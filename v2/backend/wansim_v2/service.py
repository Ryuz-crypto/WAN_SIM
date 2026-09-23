from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from threading import Lock, Timer

from . import __version__
from .models import CommandAction, ConfigurationRecord, DeploymentRecord, LanMode, Topology, TopologyConfig
from .network import ApplyError, ApplyOutcome, NetworkAgent
from .repository import ConfigRepository


class DeploymentService:
    def __init__(self, repository: ConfigRepository, agent: NetworkAgent):
        self.repository = repository
        self.agent = agent
        self._deployment_lock = Lock()
        self._confirmation_timers: dict[str, Timer] = {}
        self.confirmation_timeout = max(15, int(os.getenv("WANSIM_V2_CONFIRMATION_TIMEOUT", "45")))
        self._resume_confirmation_timers()

    def plan(self, configuration: ConfigurationRecord) -> list[dict]:
        return [action.model_dump() for action in self.agent.plan(configuration.config)]

    def review(self, configuration: ConfigurationRecord, client_ip: str | None = None) -> dict:
        preflight = self.agent.preflight(configuration.config, client_ip)
        protected = preflight.get("protected_interfaces", [])
        return {
            "configuration_id": configuration.id,
            "execution_mode": self.agent.execution_mode,
            "actions": self.plan(configuration),
            "preflight": preflight,
            "comparison": self._comparison(configuration),
            "management_confirmation_phrase": self.management_confirmation_phrase(configuration.id, protected) if protected else "",
        }

    def deploy(self, configuration: ConfigurationRecord, apply: bool, client_ip: str | None = None) -> DeploymentRecord:
        with self._deployment_lock:
            return self._deploy_locked(configuration, apply, client_ip)

    def _deploy_locked(self, configuration: ConfigurationRecord, apply: bool, client_ip: str | None) -> DeploymentRecord:
        actions = self.agent.plan(configuration.config)
        active = self.repository.active_configuration()
        if not apply:
            deployment = self.repository.create_deployment(configuration.id, None, [action.model_dump() for action in actions])
            return self.repository.update_deployment(deployment.id, "PLANNED", {"mode": self.agent.execution_mode, "message": "Plan guardado; no solicitado aplicar."})
        preflight = self.agent.preflight(configuration.config, client_ip)
        if not preflight["ok"]:
            deployment = self.repository.create_deployment(configuration.id, None, [action.model_dump() for action in actions])
            return self.repository.update_deployment(deployment.id, "REJECTED", {"mode": self.agent.execution_mode, "preflight": preflight})
        snapshot = self.agent.snapshot()
        snapshot_id = self.repository.create_snapshot(active.id if active else None, active.config if active else None, snapshot, __version__)
        deployment = self.repository.create_deployment(configuration.id, snapshot_id, [action.model_dump() for action in actions])
        outcome = ApplyOutcome([], [])
        previous_actions = self.agent.plan(active.config) if active and active.id != configuration.id else []
        conflicts: list[dict] = []
        try:
            conflicts = self.agent.cleanup_conflicts(previous_actions, actions) if previous_actions else []
            outcome = self.agent.apply(actions, configuration.config)
            verification = self.agent.verify(configuration.config, preflight.get("management"))
            if not verification["ok"]:
                raise RuntimeError(f"Verificación falló: {verification}")
            cleanup = self.agent.cleanup_obsolete(previous_actions, actions) if previous_actions else []
            self.repository.activate(configuration.id)
            result = {"mode": self.agent.execution_mode, "conflicts": conflicts, "actions": outcome.results, "cleanup": cleanup, "verification": verification, "preflight": preflight}
            if self.agent.execution_mode == "host" and preflight.get("requires_management_confirmation"):
                deadline = datetime.now(timezone.utc) + timedelta(seconds=self.confirmation_timeout)
                result["confirmation_deadline"] = deadline.isoformat()
                pending = self.repository.update_deployment(deployment.id, "AWAITING_CONFIRMATION", result)
                self._schedule_confirmation_timeout(pending.id)
                return pending
            return self.repository.update_deployment(deployment.id, "APPLIED", result)
        except ApplyError as error:
            outcome = error.outcome
            failure = str(error)
        except Exception as error:
            failure = str(error)
        rollback = self.agent.rollback(outcome.applied_actions, snapshot, actions)
        recovery = self._recover_previous(active)
        status = "ROLLED_BACK" if self._results_ok([*rollback, *recovery]) else "ROLLBACK_FAILED"
        if status == "ROLLBACK_FAILED" and active:
            self.repository.deactivate(active.id)
        return self.repository.update_deployment(deployment.id, status, {"mode": self.agent.execution_mode, "error": failure, "conflicts": conflicts, "rollback": rollback, "recovery": recovery})

    def rollback(self, deployment: DeploymentRecord) -> DeploymentRecord:
        with self._deployment_lock:
            return self._rollback_locked(deployment)

    def restore_snapshot(self, snapshot_id: str) -> DeploymentRecord:
        with self._deployment_lock:
            snapshot = self.repository.get_snapshot(snapshot_id)
            if not snapshot:
                raise LookupError("Snapshot no encontrado.")
            if not self.repository.snapshot_integrity(snapshot):
                raise ValueError("El checksum del snapshot no coincide; restauración bloqueada.")
            payload = json.loads(snapshot["config_payload"])
            target = self.repository.get_configuration(snapshot["configuration_id"]) if snapshot["configuration_id"] else None
            if payload and not target:
                target = self.repository.create_configuration(f"Recuperado {snapshot_id[:8]}", TopologyConfig.model_validate(payload))
            active = self.repository.active_configuration()
            current_actions = self.agent.plan(active.config) if active else []
            target_actions = self.agent.plan(target.config) if target else []
            deployment = self.repository.create_deployment(
                target.id if target else active.id if active else f"snapshot-{snapshot_id}", snapshot_id,
                [action.model_dump() for action in target_actions],
            )
            conflicts = self.agent.cleanup_conflicts(current_actions, target_actions) if current_actions else []
            cleanup = self.agent.cleanup_obsolete(current_actions, target_actions) if current_actions else []
            restored = self.agent.rollback([], json.loads(snapshot["host_state"]), target_actions)
            recovery = self._recover_previous(target)
            status = "RESTORED" if self._results_ok([*cleanup, *restored, *recovery]) else "RESTORE_FAILED"
            if status == "RESTORED":
                if target:
                    self.repository.activate(target.id)
                elif active:
                    self.repository.deactivate(active.id)
            return self.repository.update_deployment(deployment.id, status, {
                "mode": self.agent.execution_mode, "reason": "snapshot-restore", "snapshot_id": snapshot_id,
                "conflicts": conflicts, "cleanup": cleanup, "rollback": restored, "recovery": recovery,
            })

    def restore_last_known_good(self) -> DeploymentRecord:
        snapshot = next((item for item in self.repository.list_snapshots(100) if item["integrity"]), None)
        if not snapshot:
            raise LookupError("No existe un snapshot íntegro para recuperar.")
        return self.restore_snapshot(snapshot["id"])

    def _rollback_locked(self, deployment: DeploymentRecord, reason: str = "operator") -> DeploymentRecord:
        if deployment.status not in ("APPLIED", "AWAITING_CONFIRMATION"):
            raise ValueError("Sólo se puede revertir un despliegue aplicado o pendiente de confirmación.")
        self._cancel_confirmation_timer(deployment.id)
        snapshot = self.repository.get_snapshot(self._snapshot_id(deployment))
        if not snapshot:
            raise ValueError("El despliegue no tiene un snapshot recuperable.")
        current_actions = [CommandAction.model_validate(action) for action in deployment.plan]
        previous_id = snapshot["configuration_id"]
        previous = self.repository.get_configuration(previous_id) if previous_id else None
        previous_actions = self.agent.plan(previous.config) if previous else []
        conflicts = self.agent.cleanup_conflicts(current_actions, previous_actions)
        cleanup = self.agent.cleanup_obsolete(current_actions, previous_actions)
        host_state = json.loads(snapshot["host_state"])
        restored = self.agent.rollback([], host_state, current_actions)
        recovery = self._recover_previous(previous)
        status = "ROLLED_BACK" if self._results_ok([*cleanup, *restored, *recovery]) else "ROLLBACK_FAILED"
        if status == "ROLLED_BACK" and previous:
            self.repository.activate(previous.id)
        else:
            self.repository.deactivate(deployment.configuration_id)
        return self.repository.update_deployment(deployment.id, status, {"mode": self.agent.execution_mode, "reason": reason, "conflicts": conflicts, "cleanup": cleanup, "rollback": restored, "recovery": recovery})

    def confirm_management(self, deployment: DeploymentRecord) -> DeploymentRecord:
        with self._deployment_lock:
            current = self.repository.get_deployment(deployment.id)
            if not current or current.status != "AWAITING_CONFIRMATION":
                raise ValueError("El despliegue no está esperando confirmación de conectividad.")
            self._cancel_confirmation_timer(current.id)
            result = dict(current.result)
            result["management_confirmed_at"] = datetime.now(timezone.utc).isoformat()
            return self.repository.update_deployment(current.id, "APPLIED", result)

    def _schedule_confirmation_timeout(self, deployment_id: str, delay: float | None = None) -> None:
        timer = Timer(self.confirmation_timeout if delay is None else max(0.1, delay), self._expire_confirmation, args=(deployment_id,))
        timer.daemon = True
        self._confirmation_timers[deployment_id] = timer
        timer.start()

    def _cancel_confirmation_timer(self, deployment_id: str) -> None:
        timer = self._confirmation_timers.pop(deployment_id, None)
        if timer:
            timer.cancel()

    def _expire_confirmation(self, deployment_id: str) -> None:
        with self._deployment_lock:
            deployment = self.repository.get_deployment(deployment_id)
            if deployment and deployment.status == "AWAITING_CONFIRMATION":
                try:
                    self._rollback_locked(deployment, "management-confirmation-timeout")
                except Exception as error:
                    result = dict(deployment.result)
                    result.update({"reason": "management-confirmation-timeout", "rollback_error": str(error)})
                    self.repository.update_deployment(deployment.id, "ROLLBACK_FAILED", result)

    def _resume_confirmation_timers(self) -> None:
        now = datetime.now(timezone.utc)
        for deployment in self.repository.list_deployments(50):
            if deployment.status != "AWAITING_CONFIRMATION":
                continue
            try:
                deadline = datetime.fromisoformat(str(deployment.result["confirmation_deadline"]))
                delay = (deadline - now).total_seconds()
            except (KeyError, TypeError, ValueError):
                delay = 0.1
            self._schedule_confirmation_timeout(deployment.id, delay)

    @staticmethod
    def management_confirmation_phrase(configuration_id: str, interfaces: list[str]) -> str:
        return f"RIESGO {','.join(sorted(interfaces))} {configuration_id}"

    def _comparison(self, configuration: ConfigurationRecord) -> dict:
        active = self.repository.active_configuration()
        current = self._configuration_summary(active) if active else ["Sin configuración activa"]
        proposed = self._configuration_summary(configuration)
        current_set = set(current if active else [])
        proposed_set = set(proposed)
        changes = [f"Retirar: {item}" for item in current if item not in proposed_set] if active else []
        changes.extend(f"Agregar: {item}" for item in proposed if item not in current_set)
        if not changes:
            changes.append("La topología propuesta coincide con la configuración activa.")
        return {"current_name": active.name if active else "Sin configuración activa", "proposed_name": configuration.name, "current": current, "proposed": proposed, "changes": changes}

    @staticmethod
    def _configuration_summary(configuration: ConfigurationRecord) -> list[str]:
        config = configuration.config
        if config.topology == Topology.BRIDGE and config.bridge:
            return [f"Bridge L2 {index}: {pair.input} -> {pair.output}" for index, pair in enumerate(config.bridge.pairs, start=1)]
        assert config.l3 is not None
        items = [f"DHCP LAN: {'habilitado' if config.dhcp_enabled else 'deshabilitado'}"]
        for index, link in enumerate(config.l3.links, start=1):
            lan = "acceso sin etiqueta" if link.lan_mode == LanMode.ACCESS else f"VLAN {link.start_vlan}-{link.start_vlan + link.vlans - 1}"
            wan = "DHCP" if link.wan_mode.value == "dhcp" else f"{link.wan_cidr} vía {link.wan_gateway}"
            items.append(f"Enlace {index}: {link.lan} ({lan}) -> {link.wan} ({wan})")
            items.append(f"Red LAN {index}: {config.l3.segment}.{link.base_octet}.0/24")
        return items

    def _recover_previous(self, previous: ConfigurationRecord | None) -> list[dict]:
        if not previous:
            return []
        try:
            outcome = self.agent.apply(self.agent.plan(previous.config), previous.config)
            verification = self.agent.verify(previous.config)
            return [*outcome.results, {"id": "recovery-verify", "ok": verification["ok"], "output": str(verification)}]
        except ApplyError as error:
            return [*error.outcome.results, {"id": "recovery", "ok": False, "output": str(error)}]

    @staticmethod
    def _results_ok(results: list[dict]) -> bool:
        return all(result.get("ok") is True for result in results)

    def _snapshot_id(self, deployment: DeploymentRecord) -> str:
        # DeploymentRecord intentionally exposes no storage columns beyond API data.
        with self.repository.connection() as connection:
            row = connection.execute("SELECT snapshot_id FROM deployments WHERE id = ?", (deployment.id,)).fetchone()
        return row["snapshot_id"] if row and row["snapshot_id"] else ""

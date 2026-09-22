from __future__ import annotations

import json
from threading import Lock

from .models import CommandAction, ConfigurationRecord, DeploymentRecord
from .network import ApplyError, ApplyOutcome, NetworkAgent
from .repository import ConfigRepository


class DeploymentService:
    def __init__(self, repository: ConfigRepository, agent: NetworkAgent):
        self.repository = repository
        self.agent = agent
        self._deployment_lock = Lock()

    def plan(self, configuration: ConfigurationRecord) -> list[dict]:
        return [action.model_dump() for action in self.agent.plan(configuration.config)]

    def deploy(self, configuration: ConfigurationRecord, apply: bool) -> DeploymentRecord:
        with self._deployment_lock:
            return self._deploy_locked(configuration, apply)

    def _deploy_locked(self, configuration: ConfigurationRecord, apply: bool) -> DeploymentRecord:
        actions = self.agent.plan(configuration.config)
        active = self.repository.active_configuration()
        snapshot = self.agent.snapshot()
        snapshot_id = self.repository.create_snapshot(active.id if active else None, active.config if active else None, snapshot)
        deployment = self.repository.create_deployment(configuration.id, snapshot_id, [action.model_dump() for action in actions])
        if not apply:
            return self.repository.update_deployment(deployment.id, "PLANNED", {"mode": self.agent.execution_mode, "message": "Plan guardado; no solicitado aplicar."})
        preflight = self.agent.preflight(configuration.config)
        if not preflight["ok"]:
            return self.repository.update_deployment(deployment.id, "REJECTED", {"mode": self.agent.execution_mode, "preflight": preflight})
        outcome = ApplyOutcome([], [])
        previous_actions = self.agent.plan(active.config) if active and active.id != configuration.id else []
        conflicts: list[dict] = []
        try:
            conflicts = self.agent.cleanup_conflicts(previous_actions, actions) if previous_actions else []
            outcome = self.agent.apply(actions, configuration.config)
            verification = self.agent.verify(configuration.config)
            if not verification["ok"]:
                raise RuntimeError(f"Verificación falló: {verification}")
            cleanup = self.agent.cleanup_obsolete(previous_actions, actions) if previous_actions else []
            self.repository.activate(configuration.id)
            return self.repository.update_deployment(deployment.id, "APPLIED", {"mode": self.agent.execution_mode, "conflicts": conflicts, "actions": outcome.results, "cleanup": cleanup, "verification": verification})
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
            if deployment.status != "APPLIED":
                raise ValueError("Sólo se puede revertir un despliegue APPLIED.")
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
            return self.repository.update_deployment(deployment.id, status, {"mode": self.agent.execution_mode, "conflicts": conflicts, "cleanup": cleanup, "rollback": restored, "recovery": recovery})

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

from __future__ import annotations

from .models import ConfigurationRecord, DeploymentRecord
from .network import NetworkAgent
from .repository import ConfigRepository


class DeploymentService:
    def __init__(self, repository: ConfigRepository, agent: NetworkAgent):
        self.repository = repository
        self.agent = agent

    def plan(self, configuration: ConfigurationRecord) -> list[dict]:
        return [action.model_dump() for action in self.agent.plan(configuration.config)]

    def deploy(self, configuration: ConfigurationRecord, apply: bool) -> DeploymentRecord:
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
        try:
            applied = self.agent.apply(actions)
            verification = self.agent.verify(configuration.config)
            if not verification["ok"]:
                raise RuntimeError(f"Verificación falló: {verification}")
            self.repository.activate(configuration.id)
            return self.repository.update_deployment(deployment.id, "APPLIED", {"mode": self.agent.execution_mode, "actions": applied, "verification": verification})
        except Exception as error:
            rollback = self.agent.rollback(actions, snapshot)
            return self.repository.update_deployment(deployment.id, "ROLLED_BACK", {"mode": self.agent.execution_mode, "error": str(error), "rollback": rollback})

    def rollback(self, deployment: DeploymentRecord) -> DeploymentRecord:
        snapshot = self.repository.get_snapshot(self._snapshot_id(deployment))
        actions = deployment.plan
        from .models import CommandAction
        rollback = self.agent.rollback([CommandAction.model_validate(action) for action in actions], __import__("json").loads(snapshot["host_state"]) if snapshot else {})
        previous_id = snapshot["configuration_id"] if snapshot else ""
        if previous_id and self.repository.get_configuration(previous_id):
            self.repository.activate(previous_id)
        else:
            self.repository.deactivate(deployment.configuration_id)
        return self.repository.update_deployment(deployment.id, "ROLLED_BACK", {"mode": self.agent.execution_mode, "rollback": rollback})

    def _snapshot_id(self, deployment: DeploymentRecord) -> str:
        # DeploymentRecord intentionally exposes no storage columns beyond API data.
        with self.repository.connection() as connection:
            row = connection.execute("SELECT snapshot_id FROM deployments WHERE id = ?", (deployment.id,)).fetchone()
        return row["snapshot_id"] if row and row["snapshot_id"] else ""

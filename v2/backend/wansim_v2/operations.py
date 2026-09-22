from __future__ import annotations

from .network import NetworkAgent
from .repository import ConfigRepository


class OperationsService:
    """Shared operational boundary for ReactUI, FastAPI and Telegram."""

    def __init__(self, repository: ConfigRepository, agent: NetworkAgent):
        self.repository = repository
        self.agent = agent

    def overview(self) -> dict:
        return {
            **self.agent.overview(),
            "active_configuration": self.repository.active_configuration(),
            "deployments": self.repository.list_deployments(20),
        }

    def netem(self, interface: str, delay_ms: float, jitter_ms: float, loss_percent: float) -> dict:
        return self.agent.apply_netem(interface, delay_ms, jitter_ms, loss_percent)

    def restart(self, service: str) -> dict:
        return self.agent.restart_service(service)

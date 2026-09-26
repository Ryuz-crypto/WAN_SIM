from __future__ import annotations

import json
import os
import secrets
import time
from pathlib import Path
from typing import Iterable

import httpx

from .agent_auth import signature
from .models import CommandAction, TopologyConfig
from .network import ApplyError, ApplyOutcome, CommandRunner, NetworkAgent


class RemoteNetworkAgent:
    """NetworkAgent-compatible client for the privileged host service."""

    def __init__(self, socket_path: str, token: str, timeout: float = 35.0):
        if len(token) < 32:
            raise ValueError("WANSIM_V2_AGENT_TOKEN debe contener al menos 32 caracteres.")
        self.socket_path = socket_path
        self.token = token
        self.client = httpx.Client(
            transport=httpx.HTTPTransport(uds=socket_path),
            base_url="http://wansim-agent",
            timeout=timeout,
        )

    @property
    def execution_mode(self) -> str:
        return self._request("GET", "/v1/health")["execution_mode"]

    def _request(self, method: str, path: str, payload: dict | None = None) -> dict | list:
        body = b"" if payload is None else json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        timestamp = str(int(time.time()))
        nonce = secrets.token_hex(16)
        headers = {
            "X-WAN-SIM-Timestamp": timestamp,
            "X-WAN-SIM-Nonce": nonce,
            "X-WAN-SIM-Signature": signature(self.token, timestamp, nonce, method, path, body),
        }
        if body:
            headers["Content-Type"] = "application/json"
        try:
            response = self.client.request(method, path, content=body, headers=headers)
        except httpx.HTTPError as error:
            raise RuntimeError(f"No se pudo contactar al agente por {self.socket_path}: {error}") from error
        if response.status_code == 409:
            detail = response.json().get("detail", {})
            outcome = ApplyOutcome(
                detail.get("outcome", {}).get("results", []),
                [CommandAction.model_validate(item) for item in detail.get("outcome", {}).get("applied_actions", [])],
            )
            raise ApplyError(detail.get("message", "El agente rechazó la aplicación."), outcome)
        if response.is_error:
            try:
                detail = response.json().get("detail", response.text)
            except ValueError:
                detail = response.text
            raise RuntimeError(f"Agente HTTP {response.status_code}: {detail}")
        return response.json()

    @staticmethod
    def _actions(actions: Iterable[CommandAction]) -> list[dict]:
        return [action.model_dump(mode="json") for action in actions]

    def interfaces(self) -> list[dict]:
        return self._request("GET", "/v1/interfaces")  # type: ignore[return-value]

    def snapshot(self) -> dict:
        return self._request("GET", "/v1/snapshot")  # type: ignore[return-value]

    def plan(self, config: TopologyConfig) -> list[CommandAction]:
        result = self._request("POST", "/v1/plan", {"config": config.model_dump(mode="json", by_alias=True)})
        return [CommandAction.model_validate(item) for item in result]  # type: ignore[arg-type]

    def preflight(self, config: TopologyConfig, client_ip: str | None = None) -> dict:
        return self._request("POST", "/v1/preflight", {
            "config": config.model_dump(mode="json", by_alias=True), "client_ip": client_ip,
        })  # type: ignore[return-value]

    def apply(self, actions: Iterable[CommandAction], config: TopologyConfig | None = None) -> ApplyOutcome:
        result = self._request("POST", "/v1/apply", {
            "actions": self._actions(actions),
            "config": config.model_dump(mode="json", by_alias=True) if config else None,
        })
        return ApplyOutcome(result["results"], [CommandAction.model_validate(item) for item in result["applied_actions"]])  # type: ignore[index]

    def verify(self, config: TopologyConfig, management: dict | None = None) -> dict:
        return self._request("POST", "/v1/verify", {
            "config": config.model_dump(mode="json", by_alias=True), "management": management or {},
        })  # type: ignore[return-value]

    def cleanup_conflicts(self, previous: Iterable[CommandAction], current: Iterable[CommandAction]) -> list[dict]:
        return self._request("POST", "/v1/cleanup-conflicts", {"previous": self._actions(previous), "current": self._actions(current)})  # type: ignore[return-value]

    def cleanup_obsolete(self, previous: Iterable[CommandAction], current: Iterable[CommandAction]) -> list[dict]:
        return self._request("POST", "/v1/cleanup-obsolete", {"previous": self._actions(previous), "current": self._actions(current)})  # type: ignore[return-value]

    def rollback(self, actions: Iterable[CommandAction], snapshot: dict, restore_actions: Iterable[CommandAction] | None = None) -> list[dict]:
        return self._request("POST", "/v1/rollback", {
            "actions": self._actions(actions), "snapshot": snapshot,
            "restore_actions": self._actions(restore_actions or []),
        })  # type: ignore[return-value]

    def overview(self) -> dict:
        return self._request("GET", "/v1/overview")  # type: ignore[return-value]

    def apply_netem(self, interface: str, delay_ms: float, jitter_ms: float, loss_percent: float) -> dict:
        return self._request("POST", "/v1/netem", {
            "interface": interface, "delay_ms": delay_ms, "jitter_ms": jitter_ms, "loss_percent": loss_percent,
        })  # type: ignore[return-value]

    def restart_service(self, service: str) -> dict:
        return self._request("POST", "/v1/restart-service", {"service": service})  # type: ignore[return-value]

    def interface_action(self, interface: str, action: str) -> dict:
        return self._request("POST", "/v1/interface-action", {"interface": interface, "action": action})  # type: ignore[return-value]

    def release_status(self) -> dict:
        return self._request("GET", "/v1/releases")  # type: ignore[return-value]

    def schedule_update(self, version: str) -> dict:
        return self._request("POST", "/v1/update", {"version": version})  # type: ignore[return-value]

    def backup_catalog(self) -> list[dict]:
        return self._request("GET", "/v1/backups")  # type: ignore[return-value]

    def schedule_backup_restore(self, name: str) -> dict:
        return self._request("POST", "/v1/restore-backup", {"name": name})  # type: ignore[return-value]


def network_agent_from_environment() -> NetworkAgent | RemoteNetworkAgent:
    socket_path = os.getenv("WANSIM_V2_AGENT_SOCKET", "")
    token = os.getenv("WANSIM_V2_AGENT_TOKEN", "")
    if socket_path:
        if not Path(socket_path).exists():
            raise RuntimeError(f"El socket configurado del agente no existe: {socket_path}")
        return RemoteNetworkAgent(socket_path, token)
    return NetworkAgent(CommandRunner())

from __future__ import annotations

import os
import shutil
import time
from datetime import datetime, timezone

from .network import NetworkAgent
from .repository import ConfigRepository


class OperationsService:
    """Shared operational boundary for ReactUI, FastAPI and Telegram."""

    def __init__(self, repository: ConfigRepository, agent: NetworkAgent):
        self.repository = repository
        self.agent = agent
        self._traffic_sample: dict[str, tuple[float, int, int]] = {}

    def overview(self) -> dict:
        agent_overview = self.agent.overview()
        sampled_at = time.monotonic()
        for interface in agent_overview.get("interfaces", []):
            name = interface["name"]
            rx, tx = int(interface.get("rx_bytes", 0)), int(interface.get("tx_bytes", 0))
            previous = self._traffic_sample.get(name)
            rx_mbps = tx_mbps = 0.0
            if previous and sampled_at > previous[0]:
                elapsed = sampled_at - previous[0]
                rx_mbps = max(0.0, (rx - previous[1]) * 8 / elapsed / 1_000_000)
                tx_mbps = max(0.0, (tx - previous[2]) * 8 / elapsed / 1_000_000)
            interface.update({"rx_mbps": round(rx_mbps, 3), "tx_mbps": round(tx_mbps, 3), "total_mbps": round(rx_mbps + tx_mbps, 3)})
            self._traffic_sample[name] = (sampled_at, rx, tx)
        return {
            **agent_overview,
            "active_configuration": self.repository.active_configuration(),
            "deployments": self.repository.list_deployments(20),
        }

    def netem(self, interface: str, delay_ms: float, jitter_ms: float, loss_percent: float) -> dict:
        return self.agent.apply_netem(interface, delay_ms, jitter_ms, loss_percent)

    def restart(self, service: str) -> dict:
        return self.agent.restart_service(service)

    def interface_action(self, interface: str, action: str) -> dict:
        return self.agent.interface_action(interface, action)

    def release_status(self) -> dict:
        return self.agent.release_status()

    def schedule_update(self, version: str) -> dict:
        return self.agent.schedule_update(version)

    def doctor(self) -> dict:
        checks: list[dict] = []

        def add(component: str, status: str, title: str, detail: str, remediation: str = "", restart_service: str = "") -> None:
            checks.append({
                "component": component, "status": status, "title": title, "detail": detail,
                "remediation": remediation, "restart_service": restart_service,
            })

        try:
            agent_state = self.agent.overview()
            add("agent", "ok", "Agente de red disponible", f"Modo {agent_state.get('execution_mode', 'desconocido')}.")
        except Exception as error:
            agent_state = {"interfaces": [], "services": [], "leases": []}
            add("agent", "error", "Agente de red no disponible", str(error), "Revisa el socket y reinicia wansim-agent.service.", "wansim-agent.service")

        interfaces = agent_state.get("interfaces", [])
        if interfaces:
            management = [item["name"] for item in interfaces if item.get("is_management")]
            add("network", "ok" if management else "warning", f"{len(interfaces)} interfaces detectadas", f"Ruta administrativa: {', '.join(management) if management else 'no identificada'}.", "Conserva acceso por consola si la ruta administrativa no aparece.")
        else:
            add("network", "error", "Sin interfaces detectadas", "El agente no devolvió interfaces.", "Comprueba iproute2 y permisos del agente.")

        for service in agent_state.get("services", []):
            active = service.get("active") == "active"
            relevant = service["name"] in {"docker.service", "wansim-agent.service", "wansim-control-plane.service"}
            status = "ok" if active else "error" if relevant else "warning"
            restartable = service["name"] if service["name"] != "docker.service" else ""
            add("service", status, service["name"], f"Estado {service.get('active')} / inicio {service.get('enabled')}.", "Revisa journalctl y reinicia el componente.", restartable)

        integrity = self.repository.sqlite_integrity()
        add("database", "ok" if integrity == "ok" else "error", "Integridad SQLite", integrity, "Restaura un respaldo validado si la integridad no es ok.")
        usage = shutil.disk_usage(self.repository.database.parent)
        free_gib = usage.free / 1024**3
        add("storage", "ok" if free_gib >= 1 else "error", "Espacio de datos", f"{free_gib:.2f} GiB libres.", "Libera al menos 1 GiB antes de aplicar cambios.")

        bots = self.repository.list_telegram_bots()
        enabled_bots = [item for item in bots if item.enabled]
        unsynchronized = [item.name for item in enabled_bots if not item.webhook_url]
        add("telegram", "warning" if unsynchronized else "ok", "Bots de Telegram", f"{len(enabled_bots)} habilitados; {len(unsynchronized)} sin webhook.", "Sincroniza los bots habilitados que no tengan webhook.")

        https_mode = os.getenv("WANSIM_HTTPS_MODE", "unknown")
        add("tls", "warning" if https_mode in {"off", "unknown"} else "ok", "Publicación TLS", f"Modo HTTPS: {https_mode}.", "Configura HTTPS antes de publicar ReactUI fuera del laboratorio.")
        totals = {name: sum(1 for item in checks if item["status"] == name) for name in ("ok", "warning", "error")}
        return {
            "generated_at": datetime.now(timezone.utc).isoformat(), "status": "error" if totals["error"] else "warning" if totals["warning"] else "ok",
            "summary": totals, "checks": checks,
        }

    def backups(self) -> list[dict]:
        return self.agent.backup_catalog()

    def restore_backup(self, name: str) -> dict:
        return self.agent.schedule_backup_restore(name)

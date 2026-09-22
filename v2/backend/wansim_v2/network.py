from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable

from .models import CommandAction, LanMode, Topology, TopologyConfig, WanAddressing


@dataclass
class CommandResult:
    ok: bool
    command: list[str]
    output: str


class CommandRunner:
    """Runs only argument-vector commands and defaults to a harmless simulation."""

    def __init__(self, mode: str | None = None):
        configured = mode or os.getenv("WANSIM_V2_EXECUTION_MODE", "dry-run")
        self.mode = "host" if configured == "host" and os.getenv("WANSIM_V2_ALLOW_HOST_APPLY") == "1" else "dry-run"

    def run(self, command: list[str], *, input_data: str | None = None, timeout: int = 25) -> CommandResult:
        if self.mode != "host":
            return CommandResult(True, command, "dry-run")
        try:
            process = subprocess.run(command, input=input_data, text=True, capture_output=True, timeout=timeout, check=False)
            return CommandResult(process.returncode == 0, command, (process.stdout or process.stderr).strip())
        except (OSError, subprocess.SubprocessError) as error:
            return CommandResult(False, command, str(error))

    def probe(self, command: list[str], *, timeout: int = 10) -> CommandResult:
        """Read-only commands remain available while mutations are in dry-run mode."""
        try:
            process = subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)
            return CommandResult(process.returncode == 0, command, (process.stdout or process.stderr).strip())
        except (OSError, subprocess.SubprocessError) as error:
            return CommandResult(False, command, str(error))


class NetworkAgent:
    """Host-side planner and executor. It never accepts shell strings from API clients."""

    def __init__(self, runner: CommandRunner | None = None):
        self.runner = runner or CommandRunner()

    @property
    def execution_mode(self) -> str:
        return self.runner.mode

    def interfaces(self) -> list[dict]:
        links = self.runner.probe(["ip", "-j", "-s", "link", "show"])
        addresses = self.runner.probe(["ip", "-j", "addr", "show"])
        if not links.ok:
            return []
        try:
            ip_map = {
                item.get("ifname"): [address.get("local") for group in item.get("addr_info", []) if group.get("family") == "inet" for address in [group]]
                for item in json.loads(addresses.output or "[]")
            }
            items = []
            for item in json.loads(links.output):
                if item.get("ifname") == "lo":
                    continue
                stats = item.get("stats64", {})
                items.append({
                    "name": item["ifname"], "mac": item.get("address", ""), "state": item.get("operstate", "UNKNOWN"),
                    "ips": ip_map.get(item.get("ifname"), []),
                    "rx_bytes": stats.get("rx", {}).get("bytes", 0), "tx_bytes": stats.get("tx", {}).get("bytes", 0),
                })
            return items
        except json.JSONDecodeError:
            return []

    def snapshot(self) -> dict:
        captured_at = datetime.now(UTC).isoformat()
        probes = {
            "links": ["ip", "-j", "link", "show"],
            "addresses": ["ip", "-j", "addr", "show"],
            "routes": ["ip", "-j", "route", "show"],
            "qdisc": ["tc", "qdisc", "show"],
        }
        network = {key: self.runner.probe(command).output for key, command in probes.items()}
        iptables = self.runner.probe(["iptables-save"]).output
        return {"captured_at": captured_at, "mode": self.runner.mode, "network": network, "iptables": iptables}

    def plan(self, config: TopologyConfig) -> list[CommandAction]:
        actions: list[CommandAction] = []
        if config.topology == Topology.NAT:
            assert config.l3 is not None
            actions.append(self._action("forwarding", "prepare", "Habilitar IPv4 forwarding", ["sysctl", "-w", "net.ipv4.ip_forward=1"]))
            for link_index, link in enumerate(config.l3.links, start=1):
                actions.append(self._action(f"wan-up-{link_index}", "prepare", f"Activar WAN {link.wan}", ["ip", "link", "set", link.wan, "up"]))
                actions.append(self._action(f"lan-up-{link_index}", "prepare", f"Activar LAN {link.lan}", ["ip", "link", "set", link.lan, "up"]))
                if link.wan_mode == WanAddressing.MANUAL:
                    actions.append(self._action(f"wan-address-{link_index}", "apply", f"Configurar WAN manual {link.wan}", ["ip", "addr", "replace", link.wan_cidr or "", "dev", link.wan]))
                    actions.append(self._action(f"wan-route-{link_index}", "apply", f"Configurar gateway WAN {link.wan}", ["ip", "route", "replace", "default", "via", link.wan_gateway or "", "dev", link.wan, "metric", str(200 + link_index)]))
                else:
                    actions.append(self._action(f"wan-dhcp-{link_index}", "apply", f"Renovar DHCP de WAN {link.wan}", ["dhclient", link.wan]))
                for offset in range(link.vlans):
                    octet = link.base_octet + offset
                    subnet = f"{config.l3.segment}.{octet}.0/24"
                    address = f"{config.l3.segment}.{octet}.1/24"
                    if link.lan_mode == LanMode.ACCESS:
                        interface = link.lan
                        actions.append(self._action(f"access-address-{link_index}", "apply", f"Configurar acceso sin etiqueta {interface}", ["ip", "addr", "replace", address, "dev", interface], ["ip", "addr", "del", address, "dev", interface]))
                    else:
                        vlan_id = link.start_vlan + offset
                        interface = f"v{link_index}_{vlan_id}"
                        actions.append(self._action(f"vlan-create-{link_index}-{vlan_id}", "apply", f"Crear VLAN {vlan_id} en {link.lan}", ["ip", "link", "add", "link", link.lan, "name", interface, "type", "vlan", "id", str(vlan_id)], ["ip", "link", "del", interface]))
                        actions.append(self._action(f"vlan-address-{link_index}-{vlan_id}", "apply", f"Asignar {address} a {interface}", ["ip", "addr", "replace", address, "dev", interface]))
                        actions.append(self._action(f"vlan-up-{link_index}-{vlan_id}", "apply", f"Activar {interface}", ["ip", "link", "set", interface, "up"]))
                    actions.append(self._action(f"nat-{link_index}-{offset}", "apply", f"NAT {subnet} por {link.wan}", ["iptables", "-t", "nat", "-A", "WANSIM_POSTROUTING", "-s", subnet, "-o", link.wan, "-j", "MASQUERADE"], ["iptables", "-t", "nat", "-D", "WANSIM_POSTROUTING", "-s", subnet, "-o", link.wan, "-j", "MASQUERADE"]))
            if config.dhcp_enabled:
                actions.append(self._action("dhcp", "apply", "Regenerar y reiniciar DHCP desde el agente", ["wansim-agent", "dhcp", "apply"]))
        else:
            assert config.bridge is not None
            for index, pair in enumerate(config.bridge.pairs, start=1):
                bridge = f"br_wan{index}"
                actions.extend([
                    self._action(f"bridge-create-{index}", "apply", f"Crear bridge {bridge}", ["ip", "link", "add", "name", bridge, "type", "bridge"], ["ip", "link", "del", bridge]),
                    self._action(f"bridge-in-{index}", "apply", f"Agregar {pair.input} a {bridge}", ["ip", "link", "set", pair.input, "master", bridge], ["ip", "link", "set", pair.input, "nomaster"]),
                    self._action(f"bridge-out-{index}", "apply", f"Agregar {pair.output} a {bridge}", ["ip", "link", "set", pair.output, "master", bridge], ["ip", "link", "set", pair.output, "nomaster"]),
                    self._action(f"bridge-up-{index}", "apply", f"Activar {bridge}", ["ip", "link", "set", bridge, "up"]),
                ])
        actions.append(self._action("verify", "verify", "Verificar interfaces y topología aplicada", ["wansim-agent", "verify"]))
        return actions

    def apply(self, actions: Iterable[CommandAction]) -> list[dict]:
        results: list[dict] = []
        for action in actions:
            if action.command[0] == "wansim-agent":
                results.append({"id": action.id, "ok": True, "output": "handled-by-agent"})
                continue
            result = self.runner.run(action.command)
            results.append({"id": action.id, "ok": result.ok, "output": result.output})
            if not result.ok:
                raise RuntimeError(f"{action.description}: {result.output}")
        return results

    def verify(self, config: TopologyConfig) -> dict:
        if self.runner.mode == "dry-run":
            return {"ok": True, "mode": "dry-run", "message": "Plan validado; no se modificó el host."}
        interfaces = {item["name"] for item in self.interfaces()}
        required = set()
        if config.topology == Topology.NAT and config.l3:
            for index, link in enumerate(config.l3.links, start=1):
                required.update((link.wan, link.lan))
                if link.lan_mode == LanMode.VLAN:
                    required.update(f"v{index}_{link.start_vlan + offset}" for offset in range(link.vlans))
        elif config.bridge:
            required.update(interface for pair in config.bridge.pairs for interface in (pair.input, pair.output))
        missing = sorted(required - interfaces)
        return {"ok": not missing, "mode": "host", "missing_interfaces": missing}

    def preflight(self, config: TopologyConfig) -> dict:
        """Confirm selected physical interfaces before a host-mode transaction begins."""
        if self.runner.mode == "dry-run":
            return {"ok": True, "mode": "dry-run", "missing_interfaces": []}
        available = {item["name"] for item in self.interfaces()}
        required: set[str] = set()
        if config.topology == Topology.NAT and config.l3:
            required = {interface for link in config.l3.links for interface in (link.wan, link.lan)}
        elif config.bridge:
            required = {interface for pair in config.bridge.pairs for interface in (pair.input, pair.output)}
        missing = sorted(required - available)
        return {"ok": not missing, "mode": "host", "missing_interfaces": missing}

    def service_statuses(self) -> list[dict]:
        services = ("wansim.service", "wansim-l2-persist.service", "isc-dhcp-server", "dhcpd", "iptables")
        output = []
        for service in services:
            active = self.runner.probe(["systemctl", "is-active", service])
            enabled = self.runner.probe(["systemctl", "is-enabled", service])
            output.append({
                "name": service,
                "active": active.output if active.ok else "unavailable",
                "enabled": enabled.output if enabled.ok else "unavailable",
            })
        return output

    def dhcp_leases(self) -> list[dict]:
        for path in (Path("/var/lib/dhcp/dhcpd.leases"), Path("/var/lib/dhcpd/dhcpd.leases")):
            try:
                content = path.read_text(encoding="utf-8", errors="ignore")
                break
            except OSError:
                content = ""
        leases = []
        for match in re.finditer(r"lease\s+([0-9.]+)\s+\{(.*?)\}", content, re.DOTALL):
            body = match.group(2)
            def group(pattern: str) -> str:
                value = re.search(pattern, body)
                return value.group(1) if value else ""
            leases.append({"ip": match.group(1), "mac": group(r"hardware\s+ethernet\s+([^;]+);"), "host": group(r'client-hostname\s+"([^\"]+)"'), "state": group(r"binding\s+state\s+([^;]+);")})
        return leases[-100:]

    def apply_netem(self, interface: str, delay_ms: float, jitter_ms: float, loss_percent: float) -> dict:
        if self.runner.mode == "host" and interface not in {item["name"] for item in self.interfaces()}:
            return {"ok": False, "error": f"Interfaz no encontrada: {interface}"}
        if delay_ms == 0 and jitter_ms == 0 and loss_percent == 0:
            result = self.runner.run(["tc", "qdisc", "del", "dev", interface, "root"])
        else:
            command = ["tc", "qdisc", "replace", "dev", interface, "root", "netem", "delay", f"{delay_ms}ms"]
            if jitter_ms:
                command.append(f"{jitter_ms}ms")
            if loss_percent:
                command.extend(["loss", f"{loss_percent}%"])
            result = self.runner.run(command)
        return {"ok": result.ok, "mode": self.runner.mode, "command": result.command, "output": result.output}

    def restart_service(self, service: str) -> dict:
        allowed = {"wansim.service", "wansim-l2-persist.service", "isc-dhcp-server", "dhcpd", "iptables"}
        if service not in allowed:
            return {"ok": False, "error": "Servicio no permitido."}
        result = self.runner.run(["systemctl", "restart", service])
        return {"ok": result.ok, "mode": self.runner.mode, "command": result.command, "output": result.output}

    def overview(self) -> dict:
        return {
            "execution_mode": self.execution_mode,
            "interfaces": self.interfaces(),
            "services": self.service_statuses(),
            "leases": self.dhcp_leases(),
        }

    def rollback(self, actions: Iterable[CommandAction], snapshot: dict) -> list[dict]:
        results: list[dict] = []
        for action in reversed(list(actions)):
            if not action.undo:
                continue
            result = self.runner.run(action.undo)
            results.append({"id": action.id, "ok": result.ok, "output": result.output})
        if self.runner.mode == "host" and snapshot.get("iptables"):
            result = self.runner.run(["iptables-restore"], input_data=snapshot["iptables"])
            results.append({"id": "iptables-restore", "ok": result.ok, "output": result.output})
        return results

    @staticmethod
    def _action(action_id: str, phase: str, description: str, command: list[str], undo: list[str] | None = None) -> CommandAction:
        return CommandAction(id=action_id, phase=phase, description=description, command=command, undo=undo)

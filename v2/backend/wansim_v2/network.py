from __future__ import annotations

import json
import os
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


class NetworkAgent:
    """Host-side planner and executor. It never accepts shell strings from API clients."""

    def __init__(self, runner: CommandRunner | None = None):
        self.runner = runner or CommandRunner()

    @property
    def execution_mode(self) -> str:
        return self.runner.mode

    def interfaces(self) -> list[dict]:
        result = self.runner.run(["ip", "-j", "link", "show"])
        if not result.ok or result.output == "dry-run":
            return []
        try:
            return [
                {"name": item["ifname"], "mac": item.get("address", ""), "state": item.get("operstate", "UNKNOWN")}
                for item in json.loads(result.output)
                if item.get("ifname") != "lo"
            ]
        except json.JSONDecodeError:
            return []

    def snapshot(self) -> dict:
        captured_at = datetime.now(UTC).isoformat()
        if self.runner.mode != "host":
            return {"captured_at": captured_at, "mode": "dry-run", "network": {}, "iptables": ""}
        probes = {
            "links": ["ip", "-j", "link", "show"],
            "addresses": ["ip", "-j", "addr", "show"],
            "routes": ["ip", "-j", "route", "show"],
            "qdisc": ["tc", "qdisc", "show"],
        }
        network = {key: self.runner.run(command).output for key, command in probes.items()}
        iptables = self.runner.run(["iptables-save"]).output
        return {"captured_at": captured_at, "mode": "host", "network": network, "iptables": iptables}

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
                    actions.append(self._action(f"nat-{link_index}-{offset}", "apply", f"NAT {subnet} por {link.wan}", ["iptables", "-t", "nat", "-A", "WANSIM_POSTROUTING", "-s", subnet, "-o", link.wan, "-j", "MASQUERADE"]))
            if config.dhcp_enabled:
                actions.append(self._action("dhcp", "apply", "Regenerar y reiniciar DHCP desde el agente", ["wansim-agent", "dhcp", "apply"]))
        else:
            assert config.bridge is not None
            for index, pair in enumerate(config.bridge.pairs, start=1):
                bridge = f"br_wan{index}"
                actions.extend([
                    self._action(f"bridge-create-{index}", "apply", f"Crear bridge {bridge}", ["ip", "link", "add", "name", bridge, "type", "bridge"], ["ip", "link", "del", bridge]),
                    self._action(f"bridge-in-{index}", "apply", f"Agregar {pair.input} a {bridge}", ["ip", "link", "set", pair.input, "master", bridge]),
                    self._action(f"bridge-out-{index}", "apply", f"Agregar {pair.output} a {bridge}", ["ip", "link", "set", pair.output, "master", bridge]),
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

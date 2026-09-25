from __future__ import annotations

import json
import os
import re
import subprocess
from hashlib import sha256
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from .models import CommandAction, LanMode, Topology, TopologyConfig, WanAddressing


@dataclass
class CommandResult:
    ok: bool
    command: list[str]
    output: str


@dataclass
class ApplyOutcome:
    results: list[dict]
    applied_actions: list[CommandAction]


class ApplyError(RuntimeError):
    def __init__(self, message: str, outcome: ApplyOutcome):
        super().__init__(message)
        self.outcome = outcome


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
            management = set(self._management_path().get("interfaces", []))
            items = []
            for item in json.loads(links.output):
                if item.get("ifname") == "lo":
                    continue
                stats = item.get("stats64", {})
                items.append({
                    "name": item["ifname"], "mac": item.get("address", ""), "state": item.get("operstate", "UNKNOWN"),
                    "ips": ip_map.get(item.get("ifname"), []),
                    "rx_bytes": stats.get("rx", {}).get("bytes", 0), "tx_bytes": stats.get("tx", {}).get("bytes", 0),
                    "is_management": item["ifname"] in management,
                })
            return items
        except json.JSONDecodeError:
            return []

    def snapshot(self) -> dict:
        captured_at = datetime.now(timezone.utc).isoformat()
        probes = {
            "links": ["ip", "-j", "link", "show"],
            "addresses": ["ip", "-j", "addr", "show"],
            "routes": ["ip", "-j", "route", "show"],
            "qdisc": ["tc", "qdisc", "show"],
        }
        network = {key: self.runner.probe(command).output for key, command in probes.items()}
        iptables = self.runner.probe(["iptables-save"]).output
        forwarding = self.runner.probe(["sysctl", "-n", "net.ipv4.ip_forward"]).output
        dhcp_path = Path("/etc/dhcp/dhcpd.conf")
        try:
            dhcp_config = {"exists": True, "content": dhcp_path.read_text(encoding="utf-8")}
        except OSError:
            dhcp_config = {"exists": False, "content": ""}
        dhcp_active = next((service for service in ("isc-dhcp-server", "dhcpd") if self.runner.probe(["systemctl", "is-active", service]).ok), "")
        return {"captured_at": captured_at, "mode": self.runner.mode, "network": network, "iptables": iptables, "forwarding": forwarding, "dhcp_config": dhcp_config, "dhcp_active": dhcp_active}

    def plan(self, config: TopologyConfig) -> list[CommandAction]:
        actions: list[CommandAction] = []
        if config.topology == Topology.NAT:
            assert config.l3 is not None
            actions.append(self._action("nat-prepare", "prepare", "Preparar cadena NAT administrada", ["wansim-agent", "nat", "prepare"]))
            actions.append(self._action("forwarding", "prepare", "Habilitar IPv4 forwarding", ["sysctl", "-w", "net.ipv4.ip_forward=1"]))
            for link_index, link in enumerate(config.l3.links, start=1):
                actions.append(self._action(f"wan-up-{link_index}", "prepare", f"Activar WAN {link.wan}", ["ip", "link", "set", link.wan, "up"]))
                actions.append(self._action(f"lan-up-{link_index}", "prepare", f"Activar LAN {link.lan}", ["ip", "link", "set", link.lan, "up"]))
                if link.wan_mode == WanAddressing.MANUAL:
                    actions.append(self._action(f"wan-address-{link_index}", "apply", f"Configurar WAN manual {link.wan}", ["ip", "addr", "replace", link.wan_cidr or "", "dev", link.wan], ["ip", "addr", "del", link.wan_cidr or "", "dev", link.wan]))
                    actions.append(self._action(f"wan-route-{link_index}", "apply", f"Configurar gateway WAN {link.wan}", ["ip", "route", "replace", "default", "via", link.wan_gateway or "", "dev", link.wan, "metric", str(200 + link_index)], ["ip", "route", "del", "default", "via", link.wan_gateway or "", "dev", link.wan, "metric", str(200 + link_index)]))
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
                    actions.append(self._action(f"forward-out-{link_index}-{offset}", "apply", f"Permitir salida {interface} hacia {link.wan}", ["iptables", "-t", "filter", "-A", "WANSIM_FORWARD", "-i", interface, "-o", link.wan, "-j", "ACCEPT"], ["iptables", "-t", "filter", "-D", "WANSIM_FORWARD", "-i", interface, "-o", link.wan, "-j", "ACCEPT"]))
                    actions.append(self._action(f"forward-in-{link_index}-{offset}", "apply", f"Permitir retorno {link.wan} hacia {interface}", ["iptables", "-t", "filter", "-A", "WANSIM_FORWARD", "-i", link.wan, "-o", interface, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"], ["iptables", "-t", "filter", "-D", "WANSIM_FORWARD", "-i", link.wan, "-o", interface, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"]))
            if config.dhcp_enabled:
                actions.append(self._action("dhcp", "apply", "Regenerar y reiniciar DHCP desde el agente", ["wansim-agent", "dhcp", "apply"]))
            else:
                actions.append(self._action("dhcp-disable", "apply", "Detener DHCP administrado", ["wansim-agent", "dhcp", "disable"]))
        else:
            assert config.bridge is not None
            actions.append(self._action("forwarding-disable", "prepare", "Deshabilitar IPv4 forwarding en Bridge L2", ["sysctl", "-w", "net.ipv4.ip_forward=0"]))
            actions.append(self._action("dhcp-disable", "apply", "Detener DHCP administrado", ["wansim-agent", "dhcp", "disable"]))
            for index, pair in enumerate(config.bridge.pairs, start=1):
                bridge = f"br_wan{index}"
                actions.extend([
                    self._action(f"bridge-create-{index}", "apply", f"Crear bridge {bridge}", ["ip", "link", "add", "name", bridge, "type", "bridge"], ["ip", "link", "del", bridge]),
                    self._action(f"bridge-stp-{index}", "apply", f"Activar STP en {bridge}", ["ip", "link", "set", bridge, "type", "bridge", "stp_state", "1"]),
                    self._action(f"bridge-in-{index}", "apply", f"Agregar {pair.input} a {bridge}", ["ip", "link", "set", pair.input, "master", bridge], ["ip", "link", "set", pair.input, "nomaster"]),
                    self._action(f"bridge-out-{index}", "apply", f"Agregar {pair.output} a {bridge}", ["ip", "link", "set", pair.output, "master", bridge], ["ip", "link", "set", pair.output, "nomaster"]),
                    self._action(f"bridge-in-up-{index}", "apply", f"Activar {pair.input}", ["ip", "link", "set", pair.input, "up"]),
                    self._action(f"bridge-out-up-{index}", "apply", f"Activar {pair.output}", ["ip", "link", "set", pair.output, "up"]),
                    self._action(f"bridge-up-{index}", "apply", f"Activar {bridge}", ["ip", "link", "set", bridge, "up"]),
                ])
        actions.append(self._action("verify", "verify", "Verificar interfaces y topología aplicada", ["wansim-agent", "verify"]))
        return actions

    def apply(self, actions: Iterable[CommandAction], config: TopologyConfig | None = None) -> ApplyOutcome:
        results: list[dict] = []
        applied: list[CommandAction] = []
        for action in actions:
            if action.phase == "verify":
                continue
            result, changed = self._execute_action(action, config)
            results.append({"id": action.id, "ok": result.ok, "output": result.output})
            if not result.ok:
                raise ApplyError(f"{action.description}: {result.output}", ApplyOutcome(results, applied))
            if changed:
                applied.append(action)
        return ApplyOutcome(results, applied)

    def cleanup_obsolete(self, previous: Iterable[CommandAction], current: Iterable[CommandAction]) -> list[dict]:
        """Remove only resources whose exact undo command is absent from the new plan."""
        current_undos = {tuple(action.undo) for action in current if action.undo}
        results: list[dict] = []
        for action in reversed(list(previous)):
            if not action.undo or tuple(action.undo) in current_undos:
                continue
            result = self.runner.run(action.undo)
            missing = not result.ok and any(message in result.output for message in ("Cannot find device", "No such", "Bad rule"))
            results.append({"id": action.id, "ok": result.ok or missing, "output": result.output or ("already-absent" if missing else "")})
            if not result.ok and not missing:
                raise RuntimeError(f"No se pudo retirar {action.description}: {result.output}")
        return results

    def cleanup_conflicts(self, previous: Iterable[CommandAction], current: Iterable[CommandAction]) -> list[dict]:
        """Remove managed links that keep the same name but change their definition."""
        previous_links = {self._created_link_name(action): action for action in previous if self._created_link_name(action)}
        results: list[dict] = []
        for action in current:
            name = self._created_link_name(action)
            old = previous_links.get(name)
            if not old or old.command == action.command or not old.undo:
                continue
            if not self.runner.probe(["ip", "link", "show", name]).ok:
                results.append({"id": old.id, "ok": True, "output": "already-absent"})
                continue
            result = self.runner.run(old.undo)
            results.append({"id": old.id, "ok": result.ok, "output": result.output})
            if not result.ok:
                raise RuntimeError(f"No se pudo retirar el recurso incompatible {name}: {result.output}")
        return results

    def _execute_action(self, action: CommandAction, config: TopologyConfig | None) -> tuple[CommandResult, bool]:
        command = action.command
        if command[:3] == ["wansim-agent", "nat", "prepare"]:
            return self._prepare_nat()
        if command[:3] == ["wansim-agent", "dhcp", "apply"]:
            if config is None:
                return CommandResult(False, command, "Configuración DHCP ausente."), False
            return self._apply_dhcp(config)
        if command[:3] == ["wansim-agent", "dhcp", "disable"]:
            return self._disable_dhcp()
        if command[:3] == ["ip", "link", "add"]:
            name = command[command.index("name") + 1] if "name" in command else ""
            if name and self.runner.probe(["ip", "link", "show", name]).ok:
                if self._existing_link_matches(command, name):
                    return CommandResult(True, command, "already-present"), False
                return CommandResult(False, command, f"La interfaz {name} ya existe con otra definición."), False
        if command and command[0] == "iptables" and "-A" in command:
            check = [*command]
            check[check.index("-A")] = "-C"
            if self.runner.probe(check).ok:
                return CommandResult(True, command, "already-present"), False
        result = self.runner.run(command)
        return result, result.ok

    @staticmethod
    def _created_link_name(action: CommandAction) -> str:
        command = action.command
        if command[:3] != ["ip", "link", "add"] or "name" not in command:
            return ""
        index = command.index("name") + 1
        return command[index] if index < len(command) else ""

    def _existing_link_matches(self, command: list[str], name: str) -> bool:
        details = self.runner.probe(["ip", "-d", "-j", "link", "show", name])
        try:
            item = json.loads(details.output or "[]")[0] if details.ok else {}
        except (json.JSONDecodeError, IndexError):
            return False
        kind = ((item.get("linkinfo") or {}).get("info_kind"))
        if command[-1:] == ["bridge"] or command[-2:] == ["type", "bridge"]:
            return kind == "bridge"
        if "vlan" not in command:
            return False
        expected_id = int(command[command.index("id") + 1])
        actual_id = (((item.get("linkinfo") or {}).get("info_data") or {}).get("id"))
        parent = command[command.index("link", 2) + 1]
        parent_details = self.runner.probe(["ip", "-j", "link", "show", parent])
        try:
            parent_index = json.loads(parent_details.output or "[]")[0].get("ifindex") if parent_details.ok else None
        except (json.JSONDecodeError, IndexError):
            parent_index = None
        parent_matches = item.get("link") == parent or item.get("link_index") == parent_index
        return kind == "vlan" and actual_id == expected_id and parent_matches

    def _prepare_nat(self) -> tuple[CommandResult, bool]:
        command = ["wansim-agent", "nat", "prepare"]
        if self.runner.mode != "host":
            return CommandResult(True, command, "dry-run"), True
        changed = False
        for table, chain, parent in (("nat", "WANSIM_POSTROUTING", "POSTROUTING"), ("filter", "WANSIM_FORWARD", "FORWARD")):
            if not self.runner.probe(["iptables", "-t", table, "-S", chain]).ok:
                result = self.runner.run(["iptables", "-t", table, "-N", chain])
                if not result.ok:
                    return result, changed
                changed = True
            jump = ["iptables", "-t", table, "-C", parent, "-j", chain]
            if not self.runner.probe(jump).ok:
                result = self.runner.run(["iptables", "-t", table, "-A", parent, "-j", chain])
                if not result.ok:
                    return result, changed
                changed = True
        return CommandResult(True, command, "prepared" if changed else "already-present"), changed

    def _apply_dhcp(self, config: TopologyConfig) -> tuple[CommandResult, bool]:
        command = ["wansim-agent", "dhcp", "apply"]
        if self.runner.mode != "host":
            return CommandResult(True, command, "dry-run"), True
        if config.topology != Topology.NAT or not config.l3:
            return CommandResult(False, command, "DHCP sólo está disponible para L3/NAT."), False
        lines = ["authoritative;", "default-lease-time 600;", "max-lease-time 7200;", ""]
        for link in config.l3.links:
            for offset in range(link.vlans):
                prefix = f"{config.l3.segment}.{link.base_octet + offset}"
                lines.extend([
                    f"subnet {prefix}.0 netmask 255.255.255.0 {{",
                    f"  range {prefix}.100 {prefix}.200;",
                    f"  option routers {prefix}.1;",
                    "  option subnet-mask 255.255.255.0;",
                    "  option domain-name-servers 1.1.1.1, 8.8.8.8;",
                    "}", "",
                ])
        path = "/etc/dhcp/dhcpd.conf"
        written = self.runner.run(["tee", path], input_data="\n".join(lines))
        if not written.ok:
            return written, False
        validation = self.runner.run(["dhcpd", "-t", "-cf", path])
        if not validation.ok:
            return validation, True
        for service in ("isc-dhcp-server", "dhcpd"):
            restarted = self.runner.run(["systemctl", "restart", service])
            if restarted.ok:
                return CommandResult(True, command, f"configured:{service}"), True
        return CommandResult(False, command, "No se pudo reiniciar isc-dhcp-server ni dhcpd."), True

    def _disable_dhcp(self) -> tuple[CommandResult, bool]:
        command = ["wansim-agent", "dhcp", "disable"]
        if self.runner.mode != "host":
            return CommandResult(True, command, "dry-run"), True
        changed = False
        for service in ("isc-dhcp-server", "dhcpd"):
            if self.runner.probe(["systemctl", "is-active", service]).ok:
                stopped = self.runner.run(["systemctl", "stop", service])
                if not stopped.ok:
                    return stopped, changed
                changed = True
        return CommandResult(True, command, "stopped" if changed else "already-stopped"), changed

    def verify(self, config: TopologyConfig, management: dict | None = None) -> dict:
        if self.runner.mode == "dry-run":
            return {"ok": True, "mode": "dry-run", "message": "Plan validado; no se modificó el host."}
        interface_items = self.interfaces()
        interfaces = {item["name"] for item in interface_items}
        addresses = {item["name"]: set(item["ips"]) for item in interface_items}
        required: set[str] = set()
        errors: list[str] = []
        routes_probe = self.runner.probe(["ip", "-j", "route", "show"])
        try:
            routes = json.loads(routes_probe.output or "[]") if routes_probe.ok else []
        except json.JSONDecodeError:
            routes = []
        if config.topology == Topology.NAT and config.l3:
            for index, link in enumerate(config.l3.links, start=1):
                required.update((link.wan, link.lan))
                if link.wan_mode == WanAddressing.MANUAL and (link.wan_cidr or "").split("/")[0] not in addresses.get(link.wan, set()):
                    errors.append(f"WAN {link.wan} sin dirección {link.wan_cidr}")
                if link.wan_mode == WanAddressing.MANUAL and not any(route.get("dst") == "default" and route.get("gateway") == link.wan_gateway and route.get("dev") == link.wan for route in routes):
                    errors.append(f"Gateway {link.wan_gateway} ausente en {link.wan}")
                if link.wan_mode == WanAddressing.DHCP and not addresses.get(link.wan):
                    errors.append(f"WAN DHCP {link.wan} sin dirección IPv4")
                if link.lan_mode == LanMode.VLAN:
                    required.update(f"v{index}_{link.start_vlan + offset}" for offset in range(link.vlans))
                for offset in range(link.vlans):
                    interface = link.lan if link.lan_mode == LanMode.ACCESS else f"v{index}_{link.start_vlan + offset}"
                    if link.lan_mode == LanMode.VLAN:
                        vlan_id = link.start_vlan + offset
                        expected_link = ["ip", "link", "add", "link", link.lan, "name", interface, "type", "vlan", "id", str(vlan_id)]
                        if interface in interfaces and not self._existing_link_matches(expected_link, interface):
                            errors.append(f"VLAN {interface} no corresponde a {link.lan} ID {vlan_id}")
                    expected = f"{config.l3.segment}.{link.base_octet + offset}.1"
                    if expected not in addresses.get(interface, set()):
                        errors.append(f"LAN {interface} sin dirección {expected}")
                    subnet = f"{config.l3.segment}.{link.base_octet + offset}.0/24"
                    rule = ["iptables", "-t", "nat", "-C", "WANSIM_POSTROUTING", "-s", subnet, "-o", link.wan, "-j", "MASQUERADE"]
                    if not self.runner.probe(rule).ok:
                        errors.append(f"NAT ausente para {subnet} por {link.wan}")
                    forward_out = ["iptables", "-t", "filter", "-C", "WANSIM_FORWARD", "-i", interface, "-o", link.wan, "-j", "ACCEPT"]
                    forward_in = ["iptables", "-t", "filter", "-C", "WANSIM_FORWARD", "-i", link.wan, "-o", interface, "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"]
                    if not self.runner.probe(forward_out).ok or not self.runner.probe(forward_in).ok:
                        errors.append(f"Forwarding incompleto entre {interface} y {link.wan}")
            if config.dhcp_enabled and not any(self.runner.probe(["systemctl", "is-active", service]).ok for service in ("isc-dhcp-server", "dhcpd")):
                errors.append("Servicio DHCP inactivo")
        elif config.bridge:
            required.update(interface for pair in config.bridge.pairs for interface in (pair.input, pair.output))
            required.update(f"br_wan{index}" for index in range(1, len(config.bridge.pairs) + 1))
            links = self.runner.probe(["ip", "-j", "link", "show"])
            try:
                masters = {item.get("ifname"): item.get("master") for item in json.loads(links.output or "[]")}
            except json.JSONDecodeError:
                masters = {}
            details = self.runner.probe(["ip", "-d", "-j", "link", "show"])
            try:
                stp_states = {
                    item.get("ifname"): ((item.get("linkinfo") or {}).get("info_data") or {}).get("stp_state")
                    for item in json.loads(details.output or "[]")
                }
            except json.JSONDecodeError:
                stp_states = {}
            for index, pair in enumerate(config.bridge.pairs, start=1):
                bridge = f"br_wan{index}"
                for member in (pair.input, pair.output):
                    if masters.get(member) != bridge:
                        errors.append(f"{member} no pertenece a {bridge}")
                if stp_states.get(bridge) != 1:
                    errors.append(f"STP inactivo en {bridge}")
        missing = sorted(required - interfaces)
        errors.extend(f"Interfaz ausente: {name}" for name in missing)
        management_check = self.verify_management_path(management or {})
        if not management_check["ok"]:
            errors.extend(management_check["errors"])
        return {"ok": not errors, "mode": "host", "missing_interfaces": missing, "errors": errors, "management": management_check}

    def preflight(self, config: TopologyConfig, client_ip: str | None = None) -> dict:
        """Inspect selected interfaces and management routing before a transaction."""
        interface_items = self.interfaces()
        available = {item["name"] for item in interface_items}
        by_name = {item["name"]: item for item in interface_items}
        required: set[str] = set()
        if config.topology == Topology.NAT and config.l3:
            required = {interface for link in config.l3.links for interface in (link.wan, link.lan)}
        elif config.bridge:
            required = {interface for pair in config.bridge.pairs for interface in (pair.input, pair.output)}
        missing = sorted(required - available)
        management = self._management_path(client_ip)
        management_interfaces = set(management.get("interfaces", []))
        protected = sorted(required & management_interfaces)
        management["protected_interfaces"] = protected
        issues: list[dict] = []
        for interface in missing:
            issues.append(self._issue(
                "error" if self.runner.mode == "host" else "warning", "interface_missing",
                f"Interfaz no disponible: {interface}",
                "El host no reporta esta interfaz. En dry-run puede pertenecer al equipo donde se aplicará después.", [interface],
            ))
        for interface in protected:
            issues.append(self._issue(
                "warning", "management_interface", f"{interface} transporta la administración",
                "Modificar esta interfaz puede interrumpir ReactUI o SSH. Se activará recuperación automática.", [interface],
            ))
        for interface in sorted(required & available):
            item = by_name[interface]
            if item.get("state") not in ("UP", "UNKNOWN"):
                issues.append(self._issue(
                    "recommendation", "interface_down", f"{interface} está {item.get('state', 'DOWN')}",
                    "WAN_SIM la activará durante el despliegue; comprueba cableado y enlace.", [interface],
                ))
        if not management_interfaces:
            issues.append(self._issue(
                "recommendation", "management_unknown", "Ruta de administración no identificada",
                "Conserva acceso por consola durante el primer despliegue real.", [],
            ))
        if config.topology == Topology.BRIDGE and config.bridge:
            for pair in config.bridge.pairs:
                addressed = [name for name in (pair.input, pair.output) if by_name.get(name, {}).get("ips")]
                if addressed:
                    issues.append(self._issue(
                        "warning", "bridge_addressed_member", "Bridge con interfaz direccionada",
                        "Las direcciones actuales pueden dejar de ser alcanzables al convertir el puerto en miembro L2.", addressed,
                    ))
        errors = [item for item in issues if item["severity"] == "error"]
        return {
            "ok": not errors,
            "can_apply": not errors,
            "mode": self.runner.mode,
            "missing_interfaces": missing,
            "selected_interfaces": sorted(required),
            "management_interfaces": sorted(management_interfaces),
            "protected_interfaces": protected,
            "requires_management_confirmation": bool(protected),
            "management": management,
            "issues": issues,
        }

    def verify_management_path(self, management: dict) -> dict:
        original = set(management.get("protected_interfaces") or management.get("interfaces", []))
        target = str(management.get("target") or "")
        if self.runner.mode != "host" or not original or not target:
            return {"ok": True, "interfaces": sorted(original), "errors": []}
        current = self._management_path(target)
        current_interfaces = set(current.get("interfaces", []))
        if original & current_interfaces:
            return {"ok": True, "interfaces": sorted(current_interfaces), "errors": []}
        return {
            "ok": False,
            "interfaces": sorted(current_interfaces),
            "errors": [f"La ruta de administración hacia {target} dejó de usar {', '.join(sorted(original))}."],
        }

    def _management_path(self, client_ip: str | None = None) -> dict:
        target = client_ip or "1.1.1.1"
        route = self.runner.probe(["ip", "-j", "route", "get", target])
        routes: list[dict] = []
        try:
            routes = json.loads(route.output or "[]") if route.ok else []
        except json.JSONDecodeError:
            routes = []
        if not routes and client_ip:
            target = "1.1.1.1"
            fallback = self.runner.probe(["ip", "-j", "route", "get", target])
            try:
                routes = json.loads(fallback.output or "[]") if fallback.ok else []
            except json.JSONDecodeError:
                routes = []
        defaults = self.runner.probe(["ip", "-j", "route", "show", "default"])
        try:
            routes.extend(json.loads(defaults.output or "[]") if defaults.ok else [])
        except json.JSONDecodeError:
            pass
        interfaces = sorted({str(item.get("dev")) for item in routes if item.get("dev")})
        gateways = sorted({str(item.get("gateway")) for item in routes if item.get("gateway")})
        return {"target": target, "client_ip": client_ip or "", "interfaces": interfaces, "gateways": gateways}

    @staticmethod
    def _issue(severity: str, code: str, title: str, detail: str, interfaces: list[str]) -> dict:
        return {"severity": severity, "code": code, "title": title, "detail": detail, "interfaces": interfaces}

    def service_statuses(self) -> list[dict]:
        services = (
            "docker.service", "wansim-agent.service", "wansim-control-plane.service", "wansim.service",
            "wansim-l2-persist.service", "isc-dhcp-server", "dhcpd", "iptables",
        )
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
            if not result.ok and any(message in result.output for message in ("No such file", "Cannot delete qdisc with handle of zero")):
                result = CommandResult(True, result.command, "already-reset")
        else:
            command = ["tc", "qdisc", "replace", "dev", interface, "root", "netem", "delay", f"{delay_ms}ms"]
            if jitter_ms:
                command.append(f"{jitter_ms}ms")
            if loss_percent:
                command.extend(["loss", f"{loss_percent}%"])
            result = self.runner.run(command)
        return {"ok": result.ok, "mode": self.runner.mode, "command": result.command, "output": result.output}

    def restart_service(self, service: str) -> dict:
        allowed = {
            "wansim.service", "wansim-l2-persist.service", "wansim-agent.service",
            "wansim-control-plane.service", "isc-dhcp-server", "dhcpd", "iptables",
        }
        if service not in allowed:
            return {"ok": False, "error": "Servicio no permitido."}
        command = ["systemctl", "--no-block", "restart", service] if service.startswith("wansim-") else ["systemctl", "restart", service]
        result = self.runner.run(command)
        return {"ok": result.ok, "mode": self.runner.mode, "command": result.command, "output": result.output}

    def overview(self) -> dict:
        return {
            "execution_mode": self.execution_mode,
            "interfaces": self.interfaces(),
            "services": self.service_statuses(),
            "leases": self.dhcp_leases(),
        }

    def backup_catalog(self) -> list[dict]:
        root = Path(os.getenv("WANSIM_BACKUP_DIR", "/var/backups/wansim"))
        output = []
        try:
            archives = sorted(root.glob("wansim-*.tar.gz"), key=lambda item: item.stat().st_mtime, reverse=True)
        except OSError:
            return []
        for archive in archives[:50]:
            checksum_file = Path(f"{archive}.sha256")
            try:
                expected = checksum_file.read_text(encoding="utf-8").split()[0]
                digest = sha256()
                with archive.open("rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                integrity = digest.hexdigest() == expected
                size = archive.stat().st_size
                created_at = datetime.fromtimestamp(archive.stat().st_mtime, timezone.utc).isoformat()
            except (OSError, IndexError):
                expected, integrity, size, created_at = "", False, 0, ""
            output.append({"name": archive.name, "size": size, "created_at": created_at, "checksum": expected, "integrity": integrity})
        return output

    def schedule_backup_restore(self, name: str) -> dict:
        if not re.fullmatch(r"wansim-[A-Za-z0-9._~-]+\.tar\.gz", name):
            return {"ok": False, "error": "Nombre de respaldo no permitido."}
        backup = next((item for item in self.backup_catalog() if item["name"] == name), None)
        if not backup:
            return {"ok": False, "error": "Respaldo no encontrado."}
        if not backup["integrity"]:
            return {"ok": False, "error": "El checksum del respaldo no coincide."}
        archive = str(Path(os.getenv("WANSIM_BACKUP_DIR", "/var/backups/wansim")) / name)
        unit = f"wansim-restore-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"
        result = self.runner.run([
            "systemd-run", f"--unit={unit}", "--collect", "--property=Type=exec",
            "/usr/local/bin/wansim", "restore", archive,
        ])
        return {"ok": result.ok, "mode": self.runner.mode, "unit": unit, "output": result.output, "backup": name}

    def rollback(self, actions: Iterable[CommandAction], snapshot: dict, restore_actions: Iterable[CommandAction] | None = None) -> list[dict]:
        results: list[dict] = []
        applied = list(actions)
        for action in reversed(applied):
            if not action.undo:
                continue
            result = self.runner.run(action.undo)
            results.append({"id": action.id, "ok": result.ok, "output": result.output})
        if self.runner.mode == "host" and "iptables" in snapshot:
            saved_iptables = str(snapshot.get("iptables") or "")
            result = self.runner.run(["iptables-restore"], input_data=saved_iptables) if saved_iptables else CommandResult(True, ["iptables-restore"], "empty-snapshot")
            results.append({"id": "iptables-restore", "ok": result.ok, "output": result.output})
            if result.ok:
                results.extend(self._remove_new_managed_chains(saved_iptables))
        if self.runner.mode == "host":
            results.extend(self._restore_network_state(snapshot, list(restore_actions) if restore_actions is not None else applied))
            forwarding = str(snapshot.get("forwarding", "")).strip()
            if forwarding in {"0", "1"}:
                result = self.runner.run(["sysctl", "-w", f"net.ipv4.ip_forward={forwarding}"])
                results.append({"id": "forwarding-restore", "ok": result.ok, "output": result.output})
            results.extend(self._restore_dhcp(snapshot))
        return results

    def _remove_new_managed_chains(self, snapshot: str) -> list[dict]:
        """Delete nft/legacy chains that did not exist before the transaction."""
        results: list[dict] = []
        for table, chain, parent in (("nat", "WANSIM_POSTROUTING", "POSTROUTING"), ("filter", "WANSIM_FORWARD", "FORWARD")):
            if any(line.startswith(f":{chain} ") for line in snapshot.splitlines()):
                continue
            table_state = self.runner.probe(["iptables-save", "-t", table])
            if not table_state.ok:
                results.append({"id": f"iptables-inspect:{chain}", "ok": False, "output": table_state.output})
                continue
            if not any(line.startswith(f":{chain} ") for line in table_state.output.splitlines()):
                results.append({"id": f"iptables-remove:{chain}", "ok": True, "output": "already-absent"})
                continue
            jump = self.runner.run(["iptables", "-t", table, "-D", parent, "-j", chain])
            jump_missing = not jump.ok and any(message in jump.output for message in ("Bad rule", "No chain/target/match"))
            results.append({"id": f"iptables-unlink:{chain}", "ok": jump.ok or jump_missing, "output": jump.output or ("already-absent" if jump_missing else "")})
            flush = self.runner.run(["iptables", "-t", table, "-F", chain])
            results.append({"id": f"iptables-flush:{chain}", "ok": flush.ok, "output": flush.output})
            delete = self.runner.run(["iptables", "-t", table, "-X", chain])
            results.append({"id": f"iptables-remove:{chain}", "ok": delete.ok, "output": delete.output})
            current = self.runner.probe(["iptables-save", "-t", table])
            absent = current.ok and not any(line.startswith(f":{chain} ") for line in current.output.splitlines())
            results.append({"id": f"iptables-verify:{chain}", "ok": absent, "output": "absent" if absent else current.output})
        return results

    def _restore_network_state(self, snapshot: dict, actions: list[CommandAction]) -> list[dict]:
        results: list[dict] = []
        managed = self._managed_interfaces(actions)
        try:
            desired_items = json.loads(snapshot.get("network", {}).get("addresses") or "[]")
            current_items = json.loads(self.runner.probe(["ip", "-j", "addr", "show"]).output or "[]")
        except json.JSONDecodeError:
            return [{"id": "address-restore", "ok": False, "output": "Snapshot de direcciones inválido."}]
        desired = self._ipv4_map(desired_items)
        current = self._ipv4_map(current_items)
        for interface in sorted(managed):
            if not self.runner.probe(["ip", "link", "show", interface]).ok:
                continue
            for cidr in sorted(current.get(interface, set()) - desired.get(interface, set())):
                result = self.runner.run(["ip", "addr", "del", cidr, "dev", interface])
                results.append({"id": f"address-remove:{interface}:{cidr}", "ok": result.ok, "output": result.output})
            for cidr in sorted(desired.get(interface, set()) - current.get(interface, set())):
                result = self.runner.run(["ip", "addr", "replace", cidr, "dev", interface])
                results.append({"id": f"address-restore:{interface}:{cidr}", "ok": result.ok, "output": result.output})
        try:
            desired_routes = json.loads(snapshot.get("network", {}).get("routes") or "[]")
            current_routes = json.loads(self.runner.probe(["ip", "-j", "route", "show"]).output or "[]")
        except json.JSONDecodeError:
            return results + [{"id": "route-restore", "ok": False, "output": "Snapshot de rutas inválido."}]
        desired_defaults = {self._route_key(route): route for route in desired_routes if route.get("dst") == "default" and route.get("dev") in managed}
        current_defaults = {self._route_key(route): route for route in current_routes if route.get("dst") == "default" and route.get("dev") in managed}
        for key, route in current_defaults.items():
            if key not in desired_defaults:
                command = self._route_command("del", route)
                result = self.runner.run(command)
                results.append({"id": f"route-remove:{key}", "ok": result.ok, "output": result.output})
        for key, route in desired_defaults.items():
            if key not in current_defaults:
                command = self._route_command("replace", route)
                result = self.runner.run(command)
                results.append({"id": f"route-restore:{key}", "ok": result.ok, "output": result.output})
        return results

    def _restore_dhcp(self, snapshot: dict) -> list[dict]:
        state = snapshot.get("dhcp_config") or {}
        path = "/etc/dhcp/dhcpd.conf"
        results: list[dict] = []
        if state.get("exists"):
            result = self.runner.run(["tee", path], input_data=str(state.get("content", "")))
            results.append({"id": "dhcp-config-restore", "ok": result.ok, "output": result.output})
        else:
            result = self.runner.run(["rm", "-f", path])
            results.append({"id": "dhcp-config-remove", "ok": result.ok, "output": result.output})
        active = snapshot.get("dhcp_active")
        if active:
            result = self.runner.run(["systemctl", "restart", str(active)])
            results.append({"id": "dhcp-service-restore", "ok": result.ok, "output": result.output})
        else:
            for service in ("isc-dhcp-server", "dhcpd"):
                self.runner.run(["systemctl", "stop", service])
        return results

    @staticmethod
    def _ipv4_map(items: list[dict]) -> dict[str, set[str]]:
        return {
            item.get("ifname", ""): {
                f"{address['local']}/{address['prefixlen']}"
                for address in item.get("addr_info", [])
                if address.get("family") == "inet" and address.get("local") and address.get("prefixlen") is not None
            }
            for item in items
        }

    @staticmethod
    def _managed_interfaces(actions: list[CommandAction]) -> set[str]:
        interfaces: set[str] = set()
        for action in actions:
            for command in (action.command, action.undo or []):
                if "dev" in command and command.index("dev") + 1 < len(command):
                    interfaces.add(command[command.index("dev") + 1])
                if command[:3] == ["ip", "link", "set"] and len(command) > 3:
                    interfaces.add(command[3])
                if command[:4] == ["ip", "link", "add", "link"] and len(command) > 4:
                    interfaces.add(command[4])
                if "name" in command and command.index("name") + 1 < len(command):
                    interfaces.add(command[command.index("name") + 1])
        return interfaces

    @staticmethod
    def _route_key(route: dict) -> str:
        return "|".join(str(route.get(field, "")) for field in ("dst", "gateway", "dev", "metric", "table"))

    @staticmethod
    def _route_command(operation: str, route: dict) -> list[str]:
        command = ["ip", "route", operation, str(route.get("dst", "default"))]
        if route.get("gateway"):
            command.extend(["via", str(route["gateway"])])
        if route.get("dev"):
            command.extend(["dev", str(route["dev"])])
        if route.get("metric") is not None:
            command.extend(["metric", str(route["metric"])])
        if route.get("table") not in (None, "main", 254):
            command.extend(["table", str(route["table"])])
        return command

    @staticmethod
    def _action(action_id: str, phase: str, description: str, command: list[str], undo: list[str] | None = None) -> CommandAction:
        return CommandAction(id=action_id, phase=phase, description=description, command=command, undo=undo)

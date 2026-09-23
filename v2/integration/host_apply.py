"""Runs only in a disposable Linux VM/container as root; it never touches physical NICs."""
from __future__ import annotations

import json
import os
import platform
import subprocess
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from wansim_v2.models import TopologyConfig
from wansim_v2.network import CommandRunner, NetworkAgent
from wansim_v2.repository import ConfigRepository
from wansim_v2.service import DeploymentService


INTERFACES = ("wswan1", "wslan1", "wswan2", "wslan2")


def command(*args: str, check: bool = True) -> None:
    subprocess.run(args, check=check, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def exists(name: str) -> bool:
    return subprocess.run(("ip", "link", "show", name), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def succeeds(*args: str) -> bool:
    return subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def output(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def has_address(interface: str, cidr: str) -> bool:
    probe = subprocess.run(("ip", "-j", "address", "show", "dev", interface), text=True, capture_output=True)
    if probe.returncode != 0:
        return False
    expected_ip, expected_prefix = cidr.split("/", 1)
    return any(
        address.get("family") == "inet"
        and address.get("local") == expected_ip
        and str(address.get("prefixlen")) == expected_prefix
        for item in json.loads(probe.stdout or "[]")
        for address in item.get("addr_info", [])
    )


def os_release() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"')
    return values


def write_report(report: dict) -> None:
    target = os.getenv("WANSIM_INTEGRATION_REPORT")
    if not target:
        return
    path = Path(target)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def cleanup() -> None:
    for name in INTERFACES:
        command("ip", "link", "del", name, check=False)
    command("iptables", "-t", "nat", "-D", "POSTROUTING", "-j", "WANSIM_POSTROUTING", check=False)
    command("iptables", "-t", "nat", "-F", "WANSIM_POSTROUTING", check=False)
    command("iptables", "-t", "nat", "-X", "WANSIM_POSTROUTING", check=False)
    command("iptables", "-t", "filter", "-D", "FORWARD", "-j", "WANSIM_FORWARD", check=False)
    command("iptables", "-t", "filter", "-F", "WANSIM_FORWARD", check=False)
    command("iptables", "-t", "filter", "-X", "WANSIM_FORWARD", check=False)


def main() -> None:
    if os.geteuid() != 0:
        raise SystemExit("Esta prueba debe ejecutarse como root dentro de una VM descartable.")
    release = os_release()
    expected = os.getenv("WANSIM_EXPECTED_DISTRO", "")
    compatible_ids = {release.get("ID", ""), *release.get("ID_LIKE", "").split()}
    if expected and expected not in compatible_ids:
        raise SystemExit(f"Distribución inesperada: se esperaba {expected}, se obtuvo {sorted(compatible_ids)}")
    report = {
        "status": "running",
        "started_at": datetime.now(UTC).isoformat(),
        "distribution": {
            "id": release.get("ID", "unknown"),
            "version_id": release.get("VERSION_ID", "unknown"),
            "pretty_name": release.get("PRETTY_NAME", "unknown"),
        },
        "kernel": platform.release(),
        "python": platform.python_version(),
        "checks": {},
    }
    cleanup()
    try:
        forwarding_before = output("sysctl", "-n", "net.ipv4.ip_forward")
        for name in INTERFACES:
            command("ip", "link", "add", name, "type", "dummy")
            command("ip", "link", "set", name, "up")
        os.environ["WANSIM_V2_EXECUTION_MODE"] = "host"
        os.environ["WANSIM_V2_ALLOW_HOST_APPLY"] = "1"
        agent = NetworkAgent(CommandRunner())
        config = TopologyConfig.model_validate({
            "topology": "nat", "dhcpEnabled": False,
            "l3": {"segment": "10.254", "links": [
                {"wan": "wswan1", "lan": "wslan1", "lanMode": "vlan", "vlans": 1, "startVlan": 100, "baseOctet": 10,
                 "wanMode": "manual", "wanCidr": "198.18.1.2/24", "wanGateway": "198.18.1.1"},
                {"wan": "wswan2", "lan": "wslan2", "lanMode": "access", "vlans": 1, "startVlan": 200, "baseOctet": 20,
                 "wanMode": "manual", "wanCidr": "198.18.2.2/24", "wanGateway": "198.18.2.1"},
            ]},
        })
        with tempfile.TemporaryDirectory() as state:
            repository = ConfigRepository(Path(state) / "state.db")
            configuration = repository.create_configuration("Integración dos WAN", config)
            service = DeploymentService(repository, agent)
            deployed = service.deploy(configuration, apply=True)
            assert deployed.status == "APPLIED", deployed
            assert exists("v1_100"), "No se creó la VLAN de la primera LAN"
            assert has_address("v1_100", "10.254.10.1/24"), "La VLAN no recibió su dirección LAN"
            assert has_address("wslan2", "10.254.20.1/24"), "El puerto de acceso no recibió su dirección LAN"
            assert succeeds("iptables", "-t", "nat", "-C", "WANSIM_POSTROUTING", "-s", "10.254.10.0/24", "-o", "wswan1", "-j", "MASQUERADE")
            assert succeeds("iptables", "-t", "nat", "-C", "WANSIM_POSTROUTING", "-s", "10.254.20.0/24", "-o", "wswan2", "-j", "MASQUERADE")
            assert succeeds("iptables", "-t", "filter", "-C", "WANSIM_FORWARD", "-i", "v1_100", "-o", "wswan1", "-j", "ACCEPT")
            assert succeeds("iptables", "-t", "filter", "-C", "WANSIM_FORWARD", "-i", "wslan2", "-o", "wswan2", "-j", "ACCEPT")
            report["checks"]["apply"] = {
                "status": deployed.status,
                "two_wan": True,
                "vlan_lan": "v1_100:10.254.10.1/24",
                "access_lan": "wslan2:10.254.20.1/24",
                "nat_rules": 2,
                "forward_rules": 4,
            }
            rollback = service.rollback(deployed)
            assert rollback.status == "ROLLED_BACK", rollback
            assert not exists("v1_100"), "La VLAN quedó después del rollback"
            assert not has_address("wslan2", "10.254.20.1/24"), "La dirección de acceso quedó después del rollback"
            assert not has_address("wswan1", "198.18.1.2/24"), "La dirección WAN1 quedó después del rollback"
            assert not has_address("wswan2", "198.18.2.2/24"), "La dirección WAN2 quedó después del rollback"
            assert not succeeds("iptables", "-t", "nat", "-S", "WANSIM_POSTROUTING")
            assert not succeeds("iptables", "-t", "filter", "-S", "WANSIM_FORWARD")
            assert output("sysctl", "-n", "net.ipv4.ip_forward") == forwarding_before, "IPv4 forwarding no volvió al valor inicial"
            assert repository.active_configuration() is None, "La configuración quedó activa después del rollback"
            report["checks"]["rollback"] = {
                "status": rollback.status,
                "addresses_restored": True,
                "managed_links_removed": True,
                "iptables_restored": True,
                "forwarding_restored": True,
                "active_configuration": None,
            }
        report["status"] = "passed"
        print("WAN_SIM V2 integration: two WAN, VLAN/access and rollback passed.")
    except BaseException as error:
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
        annotation = report["error"].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error title=WAN_SIM host integration::{annotation}", flush=True)
        raise
    finally:
        cleanup()
        report["finished_at"] = datetime.now(UTC).isoformat()
        write_report(report)


if __name__ == "__main__":
    main()

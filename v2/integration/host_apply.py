"""Runs only in a disposable Linux VM as root; it never touches physical NICs."""
from __future__ import annotations

import os
import subprocess
import tempfile
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


def cleanup() -> None:
    for name in INTERFACES:
        command("ip", "link", "del", name, check=False)
    command("iptables", "-t", "nat", "-D", "POSTROUTING", "-j", "WANSIM_POSTROUTING", check=False)
    command("iptables", "-t", "nat", "-F", "WANSIM_POSTROUTING", check=False)
    command("iptables", "-t", "nat", "-X", "WANSIM_POSTROUTING", check=False)


def main() -> None:
    if os.geteuid() != 0:
        raise SystemExit("Esta prueba debe ejecutarse como root dentro de una VM descartable.")
    cleanup()
    try:
        for name in INTERFACES:
            command("ip", "link", "add", name, "type", "dummy")
            command("ip", "link", "set", name, "up")
        command("iptables", "-t", "nat", "-N", "WANSIM_POSTROUTING")
        command("iptables", "-t", "nat", "-A", "POSTROUTING", "-j", "WANSIM_POSTROUTING")
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
            rollback = service.rollback(deployed)
            assert rollback.status == "ROLLED_BACK", rollback
            assert not exists("v1_100"), "La VLAN quedó después del rollback"
        print("WAN_SIM V2 integration: two WAN, VLAN/access and rollback passed.")
    finally:
        cleanup()


if __name__ == "__main__":
    main()

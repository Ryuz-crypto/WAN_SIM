from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from wansim_v2.api import create_app
from wansim_v2.network import CommandRunner, NetworkAgent


class FailingRunner(CommandRunner):
    def __init__(self) -> None:
        self.mode = "host"
        self.commands: list[list[str]] = []

    def run(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command == ["ip", "-j", "link", "show"]:
            return CommandResult(True, command, '[{"ifname":"wan0"},{"ifname":"lan0"}]')
        if command[:3] == ["ip", "addr", "replace"]:
            return CommandResult(False, command, "forced address failure")
        return CommandResult(True, command, "ok")


class ApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.client = TestClient(create_app(Path(self.directory.name), NetworkAgent(CommandRunner("dry-run"))))

    def tearDown(self) -> None:
        self.directory.cleanup()

    def nat_payload(self, *, lan_mode: str = "access") -> dict:
        return {
            "name": "Laboratorio doble WAN",
            "config": {
                "topology": "nat",
                "dhcpEnabled": True,
                "l3": {"segment": "10.254", "links": [{
                    "wan": "wan0", "lan": "lan0", "lanMode": lan_mode,
                    "vlans": 2, "startVlan": 100, "baseOctet": 10,
                    "wanMode": "manual", "wanCidr": "192.0.2.2/24", "wanGateway": "192.0.2.1",
                }]},
            },
        }

    def test_health_is_dry_run_by_default(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["execution_mode"], "dry-run")

    def test_access_plan_has_no_vlan_creation(self) -> None:
        created = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        plan = self.client.post(f"/api/v2/configurations/{created['id']}/plan").json()
        commands = [item["command"] for item in plan["actions"]]
        self.assertIn(["ip", "addr", "replace", "10.254.10.1/24", "dev", "lan0"], commands)
        self.assertFalse(any("vlan" in command for command in commands))

    def test_tagged_plan_creates_vlan_interfaces(self) -> None:
        created = self.client.post("/api/v2/configurations", json=self.nat_payload(lan_mode="vlan")).json()
        plan = self.client.post(f"/api/v2/configurations/{created['id']}/plan").json()
        self.assertTrue(any(item["command"][:3] == ["ip", "link", "add"] for item in plan["actions"]))

    def test_dry_run_deploy_activates_draft_without_host_changes(self) -> None:
        created = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployed = self.client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True})
        self.assertEqual(deployed.status_code, 200)
        self.assertEqual(deployed.json()["status"], "APPLIED")
        self.assertEqual(deployed.json()["result"]["mode"], "dry-run")
        active = self.client.get("/api/v2/configurations/active/current")
        self.assertEqual(active.json()["id"], created["id"])

    def test_plan_only_does_not_activate_configuration(self) -> None:
        created = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployed = self.client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": False}).json()
        self.assertEqual(deployed["status"], "PLANNED")
        self.assertIsNone(self.client.get("/api/v2/configurations/active/current").json())

    def test_invalid_manual_wan_is_rejected(self) -> None:
        payload = self.nat_payload()
        payload["config"]["l3"]["links"][0]["wanGateway"] = "not-an-ip"
        self.assertEqual(self.client.post("/api/v2/configurations", json=payload).status_code, 422)

    def test_rollback_marks_deployment(self) -> None:
        created = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployment = self.client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True}).json()
        result = self.client.post(f"/api/v2/deployments/{deployment['id']}/rollback")
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["status"], "ROLLED_BACK")

    def test_failed_host_apply_rolls_back_and_never_activates_draft(self) -> None:
        runner = FailingRunner()
        app = create_app(Path(self.directory.name) / "failure", NetworkAgent(runner))
        client = TestClient(app)
        created = client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployment = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True}).json()
        self.assertEqual(deployment["status"], "ROLLED_BACK")
        self.assertIn("forced address failure", deployment["result"]["error"])
        self.assertIsNone(client.get("/api/v2/configurations/active/current").json())
        self.assertTrue(any(command[:3] == ["ip", "addr", "del"] for command in runner.commands))


if __name__ == "__main__":
    unittest.main()

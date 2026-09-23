from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from wansim_v2.api import create_app
from wansim_v2.network import CommandRunner, NetworkAgent
from wansim_v2.telegram import TelegramGateway

API_KEY = "test-operator-api-key-1234567890"
AUTH_HEADERS = {"X-WAN-SIM-API-Key": API_KEY}


class FailingRunner(CommandRunner):
    def __init__(self) -> None:
        self.mode = "host"
        self.commands: list[list[str]] = []

    def run(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command[:3] == ["ip", "addr", "replace"]:
            return CommandResult(False, command, "forced address failure")
        return CommandResult(True, command, "ok")

    def probe(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command == ["ip", "-j", "-s", "link", "show"]:
            return CommandResult(True, command, '[{"ifname":"wan0"},{"ifname":"lan0"}]')
        if command == ["ip", "-j", "addr", "show"]:
            return CommandResult(True, command, '[]')
        if command == ["ip", "-j", "route", "show"]:
            return CommandResult(True, command, '[]')
        if command[:2] == ["systemctl", "is-active"]:
            return CommandResult(False, command, "inactive")
        return CommandResult(True, command, "ok")


class RollbackFailingRunner(FailingRunner):
    def run(self, command: list[str], **kwargs: object):
        from wansim_v2.network import CommandResult

        if command == ["iptables-restore"]:
            self.commands.append(command)
            return CommandResult(False, command, "forced rollback failure")
        return super().run(command, **kwargs)


class StickyNftChainRunner(CommandRunner):
    def __init__(self) -> None:
        self.mode = "host"
        self.commands: list[list[str]] = []
        self.chains = {"WANSIM_POSTROUTING", "WANSIM_FORWARD"}

    def run(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if "-X" in command:
            self.chains.discard(command[-1])
        return CommandResult(True, command, "ok")

    def probe(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command[:2] == ["iptables-save", "-t"]:
            table = command[-1]
            chain = "WANSIM_POSTROUTING" if table == "nat" else "WANSIM_FORWARD"
            definition = f":{chain} - [0:0]\n" if chain in self.chains else ""
            return CommandResult(True, command, f"*{table}\n{definition}COMMIT\n")
        if command in (["ip", "-j", "addr", "show"], ["ip", "-j", "route", "show"]):
            return CommandResult(True, command, "[]")
        return CommandResult(False, command, "missing")


class RecordingTelegramGateway(TelegramGateway):
    def __init__(self) -> None:
        self.messages: list[dict] = []
        self.webhooks: list[dict] = []
        self.fail_delivery = False

    def send_message(self, token: str, chat_id: int, text: str, keyboard=None) -> dict:
        if self.fail_delivery:
            return {"ok": False, "error": "forced Telegram failure"}
        self.messages.append({"token": token, "chat_id": chat_id, "text": text, "keyboard": keyboard})
        return {"ok": True}

    def set_webhook(self, token: str, url: str, secret: str) -> dict:
        self.webhooks.append({"token": token, "url": url, "secret": secret})
        return {"ok": True}


class ApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.client = TestClient(create_app(Path(self.directory.name), NetworkAgent(CommandRunner("dry-run")), api_key=API_KEY), headers=AUTH_HEADERS)

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

    def test_operational_api_requires_operator_key(self) -> None:
        response = self.client.get("/api/v2/operations/overview", headers={"X-WAN-SIM-API-Key": ""})
        self.assertEqual(response.status_code, 401)

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

    def test_rollback_restores_previous_active_configuration(self) -> None:
        first = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        self.client.post(f"/api/v2/configurations/{first['id']}/deploy", json={"apply": True})
        second_payload = self.nat_payload(lan_mode="vlan")
        second_payload["name"] = "Siguiente topologia"
        second_payload["config"]["l3"]["links"][0]["baseOctet"] = 20
        second = self.client.post("/api/v2/configurations", json=second_payload).json()
        deployment = self.client.post(f"/api/v2/configurations/{second['id']}/deploy", json={"apply": True}).json()
        self.client.post(f"/api/v2/deployments/{deployment['id']}/rollback")
        active = self.client.get("/api/v2/configurations/active/current").json()
        self.assertEqual(active["id"], first["id"])

    def test_failed_host_apply_rolls_back_and_never_activates_draft(self) -> None:
        runner = FailingRunner()
        app = create_app(Path(self.directory.name) / "failure", NetworkAgent(runner), api_key=API_KEY)
        client = TestClient(app, headers=AUTH_HEADERS)
        created = client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployment = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True, "confirmation": f"APLICAR {created['id']}"}).json()
        self.assertEqual(deployment["status"], "ROLLED_BACK")
        self.assertIn("forced address failure", deployment["result"]["error"])
        self.assertIsNone(client.get("/api/v2/configurations/active/current").json())
        self.assertFalse(any(command[:3] == ["ip", "addr", "del"] for command in runner.commands))

    def test_failed_host_rollback_is_reported_and_never_activates_draft(self) -> None:
        runner = RollbackFailingRunner()
        app = create_app(Path(self.directory.name) / "rollback-failure", NetworkAgent(runner), api_key=API_KEY)
        client = TestClient(app, headers=AUTH_HEADERS)
        created = client.post("/api/v2/configurations", json=self.nat_payload()).json()
        deployment = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True, "confirmation": f"APLICAR {created['id']}"}).json()
        self.assertEqual(deployment["status"], "ROLLBACK_FAILED")
        self.assertTrue(any(item["output"] == "forced rollback failure" for item in deployment["result"]["rollback"]))
        self.assertIsNone(client.get("/api/v2/configurations/active/current").json())

    def test_host_apply_requires_exact_reactui_confirmation(self) -> None:
        runner = FailingRunner()
        client = TestClient(create_app(Path(self.directory.name) / "host-confirmation", NetworkAgent(runner), api_key=API_KEY), headers=AUTH_HEADERS)
        created = client.post("/api/v2/configurations", json=self.nat_payload()).json()
        denied = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True})
        self.assertEqual(denied.status_code, 409)
        self.assertFalse(any(command[:3] == ["ip", "addr", "replace"] for command in runner.commands))

    def test_rollback_removes_nft_chains_absent_from_snapshot(self) -> None:
        runner = StickyNftChainRunner()
        snapshot = {
            "iptables": "",
            "network": {"addresses": "[]", "routes": "[]"},
            "dhcp_config": {"exists": False, "content": ""},
            "dhcp_active": "",
        }
        results = NetworkAgent(runner).rollback([], snapshot, [])
        self.assertFalse(runner.chains)
        self.assertTrue(all(item["ok"] for item in results))
        self.assertIn(["iptables", "-t", "nat", "-X", "WANSIM_POSTROUTING"], runner.commands)
        self.assertIn(["iptables", "-t", "filter", "-X", "WANSIM_FORWARD"], runner.commands)

    def test_operations_endpoints_are_safe_in_dry_run(self) -> None:
        overview = self.client.get("/api/v2/operations/overview")
        self.assertEqual(overview.status_code, 200)
        self.assertEqual(overview.json()["execution_mode"], "dry-run")
        netem = self.client.post("/api/v2/operations/netem", json={"interface": "lan0", "delayMs": 80, "jitterMs": 5, "lossPercent": 1})
        self.assertEqual(netem.status_code, 200)
        self.assertEqual(netem.json()["mode"], "dry-run")
        restart = self.client.post("/api/v2/operations/services/restart", json={"service": "wansim.service"})
        self.assertEqual(restart.status_code, 200)
        blocked = self.client.post("/api/v2/operations/services/restart", json={"service": "ssh"})
        self.assertEqual(blocked.status_code, 400)

    def test_telegram_bots_mask_tokens_and_enforce_permissions(self) -> None:
        gateway = RecordingTelegramGateway()
        client = TestClient(create_app(Path(self.directory.name) / "telegram", NetworkAgent(CommandRunner("dry-run")), gateway, API_KEY), headers=AUTH_HEADERS)
        created = client.post("/api/v2/telegram/bots", json={
            "name": "Monitor", "token": "123456:telegram-token-for-tests", "allowedChatIds": [1001], "permission": "read",
        })
        self.assertEqual(created.status_code, 201)
        body = created.json()
        self.assertNotIn("token", body["bot"])
        self.assertTrue(body["webhook_secret"])
        bot_id = body["bot"]["id"]
        denied = client.post(f"/api/v2/telegram/bots/{bot_id}/webhook", json={"message": {"chat": {"id": 1001}, "text": "/status"}})
        self.assertEqual(denied.status_code, 403)
        status = client.post(
            f"/api/v2/telegram/bots/{bot_id}/webhook",
            headers={"X-Telegram-Bot-Api-Secret-Token": body["webhook_secret"]},
            json={"message": {"chat": {"id": 1001}, "text": "/status"}},
        )
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["action"], "status")
        self.assertEqual(gateway.messages[-1]["chat_id"], 1001)
        synced = client.post(f"/api/v2/telegram/bots/{bot_id}/sync", json={"publicBaseUrl": "https://wansim.example.test"})
        self.assertEqual(synced.status_code, 200)
        self.assertEqual(gateway.webhooks[-1]["url"], f"https://wansim.example.test/api/v2/telegram/bots/{bot_id}/webhook")
        denied_netem = client.post(
            f"/api/v2/telegram/bots/{bot_id}/webhook",
            headers={"X-Telegram-Bot-Api-Secret-Token": body["webhook_secret"]},
            json={"callback_query": {"data": "netem|lan0|40|5|0", "message": {"chat": {"id": 1001}}}},
        )
        self.assertEqual(denied_netem.status_code, 403)
        listed = client.get("/api/v2/telegram/bots")
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.json()[0]["permission"], "read")
        self.assertTrue(listed.json()[0]["webhook_url"].startswith("https://"))
        gateway.fail_delivery = True
        failed_delivery = client.post(f"/api/v2/telegram/bots/{bot_id}/test", json={"chatId": 1001})
        self.assertEqual(failed_delivery.status_code, 502)


if __name__ == "__main__":
    unittest.main()

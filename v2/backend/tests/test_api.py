from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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


class ManagementRunner(CommandRunner):
    def __init__(self) -> None:
        self.mode = "host"
        self.commands: list[list[str]] = []
        self.addresses = {"wan0": {"192.0.2.2"}, "lan0": set()}
        self.routes = [{"dst": "default", "gateway": "192.0.2.1", "dev": "wan0", "metric": 100}]

    def run(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command[:3] == ["ip", "addr", "replace"]:
            self.addresses.setdefault(command[-1], set()).add(command[3].split("/")[0])
        elif command[:3] == ["ip", "addr", "del"]:
            self.addresses.setdefault(command[-1], set()).discard(command[3].split("/")[0])
        elif command[:4] == ["ip", "route", "replace", "default"]:
            self.routes = [{"dst": "default", "gateway": command[5], "dev": command[7], "metric": int(command[9])}]
        return CommandResult(True, command, "ok")

    def probe(self, command: list[str], **_: object):
        from wansim_v2.network import CommandResult

        self.commands.append(command)
        if command == ["ip", "-j", "-s", "link", "show"]:
            links = [{"ifname": name, "operstate": "UP", "address": f"00:00:00:00:00:0{index}", "stats64": {}} for index, name in enumerate(("wan0", "lan0"), start=1)]
            return CommandResult(True, command, json.dumps(links))
        if command == ["ip", "-j", "addr", "show"]:
            payload = [{"ifname": name, "addr_info": [{"family": "inet", "local": address} for address in addresses]} for name, addresses in self.addresses.items()]
            return CommandResult(True, command, json.dumps(payload))
        if command[:5] == ["ip", "-j", "route", "get", command[-1]]:
            return CommandResult(True, command, json.dumps([{"dst": command[-1], "gateway": "192.0.2.1", "dev": "wan0"}]))
        if command in (["ip", "-j", "route", "show"], ["ip", "-j", "route", "show", "default"]):
            return CommandResult(True, command, json.dumps(self.routes))
        if command[:4] == ["ip", "link", "show", command[-1]]:
            return CommandResult(command[-1] in self.addresses, command, "present")
        if command[0:1] == ["iptables"] and "-C" in command:
            return CommandResult(True, command, "present")
        if command[0:1] == ["iptables-save"]:
            output = f"*{command[-1]}\nCOMMIT\n" if "-t" in command else ""
            return CommandResult(True, command, output)
        if command[:2] == ["systemctl", "is-active"]:
            return CommandResult(False, command, "inactive")
        if command[:3] == ["sysctl", "-n", "net.ipv4.ip_forward"]:
            return CommandResult(True, command, "0")
        if command[:2] == ["tc", "qdisc"]:
            return CommandResult(True, command, "")
        return CommandResult(False, command, "missing")


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
        self.app = create_app(Path(self.directory.name), NetworkAgent(CommandRunner("dry-run")), api_key=API_KEY)
        self.client = TestClient(self.app, headers=AUTH_HEADERS)

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

    def test_wizard_payload_with_inactive_section_is_accepted(self) -> None:
        payload = self.nat_payload()
        payload["config"]["bridge"] = {"pairs": [{"input": "", "output": ""}]}
        response = self.client.post("/api/v2/configurations", json=payload)
        self.assertEqual(response.status_code, 201)
        config = response.json()["config"]
        self.assertEqual(config["topology"], "nat")
        self.assertIsNotNone(config["l3"])
        self.assertIsNone(config["bridge"])

    def test_bridge_payload_discards_inactive_l3_section(self) -> None:
        payload = {
            "name": "Laboratorio Bridge",
            "config": {
                "topology": "bridge", "dhcpEnabled": False,
                "bridge": {"pairs": [{"input": "wan0", "output": "lan0"}]},
                "l3": {"segment": "10.254", "links": [{"wan": "", "lan": ""}]},
            },
        }
        response = self.client.post("/api/v2/configurations", json=payload)
        self.assertEqual(response.status_code, 201)
        config = response.json()["config"]
        self.assertEqual(config["topology"], "bridge")
        self.assertIsNotNone(config["bridge"])
        self.assertIsNone(config["l3"])

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

    def test_manual_gateway_must_be_inside_wan_network(self) -> None:
        payload = self.nat_payload()
        payload["config"]["l3"]["links"][0]["wanGateway"] = "198.51.100.1"
        response = self.client.post("/api/v2/configurations", json=payload)
        self.assertEqual(response.status_code, 422)

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

    def test_review_identifies_management_interface_and_compares_change(self) -> None:
        runner = ManagementRunner()
        client = TestClient(create_app(Path(self.directory.name) / "management-review", NetworkAgent(runner), api_key=API_KEY), headers=AUTH_HEADERS)
        payload = self.nat_payload()
        payload["config"]["dhcpEnabled"] = False
        created = client.post("/api/v2/configurations", json=payload).json()
        review = client.post(f"/api/v2/configurations/{created['id']}/plan", headers={**AUTH_HEADERS, "X-Forwarded-For": "203.0.113.20"}).json()
        self.assertTrue(review["preflight"]["can_apply"])
        self.assertEqual(review["preflight"]["protected_interfaces"], ["wan0"])
        self.assertTrue(any(item["code"] == "management_interface" for item in review["preflight"]["issues"]))
        self.assertIn("RIESGO wan0", review["management_confirmation_phrase"])
        self.assertTrue(review["comparison"]["changes"])

    def test_management_change_waits_for_connectivity_confirmation(self) -> None:
        runner = ManagementRunner()
        app = create_app(Path(self.directory.name) / "management-confirm", NetworkAgent(runner), api_key=API_KEY)
        client = TestClient(app, headers={**AUTH_HEADERS, "X-Forwarded-For": "203.0.113.20"})
        payload = self.nat_payload()
        payload["config"]["dhcpEnabled"] = False
        created = client.post("/api/v2/configurations", json=payload).json()
        review = client.post(f"/api/v2/configurations/{created['id']}/plan").json()
        denied = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={"apply": True, "confirmation": f"APLICAR {created['id']}"})
        self.assertEqual(denied.status_code, 409)
        pending = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={
            "apply": True,
            "confirmation": f"APLICAR {created['id']}",
            "managementConfirmation": review["management_confirmation_phrase"],
        }).json()
        self.assertEqual(pending["status"], "AWAITING_CONFIRMATION")
        confirmed = client.post(f"/api/v2/deployments/{pending['id']}/confirm")
        self.assertEqual(confirmed.status_code, 200)
        self.assertEqual(confirmed.json()["status"], "APPLIED")

    def test_management_confirmation_timeout_rolls_back(self) -> None:
        runner = ManagementRunner()
        app = create_app(Path(self.directory.name) / "management-timeout", NetworkAgent(runner), api_key=API_KEY)
        client = TestClient(app, headers={**AUTH_HEADERS, "X-Forwarded-For": "203.0.113.20"})
        payload = self.nat_payload()
        payload["config"]["dhcpEnabled"] = False
        created = client.post("/api/v2/configurations", json=payload).json()
        review = client.post(f"/api/v2/configurations/{created['id']}/plan").json()
        pending = client.post(f"/api/v2/configurations/{created['id']}/deploy", json={
            "apply": True,
            "confirmation": f"APLICAR {created['id']}",
            "managementConfirmation": review["management_confirmation_phrase"],
        }).json()
        app.state.service._expire_confirmation(pending["id"])
        rolled_back = client.get(f"/api/v2/deployments/{pending['id']}").json()
        self.assertEqual(rolled_back["status"], "ROLLED_BACK")
        self.assertEqual(rolled_back["result"]["reason"], "management-confirmation-timeout")

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

    def test_sessions_roles_and_audit_enforce_least_privilege(self) -> None:
        admin = self.client.post("/api/v2/auth/users", json={
            "username": "admin", "password": "correct-horse-battery-staple", "role": "admin",
        })
        self.assertEqual(admin.status_code, 201)
        viewer = self.client.post("/api/v2/auth/users", json={
            "username": "observer", "password": "viewer-password-1234", "role": "viewer",
        })
        self.assertEqual(viewer.status_code, 201)

        anonymous = TestClient(self.app)
        login = anonymous.post("/api/v2/auth/login", json={"username": "observer", "password": "viewer-password-1234"})
        self.assertEqual(login.status_code, 200)
        session = {"Authorization": f"Bearer {login.json()['token']}"}
        self.assertEqual(anonymous.get("/api/v2/operations/doctor", headers=session).status_code, 200)
        denied = anonymous.post("/api/v2/configurations", headers=session, json=self.nat_payload())
        self.assertEqual(denied.status_code, 403)
        me = anonymous.get("/api/v2/auth/me", headers=session).json()
        self.assertEqual(me["role"], "viewer")
        events = self.client.get("/api/v2/audit/events").json()
        self.assertTrue(any(item["action"] == "auth.login" and item["actor"] == "observer" for item in events))

    def test_password_rotation_revokes_existing_session(self) -> None:
        self.client.post("/api/v2/auth/users", json={
            "username": "operator", "password": "operator-password-123", "role": "operator",
        })
        anonymous = TestClient(self.app)
        login = anonymous.post("/api/v2/auth/login", json={"username": "operator", "password": "operator-password-123"}).json()
        session = {"Authorization": f"Bearer {login['token']}"}
        changed = anonymous.post("/api/v2/auth/password", headers=session, json={
            "currentPassword": "operator-password-123", "newPassword": "operator-password-456",
        })
        self.assertEqual(changed.status_code, 200)
        self.assertEqual(anonymous.get("/api/v2/auth/me", headers=session).status_code, 401)
        relogin = anonymous.post("/api/v2/auth/login", json={"username": "operator", "password": "operator-password-456"})
        self.assertEqual(relogin.status_code, 200)

    def test_recovery_center_verifies_checksum_and_restores_snapshot(self) -> None:
        first = self.client.post("/api/v2/configurations", json=self.nat_payload()).json()
        self.client.post(f"/api/v2/configurations/{first['id']}/deploy", json={"apply": True})
        second_payload = self.nat_payload(lan_mode="vlan")
        second_payload["name"] = "Cambio posterior"
        second_payload["config"]["l3"]["links"][0]["baseOctet"] = 30
        second = self.client.post("/api/v2/configurations", json=second_payload).json()
        self.client.post(f"/api/v2/configurations/{second['id']}/deploy", json={"apply": True})
        snapshots = self.client.get("/api/v2/recovery/snapshots").json()
        target = next(item for item in snapshots if item["configuration_id"] == first["id"])
        self.assertTrue(target["integrity"])
        restored = self.client.post(
            f"/api/v2/recovery/snapshots/{target['id']}/restore",
            json={"confirmation": f"RESTAURAR {target['id']}"},
        )
        self.assertEqual(restored.status_code, 200)
        self.assertEqual(restored.json()["status"], "RESTORED")
        self.assertEqual(self.client.get("/api/v2/configurations/active/current").json()["id"], first["id"])

        with self.app.state.repository.connection() as connection:
            connection.execute("UPDATE snapshots SET checksum='alterado' WHERE id=?", (target["id"],))
        rejected = self.client.post(
            f"/api/v2/recovery/snapshots/{target['id']}/restore",
            json={"confirmation": f"RESTAURAR {target['id']}"},
        )
        self.assertEqual(rejected.status_code, 409)

    def test_host_backups_require_integrity_and_admin_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as backup_dir, patch.dict(os.environ, {"WANSIM_BACKUP_DIR": backup_dir}):
            archive = Path(backup_dir) / "wansim-2.0.8-prestable.tar.gz"
            archive.write_bytes(b"host backup")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            Path(f"{archive}.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")

            listed = self.client.get("/api/v2/recovery/backups")
            self.assertEqual(listed.status_code, 200)
            self.assertTrue(listed.json()[0]["integrity"])
            rejected = self.client.post(
                f"/api/v2/recovery/backups/{archive.name}/restore",
                json={"confirmation": "incorrecta"},
            )
            self.assertEqual(rejected.status_code, 409)
            restored = self.client.post(
                f"/api/v2/recovery/backups/{archive.name}/restore",
                json={"confirmation": f"RESTAURAR BACKUP {archive.name}"},
            )
            self.assertEqual(restored.status_code, 200)
            self.assertTrue(restored.json()["ok"])

    def test_doctor_returns_structured_remediation_without_secrets(self) -> None:
        report = self.client.get("/api/v2/operations/doctor")
        self.assertEqual(report.status_code, 200)
        body = report.json()
        self.assertIn(body["status"], ("ok", "warning", "error"))
        self.assertTrue(any(item["component"] == "database" for item in body["checks"]))
        self.assertNotIn(API_KEY, json.dumps(body))

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
        with client.app.state.repository.connection() as connection:
            stored = connection.execute(
                "SELECT token_ciphertext, webhook_secret FROM telegram_bots WHERE id=?", (bot_id,),
            ).fetchone()
        self.assertNotIn("telegram-token-for-tests", stored["token_ciphertext"])
        self.assertNotEqual(stored["webhook_secret"], body["webhook_secret"])
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

    def test_plaintext_webhook_secret_is_migrated_to_encryption(self) -> None:
        gateway = RecordingTelegramGateway()
        root = Path(self.directory.name) / "telegram-migration"
        client = TestClient(create_app(root, NetworkAgent(CommandRunner("dry-run")), gateway, API_KEY), headers=AUTH_HEADERS)
        created = client.post("/api/v2/telegram/bots", json={
            "name": "Legacy", "token": "123456:legacy-telegram-token", "allowedChatIds": [1001], "permission": "read",
        }).json()
        bot_id, secret = created["bot"]["id"], created["webhook_secret"]
        with client.app.state.repository.connection() as connection:
            connection.execute("UPDATE telegram_bots SET webhook_secret=? WHERE id=?", (secret, bot_id))
        migrated = create_app(root, NetworkAgent(CommandRunner("dry-run")), gateway, API_KEY)
        with migrated.state.repository.connection() as connection:
            stored = connection.execute("SELECT webhook_secret FROM telegram_bots WHERE id=?", (bot_id,)).fetchone()[0]
        self.assertNotEqual(stored, secret)
        self.assertEqual(migrated.state.repository.get_telegram_bot_secret(bot_id)["webhook_secret"], secret)
        gateway.fail_delivery = True
        failed_delivery = client.post(f"/api/v2/telegram/bots/{bot_id}/test", json={"chatId": 1001})
        self.assertEqual(failed_delivery.status_code, 502)


if __name__ == "__main__":
    unittest.main()

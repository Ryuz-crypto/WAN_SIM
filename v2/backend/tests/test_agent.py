from __future__ import annotations

import json
import os
import secrets
import time
import unittest

from fastapi.testclient import TestClient

from wansim_v2.agent_auth import signature

os.environ.setdefault("WANSIM_V2_AGENT_TOKEN", "agent-test-token-with-more-than-32-characters")
os.environ.setdefault("WANSIM_V2_EXECUTION_MODE", "dry-run")

from wansim_v2.agent_server import _operation_lock, app  # noqa: E402


class AgentContractTests(unittest.TestCase):
    token = os.environ["WANSIM_V2_AGENT_TOKEN"]

    def setUp(self) -> None:
        self.client = TestClient(app)

    def signed_headers(self, method: str, path: str, body: bytes = b"", nonce: str | None = None) -> dict[str, str]:
        timestamp = str(int(time.time()))
        nonce = nonce or secrets.token_hex(16)
        return {
            "X-WAN-SIM-Timestamp": timestamp,
            "X-WAN-SIM-Nonce": nonce,
            "X-WAN-SIM-Signature": signature(self.token, timestamp, nonce, method, path, body),
            "Content-Type": "application/json",
        }

    def test_unsigned_request_is_rejected(self) -> None:
        self.assertEqual(self.client.get("/v1/health").status_code, 401)

    def test_signed_health_reports_dry_run(self) -> None:
        response = self.client.get("/v1/health", headers=self.signed_headers("GET", "/v1/health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["execution_mode"], "dry-run")

    def test_nonce_cannot_be_replayed(self) -> None:
        headers = self.signed_headers("GET", "/v1/health", nonce="one-time-nonce-1234")
        self.assertEqual(self.client.get("/v1/health", headers=headers).status_code, 200)
        self.assertEqual(self.client.get("/v1/health", headers=headers).status_code, 409)

    def test_plan_accepts_only_structured_configuration(self) -> None:
        payload = {
            "config": {
                "topology": "bridge",
                "dhcpEnabled": False,
                "bridge": {"pairs": [{"input": "in0", "output": "out0"}]},
            }
        }
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        response = self.client.post("/v1/plan", content=body, headers=self.signed_headers("POST", "/v1/plan", body))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json())

    def test_concurrent_mutation_is_rejected(self) -> None:
        payload = {"interface": "lan0", "delay_ms": 10, "jitter_ms": 0, "loss_percent": 0}
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        _operation_lock.acquire()
        try:
            response = self.client.post("/v1/netem", content=body, headers=self.signed_headers("POST", "/v1/netem", body))
        finally:
            _operation_lock.release()
        self.assertEqual(response.status_code, 423)


if __name__ == "__main__":
    unittest.main()

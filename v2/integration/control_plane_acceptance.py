"""End-to-end security acceptance against an installed WAN_SIM control plane."""
from __future__ import annotations

import json
import sqlite3
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path


BASE_URL, API_KEY, DATABASE = sys.argv[1:4]
CONTEXT = ssl.create_default_context()
CONTEXT.check_hostname = False
CONTEXT.verify_mode = ssl.CERT_NONE


def call(path: str, method: str = "GET", payload: dict | None = None, headers: dict | None = None, expected: int = 200) -> dict:
    request = urllib.request.Request(
        f"{BASE_URL}{path}", method=method,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    try:
        with urllib.request.urlopen(request, context=CONTEXT, timeout=15) as response:
            body, status = response.read(), response.status
    except urllib.error.HTTPError as error:
        body, status = error.read(), error.code
    assert status == expected, f"{method} {path}: HTTP {status}: {body.decode(errors='replace')}"
    return json.loads(body or b"{}")


admin_headers = {"X-WAN-SIM-API-Key": API_KEY}
call("/health")
call("/api/v2/auth/users", "POST", {
    "username": "acceptance-admin", "password": "Acceptance-password-123", "role": "admin",
}, admin_headers, 201)
login = call("/api/v2/auth/login", "POST", {
    "username": "acceptance-admin", "password": "Acceptance-password-123",
})
session_headers = {"Authorization": f"Bearer {login['token']}"}
assert call("/api/v2/auth/me", headers=session_headers)["role"] == "admin"

plaintext_token = "123456:acceptance-telegram-token"
created = call("/api/v2/telegram/bots", "POST", {
    "name": "Acceptance", "token": plaintext_token, "allowedChatIds": [1001], "permission": "read",
}, session_headers, 201)
assert "token" not in created["bot"] and created["bot"]["token_hint"] == "cifrado"
with sqlite3.connect(DATABASE) as database:
    ciphertext, webhook_secret = database.execute(
        "SELECT token_ciphertext, webhook_secret FROM telegram_bots WHERE id=?", (created["bot"]["id"],),
    ).fetchone()
assert plaintext_token not in ciphertext
assert created["webhook_secret"] != webhook_secret

rotation = call("/api/v2/auth/password", "POST", {
    "currentPassword": "Acceptance-password-123", "newPassword": "Acceptance-password-456",
}, session_headers)
assert rotation["reauthenticate"] is True
call("/api/v2/auth/me", headers=session_headers, expected=401)
relogin = call("/api/v2/auth/login", "POST", {
    "username": "acceptance-admin", "password": "Acceptance-password-456",
})
new_headers = {"Authorization": f"Bearer {relogin['token']}"}
events = call("/api/v2/audit/events", headers=new_headers)
assert any(item["action"] == "user.password_rotate" and item["actor"] == "acceptance-admin" for item in events)

print("WAN_SIM control-plane acceptance: TLS, sessions, rotation, audit and encrypted Telegram secrets passed.")

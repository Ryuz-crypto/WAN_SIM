from __future__ import annotations

import os
import secrets
from hmac import compare_digest
from pathlib import Path

from cryptography.fernet import Fernet


class SecretBox:
    """Encrypts persisted bot tokens; the key never leaves the host filesystem."""

    def __init__(self, state_dir: Path):
        configured = os.getenv("WANSIM_V2_SECRET_KEY")
        key_file = state_dir / "secret.key"
        if configured:
            key = configured.encode()
        elif key_file.exists():
            key = key_file.read_bytes().strip()
        else:
            key = Fernet.generate_key()
            key_file.write_bytes(key + b"\n")
            key_file.chmod(0o600)
        self._fernet = Fernet(key)

    def seal(self, value: str) -> str:
        return self._fernet.encrypt(value.encode()).decode()

    def open(self, value: str) -> str:
        return self._fernet.decrypt(value.encode()).decode()


class ApiKeyGuard:
    """Creates one operator key and validates API requests without storing it in SQLite."""

    def __init__(self, state_dir: Path, configured_key: str | None = None):
        key_file = state_dir / "api.key"
        key = configured_key or os.getenv("WANSIM_V2_API_KEY")
        if not key and key_file.exists():
            key = key_file.read_text(encoding="utf-8").strip()
        if not key:
            key = secrets.token_urlsafe(32)
            key_file.write_text(key + "\n", encoding="utf-8")
            key_file.chmod(0o600)
        if len(key) < 24:
            raise ValueError("WANSIM_V2_API_KEY debe contener al menos 24 caracteres.")
        self._key = key

    def valid(self, supplied: str | None) -> bool:
        return bool(supplied) and compare_digest(self._key, supplied)

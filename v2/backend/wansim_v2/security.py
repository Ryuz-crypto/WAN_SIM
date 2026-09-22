from __future__ import annotations

import os
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

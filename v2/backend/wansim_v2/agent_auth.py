from __future__ import annotations

import hashlib
import hmac


def body_digest(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def signature(token: str, timestamp: str, nonce: str, method: str, path: str, body: bytes) -> str:
    message = "\n".join((timestamp, nonce, method.upper(), path, body_digest(body))).encode()
    return hmac.new(token.encode(), message, hashlib.sha256).hexdigest()

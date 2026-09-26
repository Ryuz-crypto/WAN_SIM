from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone

from .models import UserCreate, UserRole, UserUpdate
from .repository import ConfigRepository
from .security import password_hash, password_valid, token_hash


class AuthService:
    def __init__(self, repository: ConfigRepository):
        self.repository = repository
        self.session_hours = max(1, min(168, int(os.getenv("WANSIM_V2_SESSION_HOURS", "12"))))

    def login(self, username: str, password: str) -> dict:
        user = self.repository.get_user_by_username(username)
        if not user or not user["enabled"] or not password_valid(password, user["password_hash"]):
            raise PermissionError("Usuario o contraseña incorrectos.")
        token = secrets.token_urlsafe(48)
        expires = datetime.now(timezone.utc) + timedelta(hours=self.session_hours)
        self.repository.create_session(user["id"], token_hash(token), expires.isoformat())
        return {"token": token, "expires_at": expires.isoformat(), "user": self.repository.public_user(user)}

    def identity(self, token: str | None) -> dict | None:
        if not token:
            return None
        return self.repository.session_identity(token_hash(token))

    def logout(self, token: str | None) -> None:
        if token:
            self.repository.revoke_session(token_hash(token))

    def create_user(self, payload: UserCreate) -> dict:
        return self.repository.create_user(payload.username, password_hash(payload.password), payload.role.value)

    def update_user(self, user_id: str, payload: UserUpdate) -> dict:
        encoded = password_hash(payload.password) if payload.password else None
        user = self.repository.update_user(user_id, payload.role.value if payload.role else None, payload.enabled, encoded)
        if not user:
            raise LookupError("Usuario no encontrado.")
        return user

    def delete_user(self, user_id: str) -> None:
        if not self.repository.delete_user(user_id):
            raise LookupError("Usuario no encontrado.")

    def change_password(self, user_id: str, current_password: str, new_password: str) -> None:
        user = self.repository.get_user(user_id)
        if not user or not password_valid(current_password, user["password_hash"]):
            raise PermissionError("La contraseña actual no es correcta.")
        self.repository.update_user(user_id, None, None, password_hash(new_password))
        self.repository.revoke_user_sessions(user_id)

    @staticmethod
    def allowed(identity: dict, minimum: UserRole) -> bool:
        ranking = {UserRole.VIEWER.value: 1, UserRole.OPERATOR.value: 2, UserRole.ADMIN.value: 3}
        return ranking.get(str(identity.get("role")), 0) >= ranking[minimum.value]

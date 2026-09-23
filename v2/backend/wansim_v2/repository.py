from __future__ import annotations

import json
import sqlite3
from hashlib import sha256
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from .models import ConfigurationRecord, DeploymentRecord, TelegramBotRecord, TelegramBotUpdate, TopologyConfig
from .security import SecretBox


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


class ConfigRepository:
    """SQLite state store; transactions use a new connection per operation."""

    def __init__(self, database: Path):
        self.database = database
        self.database.parent.mkdir(parents=True, exist_ok=True)
        self.secrets = SecretBox(database.parent)
        self._initialize()

    @contextmanager
    def connection(self):
        connection = sqlite3.connect(self.database)
        connection.row_factory = sqlite3.Row
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _initialize(self) -> None:
        with self.connection() as connection:
            connection.executescript(
                """
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS configurations (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, state TEXT NOT NULL,
                  payload TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS snapshots (
                  id TEXT PRIMARY KEY, configuration_id TEXT NOT NULL, host_state TEXT NOT NULL,
                  config_payload TEXT NOT NULL, created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS deployments (
                  id TEXT PRIMARY KEY, configuration_id TEXT NOT NULL, snapshot_id TEXT,
                  status TEXT NOT NULL, plan TEXT NOT NULL, result TEXT NOT NULL,
                  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS telegram_bots (
                  id TEXT PRIMARY KEY, name TEXT NOT NULL, token_ciphertext TEXT NOT NULL,
                  webhook_secret TEXT NOT NULL, allowed_chat_ids TEXT NOT NULL,
                  permission TEXT NOT NULL, enabled INTEGER NOT NULL,
                  webhook_url TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS users (
                  id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL,
                  role TEXT NOT NULL, enabled INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sessions (
                  id TEXT PRIMARY KEY, user_id TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE,
                  expires_at TEXT NOT NULL, created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS audit_events (
                  id TEXT PRIMARY KEY, actor TEXT NOT NULL, role TEXT NOT NULL, action TEXT NOT NULL,
                  target TEXT NOT NULL, detail TEXT NOT NULL, created_at TEXT NOT NULL
                );
                """
            )
            columns = {row["name"] for row in connection.execute("PRAGMA table_info(telegram_bots)")}
            if "webhook_url" not in columns:
                connection.execute("ALTER TABLE telegram_bots ADD COLUMN webhook_url TEXT")
            snapshot_columns = {row["name"] for row in connection.execute("PRAGMA table_info(snapshots)")}
            if "version" not in snapshot_columns:
                connection.execute("ALTER TABLE snapshots ADD COLUMN version TEXT NOT NULL DEFAULT 'legacy'")
            if "checksum" not in snapshot_columns:
                connection.execute("ALTER TABLE snapshots ADD COLUMN checksum TEXT NOT NULL DEFAULT ''")
            for row in connection.execute("SELECT id, host_state, config_payload FROM snapshots WHERE checksum = ''"):
                connection.execute(
                    "UPDATE snapshots SET checksum=? WHERE id=?",
                    (self._snapshot_checksum(row["host_state"], row["config_payload"]), row["id"]),
                )

    def create_configuration(self, name: str, config: TopologyConfig) -> ConfigurationRecord:
        config_id, timestamp = str(uuid4()), now()
        payload = json.dumps(config.model_dump(mode="json", by_alias=True), sort_keys=True)
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO configurations VALUES (?, ?, 'DRAFT', ?, ?, ?)",
                (config_id, name, payload, timestamp, timestamp),
            )
        return ConfigurationRecord(id=config_id, name=name, state="DRAFT", config=config, created_at=timestamp, updated_at=timestamp)

    def get_configuration(self, config_id: str) -> ConfigurationRecord | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM configurations WHERE id = ?", (config_id,)).fetchone()
        return self._to_configuration(row) if row else None

    def active_configuration(self) -> ConfigurationRecord | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM configurations WHERE state = 'ACTIVE' ORDER BY updated_at DESC LIMIT 1").fetchone()
        return self._to_configuration(row) if row else None

    def _to_configuration(self, row: sqlite3.Row) -> ConfigurationRecord:
        return ConfigurationRecord(
            id=row["id"], name=row["name"], state=row["state"],
            config=TopologyConfig.model_validate_json(row["payload"]),
            created_at=row["created_at"], updated_at=row["updated_at"],
        )

    def create_snapshot(self, previous_configuration_id: str | None, config: TopologyConfig | None, host_state: dict, version: str = "unknown") -> str:
        snapshot_id = str(uuid4())
        host_payload = json.dumps(host_state, sort_keys=True)
        config_payload = json.dumps(config.model_dump(mode="json", by_alias=True) if config else None, sort_keys=True)
        checksum = self._snapshot_checksum(host_payload, config_payload)
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO snapshots (id, configuration_id, host_state, config_payload, created_at, version, checksum) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (snapshot_id, previous_configuration_id or "", host_payload, config_payload, now(), version, checksum),
            )
        return snapshot_id

    def get_snapshot(self, snapshot_id: str) -> dict | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM snapshots WHERE id = ?", (snapshot_id,)).fetchone()
        return dict(row) if row else None

    @staticmethod
    def _snapshot_checksum(host_state: str, config_payload: str) -> str:
        return sha256(f"{host_state}\n{config_payload}".encode()).hexdigest()

    def snapshot_integrity(self, snapshot: dict) -> bool:
        return bool(snapshot.get("checksum")) and snapshot["checksum"] == self._snapshot_checksum(snapshot["host_state"], snapshot["config_payload"])

    def list_snapshots(self, limit: int = 50) -> list[dict]:
        with self.connection() as connection:
            rows = connection.execute("SELECT * FROM snapshots ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        output = []
        for row in rows:
            item = dict(row)
            try:
                payload = json.loads(item["config_payload"])
                topology = payload.get("topology", "none") if payload else "none"
            except (TypeError, ValueError):
                topology = "invalid"
            output.append({
                "id": item["id"], "configuration_id": item["configuration_id"], "created_at": item["created_at"],
                "version": item.get("version", "legacy"), "checksum": item.get("checksum", ""),
                "integrity": self.snapshot_integrity(item), "topology": topology,
            })
        return output

    def create_deployment(self, configuration_id: str, snapshot_id: str | None, plan: list[dict]) -> DeploymentRecord:
        deployment_id, timestamp = str(uuid4()), now()
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO deployments VALUES (?, ?, ?, 'PLANNED', ?, '{}', ?, ?)",
                (deployment_id, configuration_id, snapshot_id, json.dumps(plan), timestamp, timestamp),
            )
        return self.get_deployment(deployment_id)

    def get_deployment(self, deployment_id: str) -> DeploymentRecord | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM deployments WHERE id = ?", (deployment_id,)).fetchone()
        if not row:
            return None
        return DeploymentRecord(
            id=row["id"], configuration_id=row["configuration_id"], status=row["status"],
            plan=json.loads(row["plan"]), result=json.loads(row["result"]),
            created_at=row["created_at"], updated_at=row["updated_at"],
        )

    def update_deployment(self, deployment_id: str, status: str, result: dict) -> DeploymentRecord:
        with self.connection() as connection:
            connection.execute("UPDATE deployments SET status=?, result=?, updated_at=? WHERE id=?", (status, json.dumps(result), now(), deployment_id))
        return self.get_deployment(deployment_id)

    def list_deployments(self, limit: int = 50) -> list[DeploymentRecord]:
        with self.connection() as connection:
            rows = connection.execute("SELECT * FROM deployments ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [
            DeploymentRecord(
                id=row["id"], configuration_id=row["configuration_id"], status=row["status"],
                plan=json.loads(row["plan"]), result=json.loads(row["result"]),
                created_at=row["created_at"], updated_at=row["updated_at"],
            )
            for row in rows
        ]

    def sqlite_integrity(self) -> str:
        with self.connection() as connection:
            return str(connection.execute("PRAGMA integrity_check").fetchone()[0])

    def activate(self, configuration_id: str) -> None:
        with self.connection() as connection:
            timestamp = now()
            connection.execute("UPDATE configurations SET state='ARCHIVED', updated_at=? WHERE state='ACTIVE'", (timestamp,))
            connection.execute("UPDATE configurations SET state='ACTIVE', updated_at=? WHERE id=?", (timestamp, configuration_id))

    def deactivate(self, configuration_id: str) -> None:
        with self.connection() as connection:
            connection.execute("UPDATE configurations SET state='ARCHIVED', updated_at=? WHERE id=?", (now(), configuration_id))

    def create_telegram_bot(self, name: str, token: str, webhook_secret: str, allowed_chat_ids: list[int], permission: str) -> TelegramBotRecord:
        bot_id, timestamp = str(uuid4()), now()
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO telegram_bots (id, name, token_ciphertext, webhook_secret, allowed_chat_ids, permission, enabled, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)",
                (bot_id, name, self.secrets.seal(token), webhook_secret, json.dumps(allowed_chat_ids), permission, timestamp, timestamp),
            )
        return self.get_telegram_bot(bot_id)  # type: ignore[return-value]

    def get_telegram_bot(self, bot_id: str) -> TelegramBotRecord | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM telegram_bots WHERE id=?", (bot_id,)).fetchone()
        return self._to_telegram_bot(row) if row else None

    def list_telegram_bots(self) -> list[TelegramBotRecord]:
        with self.connection() as connection:
            rows = connection.execute("SELECT * FROM telegram_bots ORDER BY created_at DESC").fetchall()
        return [self._to_telegram_bot(row) for row in rows]

    def update_telegram_bot(self, bot_id: str, update: TelegramBotUpdate) -> TelegramBotRecord | None:
        current = self.get_telegram_bot(bot_id)
        if not current:
            return None
        enabled = current.enabled if update.enabled is None else update.enabled
        allowed = current.allowed_chat_ids if update.allowed_chat_ids is None else update.allowed_chat_ids
        permission = current.permission.value if update.permission is None else update.permission.value
        with self.connection() as connection:
            connection.execute(
                "UPDATE telegram_bots SET enabled=?, allowed_chat_ids=?, permission=?, updated_at=? WHERE id=?",
                (int(enabled), json.dumps(allowed), permission, now(), bot_id),
            )
        return self.get_telegram_bot(bot_id)

    def get_telegram_bot_secret(self, bot_id: str) -> dict | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM telegram_bots WHERE id=?", (bot_id,)).fetchone()
        if not row:
            return None
        return {
            "id": row["id"], "token": self.secrets.open(row["token_ciphertext"]), "webhook_secret": row["webhook_secret"],
            "allowed_chat_ids": json.loads(row["allowed_chat_ids"]), "permission": row["permission"], "enabled": bool(row["enabled"]),
        }

    def set_telegram_webhook(self, bot_id: str, webhook_url: str) -> TelegramBotRecord | None:
        with self.connection() as connection:
            connection.execute("UPDATE telegram_bots SET webhook_url=?, updated_at=? WHERE id=?", (webhook_url, now(), bot_id))
        return self.get_telegram_bot(bot_id)

    def create_user(self, username: str, encoded_password: str, role: str) -> dict:
        user_id, timestamp = str(uuid4()), now()
        try:
            with self.connection() as connection:
                connection.execute(
                    "INSERT INTO users VALUES (?, ?, ?, ?, 1, ?, ?)",
                    (user_id, username.lower(), encoded_password, role, timestamp, timestamp),
                )
        except sqlite3.IntegrityError as error:
            raise ValueError("El nombre de usuario ya existe.") from error
        return self.public_user(self.get_user(user_id))

    def get_user(self, user_id: str) -> dict | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
        return dict(row) if row else None

    def get_user_by_username(self, username: str) -> dict | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM users WHERE username=?", (username.lower(),)).fetchone()
        return dict(row) if row else None

    def list_users(self) -> list[dict]:
        with self.connection() as connection:
            rows = connection.execute("SELECT * FROM users ORDER BY username").fetchall()
        return [self.public_user(dict(row)) for row in rows]

    def has_users(self) -> bool:
        with self.connection() as connection:
            return bool(connection.execute("SELECT 1 FROM users LIMIT 1").fetchone())

    @staticmethod
    def public_user(user: dict | None) -> dict:
        if not user:
            raise ValueError("Usuario no encontrado.")
        result = {key: user[key] for key in ("id", "username", "role", "enabled", "created_at", "updated_at")}
        result["enabled"] = bool(result["enabled"])
        return result

    def update_user(self, user_id: str, role: str | None, enabled: bool | None, encoded_password: str | None) -> dict | None:
        current = self.get_user(user_id)
        if not current:
            return None
        values = {
            "role": role or current["role"],
            "enabled": int(current["enabled"] if enabled is None else enabled),
            "password_hash": encoded_password or current["password_hash"],
        }
        with self.connection() as connection:
            connection.execute(
                "UPDATE users SET role=?, enabled=?, password_hash=?, updated_at=? WHERE id=?",
                (values["role"], values["enabled"], values["password_hash"], now(), user_id),
            )
        if encoded_password or enabled is False:
            self.revoke_user_sessions(user_id)
        return self.public_user(self.get_user(user_id))

    def create_session(self, user_id: str, hashed_token: str, expires_at: str) -> None:
        timestamp = now()
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?)",
                (str(uuid4()), user_id, hashed_token, expires_at, timestamp, timestamp),
            )

    def session_identity(self, hashed_token: str) -> dict | None:
        timestamp = now()
        with self.connection() as connection:
            connection.execute("DELETE FROM sessions WHERE expires_at <= ?", (timestamp,))
            row = connection.execute(
                "SELECT users.*, sessions.id AS session_id, sessions.expires_at FROM sessions "
                "JOIN users ON users.id=sessions.user_id WHERE sessions.token_hash=? AND users.enabled=1",
                (hashed_token,),
            ).fetchone()
            if row:
                connection.execute("UPDATE sessions SET last_seen_at=? WHERE id=?", (timestamp, row["session_id"]))
        if not row:
            return None
        return {"id": row["id"], "username": row["username"], "role": row["role"], "auth": "session", "session_id": row["session_id"], "expires_at": row["expires_at"]}

    def revoke_session(self, hashed_token: str) -> None:
        with self.connection() as connection:
            connection.execute("DELETE FROM sessions WHERE token_hash=?", (hashed_token,))

    def revoke_user_sessions(self, user_id: str) -> None:
        with self.connection() as connection:
            connection.execute("DELETE FROM sessions WHERE user_id=?", (user_id,))

    def audit(self, actor: str, role: str, action: str, target: str, detail: dict | None = None) -> None:
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO audit_events VALUES (?, ?, ?, ?, ?, ?, ?)",
                (str(uuid4()), actor, role, action, target, json.dumps(detail or {}, sort_keys=True), now()),
            )

    def list_audit_events(self, limit: int = 200) -> list[dict]:
        with self.connection() as connection:
            rows = connection.execute("SELECT * FROM audit_events ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
        return [{**dict(row), "detail": json.loads(row["detail"])} for row in rows]

    @staticmethod
    def _to_telegram_bot(row: sqlite3.Row) -> TelegramBotRecord:
        return TelegramBotRecord(
            id=row["id"], name=row["name"], token_hint="cifrado",
            allowed_chat_ids=json.loads(row["allowed_chat_ids"]), permission=row["permission"], enabled=bool(row["enabled"]), webhook_url=row["webhook_url"],
            created_at=row["created_at"], updated_at=row["updated_at"],
        )

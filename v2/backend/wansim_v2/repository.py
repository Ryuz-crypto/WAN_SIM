from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from .models import ConfigurationRecord, DeploymentRecord, TopologyConfig


def now() -> str:
    return datetime.now(UTC).isoformat()


class ConfigRepository:
    """SQLite state store; transactions use a new connection per operation."""

    def __init__(self, database: Path):
        self.database = database
        self.database.parent.mkdir(parents=True, exist_ok=True)
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
                """
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

    def create_snapshot(self, previous_configuration_id: str | None, config: TopologyConfig | None, host_state: dict) -> str:
        snapshot_id = str(uuid4())
        with self.connection() as connection:
            connection.execute(
                "INSERT INTO snapshots VALUES (?, ?, ?, ?, ?)",
                (snapshot_id, previous_configuration_id or "", json.dumps(host_state), json.dumps(config.model_dump(mode="json", by_alias=True) if config else None), now()),
            )
        return snapshot_id

    def get_snapshot(self, snapshot_id: str) -> dict | None:
        with self.connection() as connection:
            row = connection.execute("SELECT * FROM snapshots WHERE id = ?", (snapshot_id,)).fetchone()
        return dict(row) if row else None

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

    def activate(self, configuration_id: str) -> None:
        with self.connection() as connection:
            timestamp = now()
            connection.execute("UPDATE configurations SET state='ARCHIVED', updated_at=? WHERE state='ACTIVE'", (timestamp,))
            connection.execute("UPDATE configurations SET state='ACTIVE', updated_at=? WHERE id=?", (timestamp, configuration_id))

    def deactivate(self, configuration_id: str) -> None:
        with self.connection() as connection:
            connection.execute("UPDATE configurations SET state='ARCHIVED', updated_at=? WHERE id=?", (now(), configuration_id))

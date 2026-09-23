from __future__ import annotations

import shutil
import sqlite3
import sys
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path


def migrate(database: Path, target_version: str) -> None:
    backup = database.with_name(f"state.pre-{target_version}.db")
    shutil.copy2(database, backup)
    with closing(sqlite3.connect(database)) as connection:
        with connection:
            result = connection.execute("PRAGMA integrity_check").fetchone()
            if not result or result[0] != "ok":
                raise RuntimeError(f"SQLite integrity_check falló: {result}")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS schema_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)"
            )
            connection.execute(
                "INSERT INTO schema_metadata(key, value, updated_at) VALUES('application_version', ?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                (target_version, datetime.now(timezone.utc).isoformat()),
            )
    backup.chmod(0o600)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Uso: migrate_state.py DATABASE TARGET_VERSION")
    migrate(Path(sys.argv[1]), sys.argv[2])

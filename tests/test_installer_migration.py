from __future__ import annotations

import importlib.util
import os
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("migrate_state", ROOT / "installer/migrate_state.py")
assert SPEC and SPEC.loader
MIGRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MIGRATION)


class InstallerMigrationTests(unittest.TestCase):
    def test_migration_keeps_backup_and_records_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "state.db"
            with closing(sqlite3.connect(database)) as connection:
                with connection:
                    connection.execute("CREATE TABLE existing_value (value TEXT NOT NULL)")
                    connection.execute("INSERT INTO existing_value VALUES ('kept')")

            MIGRATION.migrate(database, "2.0.8-prestable")

            backup = Path(directory) / "state.pre-2.0.8-prestable.db"
            self.assertTrue(backup.is_file())
            if os.name == "posix":
                self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
            with closing(sqlite3.connect(database)) as connection:
                self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone()[0], "ok")
                self.assertEqual(connection.execute("SELECT value FROM existing_value").fetchone()[0], "kept")
                self.assertEqual(
                    connection.execute("SELECT value FROM schema_metadata WHERE key='application_version'").fetchone()[0],
                    "2.0.8-prestable",
                )


if __name__ == "__main__":
    unittest.main()

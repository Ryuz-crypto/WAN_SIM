from __future__ import annotations

import os
import hashlib
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from wansim_v2.network import CommandRunner, NetworkAgent
from wansim_v2.operations import OperationsService
from wansim_v2.repository import ConfigRepository


class ResilienceTests(unittest.TestCase):
    def test_host_backup_catalog_verifies_checksum_before_restore(self) -> None:
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"WANSIM_BACKUP_DIR": directory}):
            archive = Path(directory) / "wansim-2.0.8-prestable.tar.gz"
            archive.write_bytes(b"verified backup")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            Path(f"{archive}.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
            agent = NetworkAgent(CommandRunner("dry-run"))

            catalog = agent.backup_catalog()
            self.assertEqual(catalog[0]["name"], archive.name)
            self.assertTrue(catalog[0]["integrity"])
            self.assertTrue(agent.schedule_backup_restore(archive.name)["ok"])
            self.assertFalse(agent.schedule_backup_restore("../outside.tar.gz")["ok"])

            archive.write_bytes(b"altered backup")
            self.assertFalse(agent.backup_catalog()[0]["integrity"])
            self.assertFalse(agent.schedule_backup_restore(archive.name)["ok"])

    def test_sqlite_remains_consistent_after_abrupt_writer_stop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "state.db"
            ConfigRepository(database)
            ready = Path(directory) / "ready"
            script = """
import sys
from pathlib import Path
from wansim_v2.repository import ConfigRepository
repo = ConfigRepository(Path(sys.argv[1]))
for index in range(30):
    repo.audit('resilience', 'admin', 'write', str(index))
Path(sys.argv[2]).write_text('ready')
while True:
    repo.audit('resilience', 'admin', 'write', 'loop')
"""
            process = subprocess.Popen([sys.executable, "-c", script, str(database), str(ready)], env=os.environ.copy())
            try:
                deadline = time.time() + 10
                while not ready.exists() and time.time() < deadline:
                    time.sleep(0.05)
                self.assertTrue(ready.exists(), "El escritor de prueba no inició.")
                process.kill()
                process.wait(timeout=5)
            finally:
                if process.poll() is None:
                    process.kill()
            reopened = ConfigRepository(database)
            self.assertEqual(reopened.sqlite_integrity(), "ok")
            self.assertGreater(len(reopened.list_audit_events()), 0)

    def test_doctor_blocks_on_critically_low_disk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = ConfigRepository(Path(directory) / "state.db")
            service = OperationsService(repository, NetworkAgent(CommandRunner("dry-run")))
            with patch("wansim_v2.operations.shutil.disk_usage", return_value=SimpleNamespace(total=1024, used=1000, free=24)):
                report = service.doctor()
            storage = next(item for item in report["checks"] if item["component"] == "storage")
            self.assertEqual(storage["status"], "error")
            self.assertEqual(report["status"], "error")


if __name__ == "__main__":
    unittest.main()

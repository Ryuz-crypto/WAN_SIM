from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class InstallerStructureTests(unittest.TestCase):
    def test_entrypoint_sources_every_required_module(self) -> None:
        entrypoint = (ROOT / "install-v2.sh").read_text(encoding="utf-8")
        expected = {
            "platform.sh", "packages.sh", "docker.sh", "network.sh", "agent.sh",
            "control-plane.sh", "security.sh", "systemd.sh", "healthcheck.sh",
            "rollback.sh", "uninstall.sh",
        }
        for module in expected:
            self.assertIn(f'installer/{module}', entrypoint)

    def test_all_installer_modes_are_explicit(self) -> None:
        entrypoint = (ROOT / "install-v2.sh").read_text(encoding="utf-8")
        for mode in ("install", "update", "repair", "doctor", "uninstall"):
            self.assertIn(mode, entrypoint)
        self.assertIn("--non-interactive", entrypoint)

    def test_compose_does_not_grant_host_network_capabilities(self) -> None:
        compose = (ROOT / "v2/deploy/docker-compose.yml").read_text(encoding="utf-8")
        self.assertNotIn("NET_ADMIN", compose)
        self.assertNotIn("network_mode: host", compose)
        self.assertIn("/run/wansim", compose)
        self.assertIn("WANSIM_V2_AGENT_TOKEN", compose)

    def test_services_have_restart_and_boot_dependencies(self) -> None:
        agent = (ROOT / "installer/systemd/wansim-agent.service").read_text(encoding="utf-8")
        control = (ROOT / "installer/systemd/wansim-control-plane.service").read_text(encoding="utf-8")
        self.assertIn("Restart=on-failure", agent)
        self.assertIn("Requires=docker.service wansim-agent.service", control)
        self.assertIn("WantedBy=multi-user.target", control)


if __name__ == "__main__":
    unittest.main()

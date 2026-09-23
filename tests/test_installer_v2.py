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
            "rollback.sh", "uninstall.sh", "configuration.sh", "wizard.sh",
            "migrations.sh", "backup.sh", "support.sh", "update.sh",
        }
        for module in expected:
            self.assertIn(f'installer/{module}', entrypoint)

    def test_all_installer_modes_are_explicit(self) -> None:
        entrypoint = (ROOT / "install-v2.sh").read_text(encoding="utf-8")
        for mode in ("install", "update", "repair", "doctor", "uninstall"):
            self.assertIn(mode, entrypoint)
        self.assertIn("--non-interactive", entrypoint)
        self.assertIn("--config", entrypoint)
        self.assertIn("--confirm-host-apply", entrypoint)

    def test_transaction_covers_files_firewall_and_service_state(self) -> None:
        transaction = (ROOT / "installer/rollback.sh").read_text(encoding="utf-8")
        self.assertIn("managed-files.tar.gz", transaction)
        self.assertIn("iptables-save", transaction)
        self.assertIn("capture_service_state", transaction)
        self.assertIn("ROLLED_BACK", transaction)

    def test_admin_cli_exposes_lifecycle_commands(self) -> None:
        cli = (ROOT / "installer/bin/wansim").read_text(encoding="utf-8")
        for command in ("doctor", "backup", "restore", "update", "upgrade", "rollback-version", "support-bundle", "repair", "uninstall"):
            self.assertIn(command, cli)
        self.assertIn("enable-host-apply --confirm", cli)

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

    def test_rpm_platform_installs_tc_for_netem(self) -> None:
        packages = (ROOT / "installer/packages.sh").read_text(encoding="utf-8")
        integration = (ROOT / "v2/integration/container-entrypoint.sh").read_text(encoding="utf-8")
        self.assertIn("iproute-tc", packages)
        self.assertIn("iproute-tc", integration)

    def test_release_packaging_has_deb_rpm_checksums_and_attestation(self) -> None:
        builder = (ROOT / "packaging/build-packages.sh").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/packages.yml").read_text(encoding="utf-8")
        self.assertIn("dpkg-deb", builder)
        self.assertIn("rpmbuild", builder)
        self.assertIn("SHA256SUMS", builder)
        self.assertIn("sed 's/-/~/g'", builder)
        self.assertNotIn('${VERSION//-/~}', builder)
        self.assertIn("attest-build-provenance", workflow)

    def test_support_bundle_redacts_environment_and_logs(self) -> None:
        support = (ROOT / "installer/support.sh").read_text(encoding="utf-8")
        self.assertIn("environment-redacted.txt", support)
        self.assertIn("sanitize_support_file", support)
        self.assertIn("Bearer ", support)


if __name__ == "__main__":
    unittest.main()

# Project Structure

Version `3.0.0-beta.1` evolves the React/FastAPI control plane while preserving `v2.0.13-stable` as the recommended stable release and `v1.119-stable` as the legacy stable release. `WANsim2.sh` remains the V1 entrypoint and `install-v2.sh` is the all-in-one lifecycle command for V2 and V3.

Current layout:

```text
WAN_SIM/
  WANsim2.sh              # Main simulator and installer entrypoint
  install-v2.sh           # All-in-one V2/V3 installer and lifecycle entrypoint
  installer/              # Wizard, lifecycle, platform, security, agent and systemd modules
  packaging/              # Reproducible DEB/RPM builders and bootstrap command
  VERSION                 # Single source for the released version
  README.md               # User installation and operating guide
  tests/
    test_l3_access.py     # L3 access/tagged regression tests without root
    test_installer_v2.py  # Installer structure and security contracts
  docs/
    PROJECT_STRUCTURE.md  # Notes for future modularization
  lib/
    logging.sh            # Shared installer logging adapter
    network.sh            # V1-compatible IP and WAN primitives
    platform.sh           # OS and package-manager inspection
  v2/
    backend/              # FastAPI control plane, SQLite state and transaction engine
    frontend/             # React + TypeScript operational interface
    deploy/               # Docker Compose and Nginx proxy definitions
    integration/          # Container and Vagrant Linux acceptance matrices
```

The V1 entrypoint sources `lib/` to preserve `./WANsim2.sh` compatibility. The V2/V3 control plane is deliberately isolated; it does not replace the stable V1 dashboard or alter the V1 installer.

Future split:

```text
lib/
  platform.sh             # OS detection, package manager, service names
  logging.sh              # log_message and console colors
  network.sh              # VLAN, bridge, NAT and tc helpers
  dashboard.sh            # Flask dashboard generation and systemd unit
  telegram.sh             # Telegram bot setup and handlers
  tls.sh                  # HTTPS certificate normalization and validation
```

The safe migration path is to extract one group at a time and keep `WANsim2.sh` sourcing those files. That preserves the existing install command:

```bash
./WANsim2.sh
```

WAN_SIM V2/V3 uses FastAPI as the control plane and a separate React + TypeScript interface as the operator console. Its privileged `NetworkAgent` runs natively under `wansim-agent.service`; FastAPI reaches it through a group-restricted, HMAC-authenticated Unix socket. It defaults to `dry-run` and persists drafts, active configuration, host snapshots and deployment results in SQLite.

Run V1 regression tests with `python3 -m unittest discover -s tests -v`, V2 API tests with `PYTHONPATH=v2/backend python3 -m unittest discover -s v2/backend/tests -v`, ReactUI checks with `cd v2/frontend && npm install && npm run build`, and shell syntax checks with `bash -n WANsim2.sh`.

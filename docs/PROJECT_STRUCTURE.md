# Project Structure

Version 2.0.5-prestable keeps `WANsim2.sh` as the main entrypoint while the current stable release remains `v1.119-stable`.

Current layout:

```text
WAN_SIM/
  WANsim2.sh              # Main simulator and installer entrypoint
  VERSION                 # Single source for the released version
  README.md               # User installation and operating guide
  tests/
    test_l3_access.py     # L3 access/tagged regression tests without root
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
    integration/          # Vagrant VM matrix for native Linux network checks
```

The V1 entrypoint sources `lib/` to preserve `./WANsim2.sh` compatibility. The V2 backend is deliberately isolated; it does not replace the stable dashboard or alter the V1 installer.

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

WAN_SIM 2.0 uses FastAPI as the control plane and a separate React + TypeScript interface as the operator console. Its `NetworkAgent` defaults to `dry-run`; it persists drafts, active configuration, host snapshots and deployment results in SQLite. An explicit host agent is required before it performs privileged network operations.

Run V1 regression tests with `python3 -m unittest discover -s tests -v`, V2 API tests with `PYTHONPATH=v2/backend python3 -m unittest discover -s v2/backend/tests -v`, ReactUI checks with `cd v2/frontend && npm install && npm run build`, and shell syntax checks with `bash -n WANsim2.sh`.

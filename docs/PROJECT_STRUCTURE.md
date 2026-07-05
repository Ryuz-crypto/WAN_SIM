# Project Structure

Version 1.118-prebeta keeps `WANsim2.sh` as the main entrypoint for compatibility with existing installs.

Current layout:

```text
WAN_SIM/
  WANsim2.sh              # Main simulator and installer entrypoint
  VERSION                 # Single source for the released version
  README.md               # User installation and operating guide
  docs/
    PROJECT_STRUCTURE.md  # Notes for future modularization
```

Recommended next split:

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

Do not move the dashboard to FastAPI/React in this base until the shell simulator is stable across Ubuntu, Debian, Fedora, CentOS and Rocky Linux.

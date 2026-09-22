#!/usr/bin/env bash
set -euo pipefail

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip iproute2 iptables isc-dhcp-client isc-dhcp-server
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y python3 python3-pip iproute iptables dhcp-client dhcp-server
else
  echo "No se reconoce un gestor de paquetes compatible." >&2
  exit 1
fi

python3 -m pip install --break-system-packages -r /vagrant/v2/backend/requirements.txt || \
  python3 -m pip install -r /vagrant/v2/backend/requirements.txt
export PYTHONPATH=/vagrant/v2/backend
python3 /vagrant/v2/integration/host_apply.py

#!/usr/bin/env bash
set -euo pipefail

workspace="${WANSIM_WORKSPACE:-/workspace}"
export INSTALLER_ROOT="$workspace"

# Validate that the all-in-one installer identifies every matrix platform.
source "$workspace/installer/common.sh"
source "$workspace/installer/platform.sh"
detect_platform
if [[ -n "${WANSIM_EXPECTED_DISTRO:-}" && "$WANSIM_DISTRO_ID" != "$WANSIM_EXPECTED_DISTRO" ]]; then
  echo "Distribución detectada $WANSIM_DISTRO_ID; se esperaba $WANSIM_EXPECTED_DISTRO." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates iproute2 iptables procps python3 python3-pip
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y \
    ca-certificates iproute procps-ng python3 python3-pip
  dnf install -y iptables || dnf install -y iptables-nft
  dnf clean all
else
  echo "No se reconoce apt-get ni dnf en la imagen de integración." >&2
  exit 1
fi

python3 -m pip install --disable-pip-version-check --no-cache-dir --target /tmp/wansim-integration-deps \
  -r "$workspace/v2/backend/requirements.txt"

export PYTHONPATH="$workspace/v2/backend:/tmp/wansim-integration-deps"
exec python3 "$workspace/v2/integration/host_apply.py"

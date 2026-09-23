#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

printf '%s\n' 'operator-key-with-more-than-24-characters' > "$TEMP_DIR/admin.key"
printf '%s\n' 'pfx-secret' > "$TEMP_DIR/pfx.secret"
cat > "$TEMP_DIR/answers.yaml" <<EOF
bindAddress: "192.0.2.10"
httpPort: 9080
httpsMode: off
httpsPort: 9443
adminKeyFile: "$TEMP_DIR/admin.key"
tlsPasswordFile: "$TEMP_DIR/pfx.secret"
executionMode: host
confirmHostApply: true
configureFirewall: yes
skipConnectivityCheck: true
nonInteractive: true
EOF

# shellcheck source=../installer/common.sh
source "$ROOT/installer/common.sh"
# shellcheck source=../installer/configuration.sh
source "$ROOT/installer/configuration.sh"
load_answer_file "$TEMP_DIR/answers.yaml" >/dev/null

[[ "$WANSIM_BIND_ADDRESS" == "192.0.2.10" ]]
[[ "$WANSIM_HTTP_PORT" == "9080" ]]
[[ "$WANSIM_HTTPS_MODE" == "off" ]]
[[ "$WANSIM_ADMIN_KEY" == "operator-key-with-more-than-24-characters" ]]
[[ "$WANSIM_TLS_PASSWORD" == "pfx-secret" ]]
[[ "$WANSIM_EXECUTION_MODE" == "host" ]]
[[ "$WANSIM_CONFIRM_HOST_APPLY" == "1" ]]
[[ "$WANSIM_CONFIGURE_FIREWALL" == "1" ]]
[[ "$WANSIM_SKIP_CONNECTIVITY" == "1" ]]
[[ "$WANSIM_NON_INTERACTIVE" == "1" ]]

printf '%s\n' 'unknownOption: true' > "$TEMP_DIR/invalid.yaml"
if (load_answer_file "$TEMP_DIR/invalid.yaml" >/dev/null 2>&1); then
  printf 'Se aceptó una clave YAML desconocida.\n' >&2
  exit 1
fi

printf 'Configuración desatendida validada.\n'

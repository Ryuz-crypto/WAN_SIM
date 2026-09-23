#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/vagrant
source /etc/os-release
SLUG="${ID:-linux}-${VERSION_ID:-unknown}"
REPORT_DIR="$ROOT/test-results/vagrant/$SLUG"
REPORT="$REPORT_DIR/installer-lifecycle.log"
BACKUP="$REPORT_DIR/wansim-lifecycle-backup.tar.gz"
SUPPORT="$REPORT_DIR/wansim-support.tar.gz"
TLS_DIR=/root/wansim-acceptance-tls
V1_REFERENCE=/root/WAN_SIM-v1.119-stable
WANSIM=/usr/local/bin/wansim

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { printf 'Esta prueba requiere root.\n' >&2; exit 1; }
install -d -m 0755 "$REPORT_DIR"
exec > >(tee "$REPORT") 2>&1

phase() { printf '\n=== %s ===\n' "$1"; }

if [[ -f /.dockerenv ]]; then
  phase "Preparación de Docker anidado"
  install -d -m 0755 /etc/docker
  printf '{"storage-driver":"vfs"}\n' > /etc/docker/daemon.json
fi

phase "Instalación nueva"
"$ROOT/install-v2.sh" install --non-interactive --https self-signed
"$WANSIM" doctor --export "$REPORT_DIR/doctor-install.txt"

phase "Referencia de retorno a V1.119"
git clone --quiet --branch v1.119-stable --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git "$V1_REFERENCE"
[[ "$(git -C "$V1_REFERENCE" describe --tags --exact-match)" == "v1.119-stable" ]]
bash -n "$V1_REFERENCE/WANsim2.sh"

phase "Respaldo consistente"
"$WANSIM" backup "$BACKUP"
[[ -s "$BACKUP" && -s "${BACKUP}.sha256" ]]

phase "Fallo inducido y rollback del instalador"
set +e
WANSIM_TEST_FAIL_PHASE=after-agent "$ROOT/install-v2.sh" repair --non-interactive
failure_status=$?
set -e
[[ "$failure_status" -ne 0 ]] || { printf 'El fallo inducido no interrumpió repair.\n' >&2; exit 1; }
latest_transaction="$(find /var/lib/wansim-installer/transactions -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
grep -q '^ROLLED_BACK' "$latest_transaction/status"
"$WANSIM" doctor --export "$REPORT_DIR/doctor-rollback.txt"

phase "Reparación y reinicio"
install -d -m 0700 "$TLS_DIR"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3 -subj '/CN=WAN_SIM Acceptance CA' \
  -keyout "$TLS_DIR/ca.key" -out "$TLS_DIR/ca.crt" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj '/CN=localhost' \
  -keyout "$TLS_DIR/server.key" -out "$TLS_DIR/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > "$TLS_DIR/server.ext"
openssl x509 -req -sha256 -days 2 -in "$TLS_DIR/server.csr" \
  -CA "$TLS_DIR/ca.crt" -CAkey "$TLS_DIR/ca.key" -CAcreateserial \
  -extfile "$TLS_DIR/server.ext" -out "$TLS_DIR/server.crt" >/dev/null 2>&1
"$ROOT/install-v2.sh" repair --non-interactive --https pem \
  --tls-cert "$TLS_DIR/server.crt" --tls-key "$TLS_DIR/server.key"
"$WANSIM" restart
"$WANSIM" doctor --export "$REPORT_DIR/doctor-repair.txt"
curl --fail --silent --show-error --cacert "$TLS_DIR/ca.crt" https://localhost/health >/dev/null

phase "Seguridad del plano de control"
operator_key="$(sed -n 's/^WANSIM_V2_API_KEY="\(.*\)"$/\1/p' /etc/wansim/wansim.env)"
[[ ${#operator_key} -ge 24 ]]
/opt/wansim/agent/venv/bin/python "$ROOT/v2/integration/control_plane_acceptance.py" \
  https://127.0.0.1 "$operator_key" /var/lib/wansim/state.db
"$WANSIM" support-bundle "$SUPPORT"
[[ -s "$SUPPORT" && -s "${SUPPORT}.sha256" ]]
if tar -xOzf "$SUPPORT" | grep -Fq '123456:acceptance-telegram-token'; then
  printf 'El bundle de soporte expuso el token Telegram de aceptación.\n' >&2
  exit 1
fi

phase "Transacción real del agente en interfaces desechables"
PYTHONPATH="$ROOT/v2/backend" /opt/wansim/agent/venv/bin/python "$ROOT/v2/integration/host_apply.py"

phase "Restauración validada"
"$WANSIM" restore "$BACKUP"
"$WANSIM" doctor --export "$REPORT_DIR/doctor-restore.txt"

phase "Desinstalación conservadora"
"$WANSIM" uninstall
[[ -d /etc/wansim && -d /var/lib/wansim ]]
[[ ! -e /usr/local/bin/wansim && ! -d /opt/wansim ]]

phase "Reinstalación desde datos conservados"
"$ROOT/install-v2.sh" repair --non-interactive
"$WANSIM" doctor --export "$REPORT_DIR/doctor-reinstall.txt"

phase "Desinstalación total"
"$WANSIM" uninstall --purge
[[ ! -e /etc/wansim && ! -e /var/lib/wansim && ! -e /opt/wansim && ! -e /usr/local/bin/wansim ]]
find /var/backups/wansim -maxdepth 1 -type f -name '*.tar.gz' -print -quit | grep -q .
[[ "$(git -C "$V1_REFERENCE" describe --tags --exact-match)" == "v1.119-stable" ]]
bash -n "$V1_REFERENCE/WANsim2.sh"

printf '\nPASS: ciclo integral completado en %s %s.\n' "${PRETTY_NAME:-$ID}" "$(uname -m)"

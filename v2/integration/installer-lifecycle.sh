#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/vagrant
source /etc/os-release
SLUG="${ID:-linux}-${VERSION_ID:-unknown}"
REPORT_DIR="$ROOT/test-results/vagrant/$SLUG"
REPORT="$REPORT_DIR/installer-lifecycle.log"
BACKUP="$REPORT_DIR/wansim-lifecycle-backup.tar.gz"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || { printf 'Esta prueba requiere root.\n' >&2; exit 1; }
install -d -m 0755 "$REPORT_DIR"
exec > >(tee "$REPORT") 2>&1

phase() { printf '\n=== %s ===\n' "$1"; }

phase "Instalación nueva"
"$ROOT/install-v2.sh" install --non-interactive --https off
wansim doctor --export "$REPORT_DIR/doctor-install.txt"

phase "Respaldo consistente"
wansim backup "$BACKUP"
[[ -s "$BACKUP" && -s "${BACKUP}.sha256" ]]

phase "Fallo inducido y rollback del instalador"
set +e
WANSIM_TEST_FAIL_PHASE=after-agent "$ROOT/install-v2.sh" repair --non-interactive
failure_status=$?
set -e
[[ "$failure_status" -ne 0 ]] || { printf 'El fallo inducido no interrumpió repair.\n' >&2; exit 1; }
latest_transaction="$(find /var/lib/wansim-installer/transactions -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
grep -q '^ROLLED_BACK' "$latest_transaction/status"
wansim doctor --export "$REPORT_DIR/doctor-rollback.txt"

phase "Reparación y reinicio"
"$ROOT/install-v2.sh" repair --non-interactive
wansim restart
wansim doctor --export "$REPORT_DIR/doctor-repair.txt"

phase "Transacción real del agente en interfaces desechables"
PYTHONPATH="$ROOT/v2/backend" /opt/wansim/agent/venv/bin/python "$ROOT/v2/integration/host_apply.py"

phase "Restauración validada"
wansim restore "$BACKUP"
wansim doctor --export "$REPORT_DIR/doctor-restore.txt"

phase "Desinstalación conservadora"
wansim uninstall
[[ -d /etc/wansim && -d /var/lib/wansim ]]
[[ ! -e /usr/local/bin/wansim && ! -d /opt/wansim ]]

phase "Reinstalación desde datos conservados"
"$ROOT/install-v2.sh" repair --non-interactive
wansim doctor --export "$REPORT_DIR/doctor-reinstall.txt"

phase "Desinstalación total"
wansim uninstall --purge
[[ ! -e /etc/wansim && ! -e /var/lib/wansim && ! -e /opt/wansim && ! -e /usr/local/bin/wansim ]]
find /var/backups/wansim -maxdepth 1 -type f -name '*.tar.gz' -print -quit | grep -q .

printf '\nPASS: ciclo integral completado en %s %s.\n' "${PRETTY_NAME:-$ID}" "$(uname -m)"

#!/usr/bin/env bash

WANSIM_INSTALL_MODE="${WANSIM_INSTALL_MODE:-install}"
WANSIM_NON_INTERACTIVE="${WANSIM_NON_INTERACTIVE:-0}"
WANSIM_BIND_ADDRESS="${WANSIM_BIND_ADDRESS:-0.0.0.0}"
WANSIM_HTTP_PORT="${WANSIM_HTTP_PORT:-8080}"
WANSIM_HTTPS_PORT="${WANSIM_HTTPS_PORT:-443}"
WANSIM_HTTPS_MODE="${WANSIM_HTTPS_MODE:-self-signed}"
WANSIM_TLS_CERT="${WANSIM_TLS_CERT:-}"
WANSIM_TLS_KEY="${WANSIM_TLS_KEY:-}"
WANSIM_TLS_PASSWORD="${WANSIM_TLS_PASSWORD:-}"
WANSIM_ADMIN_KEY="${WANSIM_ADMIN_KEY:-}"
WANSIM_EXECUTION_MODE="${WANSIM_EXECUTION_MODE:-dry-run}"
WANSIM_CONFIGURE_FIREWALL="${WANSIM_CONFIGURE_FIREWALL:-0}"
WANSIM_PURGE="${WANSIM_PURGE:-0}"
WANSIM_SKIP_CONNECTIVITY="${WANSIM_SKIP_CONNECTIVITY:-0}"

WANSIM_ETC_DIR="/etc/wansim"
WANSIM_DATA_DIR="/var/lib/wansim"
WANSIM_LOG_DIR="/var/log/wansim"
WANSIM_OPT_DIR="/opt/wansim"
WANSIM_RUN_DIR="/run/wansim"
WANSIM_SERVICE_USER="wansim"
WANSIM_SERVICE_GROUP="wansim"
export WANSIM_ETC_DIR WANSIM_DATA_DIR WANSIM_LOG_DIR WANSIM_OPT_DIR WANSIM_RUN_DIR

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok() { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[AVISO] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Ejecuta este modo con sudo."
}

require_option_value() {
  [[ -n "$2" ]] || die "$1 requiere un valor."
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)) || die "Puerto $2 no válido: $1"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

atomic_install() {
  local source="$1" target="$2" mode="${3:-0644}"
  install -D -m "$mode" "$source" "${target}.tmp"
  mv -f "${target}.tmp" "$target"
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

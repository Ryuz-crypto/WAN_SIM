#!/usr/bin/env bash
set -Eeuo pipefail

INSTALLER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALLER_ROOT

# shellcheck source=installer/common.sh
source "$INSTALLER_ROOT/installer/common.sh"
source "$INSTALLER_ROOT/installer/configuration.sh"
source "$INSTALLER_ROOT/installer/wizard.sh"
source "$INSTALLER_ROOT/installer/platform.sh"
source "$INSTALLER_ROOT/installer/packages.sh"
source "$INSTALLER_ROOT/installer/docker.sh"
source "$INSTALLER_ROOT/installer/network.sh"
source "$INSTALLER_ROOT/installer/security.sh"
source "$INSTALLER_ROOT/installer/agent.sh"
source "$INSTALLER_ROOT/installer/control-plane.sh"
source "$INSTALLER_ROOT/installer/systemd.sh"
source "$INSTALLER_ROOT/installer/healthcheck.sh"
source "$INSTALLER_ROOT/installer/rollback.sh"
source "$INSTALLER_ROOT/installer/migrations.sh"
source "$INSTALLER_ROOT/installer/backup.sh"
source "$INSTALLER_ROOT/installer/support.sh"
source "$INSTALLER_ROOT/installer/update.sh"
source "$INSTALLER_ROOT/installer/uninstall.sh"

usage() {
  cat <<'EOF'
WAN_SIM 2 - instalador integral

Uso:
  sudo ./install-v2.sh [install|update|repair|doctor|uninstall] [opciones]

Modos:
  install       Instalación nueva (predeterminado)
  update        Actualiza la aplicación y conserva configuración y datos
  repair        Reinstala dependencias, archivos y servicios
  doctor        Diagnóstico de sólo lectura
  uninstall     Retira servicios y aplicación; conserva datos sin --purge

Opciones:
  --non-interactive              No solicitar respuestas
  --config RUTA                  Archivo de respuestas YAML
  --bind-address DIRECCION       Dirección publicada (predeterminado 0.0.0.0)
  --http-port PUERTO             Puerto HTTP (predeterminado 8080)
  --https off|self-signed|pem|pfx|der
  --https-port PUERTO            Puerto HTTPS (predeterminado 443)
  --tls-cert RUTA                Certificado, bundle, PFX/P12 o DER
  --tls-key RUTA                 Clave PEM o DER cuando aplique
  --tls-password VALOR           Contraseña PFX; se evita mostrarla en logs
  --admin-key VALOR              Clave inicial de operador (mínimo 24 caracteres)
  --host-apply                   Habilita aplicación real; predeterminado dry-run
  --confirm-host-apply           Confirmación adicional obligatoria en modo no interactivo
  --configure-firewall           Abre solamente los puertos seleccionados si hay firewall activo
  --purge                        Con uninstall, elimina también configuración y datos
  --skip-connectivity-check      Omite pruebas externas de GitHub y Docker Hub
  --report RUTA                  Guarda el resultado de doctor sin secretos
  -h, --help                     Muestra esta ayuda
EOF
}

parse_arguments() {
  if [[ $# -gt 0 && "$1" != -* ]]; then
    WANSIM_INSTALL_MODE="$1"
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --non-interactive) WANSIM_NON_INTERACTIVE=1 ;;
      --config) require_option_value "$1" "${2:-}"; shift ;;
      --bind-address) require_option_value "$1" "${2:-}"; WANSIM_BIND_ADDRESS="$2"; shift ;;
      --http-port) require_option_value "$1" "${2:-}"; WANSIM_HTTP_PORT="$2"; shift ;;
      --https) require_option_value "$1" "${2:-}"; WANSIM_HTTPS_MODE="$2"; shift ;;
      --https-port) require_option_value "$1" "${2:-}"; WANSIM_HTTPS_PORT="$2"; shift ;;
      --tls-cert) require_option_value "$1" "${2:-}"; WANSIM_TLS_CERT="$2"; shift ;;
      --tls-key) require_option_value "$1" "${2:-}"; WANSIM_TLS_KEY="$2"; shift ;;
      --tls-password) require_option_value "$1" "${2:-}"; WANSIM_TLS_PASSWORD="$2"; shift ;;
      --admin-key) require_option_value "$1" "${2:-}"; WANSIM_ADMIN_KEY="$2"; shift ;;
      --host-apply) WANSIM_EXECUTION_MODE=host ;;
      --confirm-host-apply) WANSIM_CONFIRM_HOST_APPLY=1 ;;
      --configure-firewall) WANSIM_CONFIGURE_FIREWALL=1 ;;
      --purge) WANSIM_PURGE=1 ;;
      --skip-connectivity-check) WANSIM_SKIP_CONNECTIVITY=1 ;;
      --report) require_option_value "$1" "${2:-}"; WANSIM_DOCTOR_REPORT="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Opción desconocida: $1" ;;
    esac
    shift
  done
}

validate_arguments() {
  case "$WANSIM_INSTALL_MODE" in install|update|repair|doctor|uninstall) ;; *) die "Modo no válido: $WANSIM_INSTALL_MODE" ;; esac
  if [[ "$WANSIM_INSTALL_MODE" == "install" && -e "$WANSIM_ETC_DIR/wansim.env" ]]; then
    die "WAN_SIM 2 ya está instalado; usa update o repair."
  fi
  if [[ ("$WANSIM_INSTALL_MODE" == "update" || "$WANSIM_INSTALL_MODE" == "repair") && ! -e "$WANSIM_ETC_DIR/wansim.env" ]]; then
    die "No se encontró una instalación existente; usa install."
  fi
  validate_port "$WANSIM_HTTP_PORT" "HTTP"
  validate_port "$WANSIM_HTTPS_PORT" "HTTPS"
  case "$WANSIM_HTTPS_MODE" in off|self-signed|pem|pfx|der) ;; *) die "Modo HTTPS no válido: $WANSIM_HTTPS_MODE" ;; esac
  if [[ "$WANSIM_HTTPS_MODE" != "off" && "$WANSIM_HTTP_PORT" == "$WANSIM_HTTPS_PORT" ]]; then
    die "Los puertos HTTP y HTTPS deben ser diferentes."
  fi
  if [[ ! "$WANSIM_BIND_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    die "--bind-address debe ser una dirección IPv4."
  fi
  local octet
  local -a bind_octets
  IFS=. read -r -a bind_octets <<< "$WANSIM_BIND_ADDRESS"
  for octet in "${bind_octets[@]}"; do ((10#$octet <= 255)) || die "Dirección IPv4 no válida: $WANSIM_BIND_ADDRESS"; done
  if [[ -n "$WANSIM_ADMIN_KEY" && ${#WANSIM_ADMIN_KEY} -lt 24 ]]; then
    die "--admin-key debe contener al menos 24 caracteres."
  fi
  case "$WANSIM_EXECUTION_MODE" in dry-run|host) ;; *) die "executionMode debe ser dry-run u host." ;; esac
  if [[ "$WANSIM_EXECUTION_MODE" == "host" && "$WANSIM_CONFIRM_HOST_APPLY" != "1" ]]; then
    die "El modo host requiere --confirm-host-apply o confirmHostApply: true."
  fi
  local existing_tls=0
  [[ -r "$WANSIM_ETC_DIR/certs/fullchain.pem" && -r "$WANSIM_ETC_DIR/certs/privkey.pem" ]] && existing_tls=1
  if [[ "$existing_tls" == "0" ]]; then
    case "$WANSIM_HTTPS_MODE" in
      pem|der) [[ -r "$WANSIM_TLS_CERT" && -r "$WANSIM_TLS_KEY" ]] || die "$WANSIM_HTTPS_MODE requiere --tls-cert y --tls-key legibles." ;;
      pfx) [[ -r "$WANSIM_TLS_CERT" ]] || die "pfx requiere --tls-cert legible." ;;
    esac
  fi
}

install_or_refresh() {
  require_root
  detect_platform
  validate_platform
  validate_connectivity
  begin_install_transaction
  install_base_packages
  validate_python_runtime
  maybe_fail_for_test after-packages
  install_docker_engine
  validate_network_tooling
  prepare_security_and_state
  run_state_migrations
  maybe_fail_for_test after-security
  install_native_agent
  maybe_fail_for_test after-agent
  install_control_plane
  maybe_fail_for_test after-control-plane
  install_systemd_services
  configure_selected_firewall_ports
  start_wansim_services
  verify_installation
  record_installed_version
  commit_install_transaction
  print_install_summary
}

main() {
  if [[ "${1:-}" == "update" || "${1:-}" == "repair" ]] && [[ -r "$WANSIM_ETC_DIR/wansim.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$WANSIM_ETC_DIR/wansim.env"
    set +a
    WANSIM_EXECUTION_MODE="${WANSIM_V2_EXECUTION_MODE:-dry-run}"
    [[ "$WANSIM_EXECUTION_MODE" != "host" || "${WANSIM_V2_ALLOW_HOST_APPLY:-0}" != "1" ]] || WANSIM_CONFIRM_HOST_APPLY=1
  fi
  preload_answer_file "$@"
  parse_arguments "$@"
  run_install_wizard
  validate_arguments
  case "$WANSIM_INSTALL_MODE" in
    install|update|repair) install_or_refresh ;;
    doctor) detect_platform; run_doctor "$WANSIM_DOCTOR_REPORT" ;;
    uninstall) require_root; uninstall_wansim ;;
  esac
}

main "$@"

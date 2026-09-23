#!/usr/bin/env bash

prompt_value() {
  local label="$1" current="$2" answer
  read -r -p "$label [$current]: " answer </dev/tty || true
  printf '%s' "${answer:-$current}"
}

prompt_yes_no() {
  local label="$1" default="${2:-n}" answer
  read -r -p "$label (s/n) [$default]: " answer </dev/tty || true
  answer="${answer:-$default}"
  [[ "${answer,,}" == "s" || "${answer,,}" == "si" || "${answer,,}" == "sí" ]]
}

print_configuration_summary() {
  cat <<EOF

Resumen del instalador WAN_SIM 2
  Operación:       $WANSIM_INSTALL_MODE
  Publicación:     $WANSIM_BIND_ADDRESS
  HTTP:            $WANSIM_HTTP_PORT
  HTTPS:           $WANSIM_HTTPS_MODE ($WANSIM_HTTPS_PORT)
  Ejecución:       $WANSIM_EXECUTION_MODE
  Firewall:        $([[ "$WANSIM_CONFIGURE_FIREWALL" == 1 ]] && printf 'ajustar puertos' || printf 'sin cambios')
  Configuración:   $WANSIM_ETC_DIR
  Datos:           $WANSIM_DATA_DIR
EOF
}

run_install_wizard() {
  local host_default=n
  case "$WANSIM_INSTALL_MODE" in install|update|repair) ;; *) return 0 ;; esac
  [[ "$WANSIM_NON_INTERACTIVE" == "0" ]] || return 0
  [[ -r /dev/tty ]] || die "No hay terminal interactiva; usa --non-interactive y parámetros explícitos."
  printf '\nAsistente de instalación WAN_SIM 2\n'
  WANSIM_BIND_ADDRESS="$(prompt_value 'Dirección IPv4 de publicación' "$WANSIM_BIND_ADDRESS")"
  WANSIM_HTTP_PORT="$(prompt_value 'Puerto HTTP' "$WANSIM_HTTP_PORT")"
  WANSIM_HTTPS_MODE="$(prompt_value 'HTTPS (self-signed, pem, pfx, der, off)' "$WANSIM_HTTPS_MODE")"
  if [[ "$WANSIM_HTTPS_MODE" != "off" ]]; then
    WANSIM_HTTPS_PORT="$(prompt_value 'Puerto HTTPS' "$WANSIM_HTTPS_PORT")"
  fi
  case "$WANSIM_HTTPS_MODE" in
    pem|der)
      WANSIM_TLS_CERT="$(prompt_value 'Ruta del certificado' "$WANSIM_TLS_CERT")"
      WANSIM_TLS_KEY="$(prompt_value 'Ruta de la clave' "$WANSIM_TLS_KEY")"
      ;;
    pfx)
      WANSIM_TLS_CERT="$(prompt_value 'Ruta PFX/PKCS12' "$WANSIM_TLS_CERT")"
      read -r -s -p 'Contraseña PFX (vacía si no tiene): ' WANSIM_TLS_PASSWORD </dev/tty || true
      printf '\n'
      ;;
  esac
  [[ "$WANSIM_EXECUTION_MODE" == "host" ]] && host_default=s
  if prompt_yes_no '¿Habilitar aplicación real de cambios de red?' "$host_default"; then
    local phrase
    read -r -p 'Escribe HABILITAR para confirmar: ' phrase </dev/tty || true
    [[ "$phrase" == "HABILITAR" ]] || die "No se confirmó el modo host."
    WANSIM_EXECUTION_MODE=host
    WANSIM_CONFIRM_HOST_APPLY=1
  else
    WANSIM_EXECUTION_MODE=dry-run
  fi
  prompt_yes_no '¿Abrir los puertos seleccionados si el firewall ya está activo?' n && WANSIM_CONFIGURE_FIREWALL=1
  print_configuration_summary
  prompt_yes_no '¿Continuar?' s || die "Instalación cancelada sin cambios."
}

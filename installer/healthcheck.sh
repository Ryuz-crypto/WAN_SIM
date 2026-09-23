#!/usr/bin/env bash

wait_for_url() {
  local url="$1" attempts="${2:-30}" insecure="${3:-0}" i
  for ((i=1; i<=attempts; i++)); do
    if [[ "$insecure" == "1" ]]; then
      curl -kfsS --connect-timeout 2 "$url" >/dev/null 2>&1 && return 0
    else
      curl -fsS --connect-timeout 2 "$url" >/dev/null 2>&1 && return 0
    fi
    sleep 2
  done
  return 1
}

verify_installation() {
  systemctl is-active --quiet wansim-agent.service || die "wansim-agent.service no está activo."
  systemctl is-active --quiet wansim-control-plane.service || die "wansim-control-plane.service no está activo."
  [[ -S "$WANSIM_RUN_DIR/agent.sock" ]] || die "No se creó el socket del agente."
  (
    set -a
    # shellcheck disable=SC1091
    source "$WANSIM_ETC_DIR/wansim.env"
    set +a
    docker compose -f "$WANSIM_OPT_DIR/control-plane/deploy/docker-compose.yml" ps --status running >/dev/null
  )
  local health_host="$WANSIM_BIND_ADDRESS"
  [[ "$health_host" == "0.0.0.0" ]] && health_host=127.0.0.1
  if [[ "$WANSIM_HTTPS_MODE" == "off" ]]; then
    wait_for_url "http://$health_host:$WANSIM_HTTP_PORT/health" || die "El healthcheck HTTP no respondió."
  else
    wait_for_url "https://$health_host:$WANSIM_HTTPS_PORT/health" 30 1 || die "El healthcheck HTTPS no respondió."
  fi
  log_ok "Agente, FastAPI, ReactUI y proxy superaron el healthcheck."
}

run_doctor() {
  local failed=0
  log_info "Diagnóstico WAN_SIM 2 (sólo lectura)"
  printf 'Plataforma: %s %s (%s)\n' "$WANSIM_DISTRO_ID" "$WANSIM_DISTRO_VERSION" "$WANSIM_ARCH"
  local command
  for command in docker ip tc iptables openssl python3; do
    if command_exists "$command"; then printf '[OK] %s\n' "$command"; else printf '[FALTA] %s\n' "$command"; failed=1; fi
  done
  local service
  for service in docker wansim-agent.service wansim-control-plane.service; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then printf '[OK] %s activo\n' "$service"; else printf '[FALTA] %s inactivo\n' "$service"; failed=1; fi
  done
  [[ -S "$WANSIM_RUN_DIR/agent.sock" ]] && printf '[OK] socket del agente\n' || { printf '[FALTA] socket del agente\n'; failed=1; }
  [[ -r "$WANSIM_ETC_DIR/wansim.env" ]] && printf '[OK] configuración protegida\n' || { printf '[FALTA] configuración\n'; failed=1; }
  return "$failed"
}

print_install_summary() {
  local scheme=http port="$WANSIM_HTTP_PORT"
  if [[ "$WANSIM_HTTPS_MODE" != "off" ]]; then scheme=https; port="$WANSIM_HTTPS_PORT"; fi
  local address="$WANSIM_BIND_ADDRESS"
  [[ "$address" == "0.0.0.0" ]] && address="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$address" ]] || address=127.0.0.1
  printf '\nWAN_SIM 2 instalado correctamente\n'
  printf 'ReactUI: %s://%s:%s/\n' "$scheme" "$address" "$port"
  printf 'API:     %s://%s:%s/api/docs\n' "$scheme" "$address" "$port"
  printf 'Modo:    %s\n' "$WANSIM_EXECUTION_MODE"
  printf 'Estado:  sudo ./install-v2.sh doctor\n'
  printf 'Clave:   sudo sed -n '\''s/^WANSIM_V2_API_KEY="\\(.*\\)"$/\\1/p'\'' /etc/wansim/wansim.env\n'
}

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

doctor_ok() { printf '[OK] %s\n' "$*"; }
doctor_fail() { printf '[FALTA] %s\n' "$*"; }

doctor_body() {
  local failed=0 command service socket_mode free_kb mode=http host=127.0.0.1 port="$WANSIM_HTTP_PORT"
  log_info "Diagnóstico WAN_SIM 2 (sólo lectura)"
  printf 'Fecha UTC: %s\n' "$(date -u +%FT%TZ)"
  printf 'Plataforma: %s %s (%s), kernel %s\n' "$WANSIM_DISTRO_ID" "$WANSIM_DISTRO_VERSION" "$WANSIM_ARCH" "$WANSIM_KERNEL"
  printf 'Versión: %s\n' "$(cat "$WANSIM_ETC_DIR/version" 2>/dev/null || printf no-instalada)"

  for command in docker ip tc iptables openssl python3 tar sha256sum; do
    if command_exists "$command"; then doctor_ok "$command disponible"; else doctor_fail "$command no disponible"; failed=1; fi
  done
  if command_exists docker && docker compose version >/dev/null 2>&1; then doctor_ok "Docker Compose disponible"; else doctor_fail "Docker Compose no disponible"; failed=1; fi

  for service in docker.service wansim-agent.service wansim-control-plane.service; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then doctor_ok "$service activo"; else doctor_fail "$service inactivo"; failed=1; fi
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then doctor_ok "$service habilitado"; else doctor_fail "$service no habilitado"; failed=1; fi
  done

  if [[ -S "$WANSIM_RUN_DIR/agent.sock" ]]; then
    socket_mode="$(stat -c '%a %U %G' "$WANSIM_RUN_DIR/agent.sock" 2>/dev/null || true)"
    [[ "$socket_mode" == "660 root $WANSIM_SERVICE_GROUP" ]] && doctor_ok "socket del agente: $socket_mode" \
      || { doctor_fail "permisos del socket: ${socket_mode:-desconocidos}"; failed=1; }
  else
    doctor_fail "socket del agente ausente"; failed=1
  fi

  if [[ -r "$WANSIM_ETC_DIR/wansim.env" ]]; then
    local env_mode
    env_mode="$(stat -c '%a %U %G' "$WANSIM_ETC_DIR/wansim.env" 2>/dev/null || true)"
    [[ "$env_mode" == "640 root $WANSIM_SERVICE_GROUP" ]] && doctor_ok "configuración protegida: $env_mode" \
      || { doctor_fail "permisos de configuración: $env_mode"; failed=1; }
    set -a
    # shellcheck disable=SC1091
    source "$WANSIM_ETC_DIR/wansim.env"
    set +a
    host="$WANSIM_BIND_ADDRESS"; [[ "$host" == "0.0.0.0" ]] && host=127.0.0.1
    if [[ "$WANSIM_HTTPS_MODE" != "off" ]]; then mode=https; port="$WANSIM_HTTPS_PORT"; fi
  else
    doctor_fail "archivo $WANSIM_ETC_DIR/wansim.env ausente"; failed=1
  fi

  if [[ -d "$WANSIM_OPT_DIR/control-plane/deploy" ]] && command_exists docker; then
    local running
    running="$(cd "$WANSIM_OPT_DIR/control-plane/deploy" && docker compose -f docker-compose.yml ps --services --filter status=running 2>/dev/null | wc -l)"
    [[ "$running" -ge 3 ]] && doctor_ok "$running contenedores del plano de control activos" \
      || { doctor_fail "sólo $running contenedores activos"; failed=1; }
  else
    doctor_fail "plano de control no instalado"; failed=1
  fi

  if [[ "$mode" == https ]]; then
    wait_for_url "https://$host:$port/health" 3 1 && doctor_ok "API HTTPS saludable" || { doctor_fail "API HTTPS no responde"; failed=1; }
    openssl x509 -in "$WANSIM_ETC_DIR/certs/fullchain.pem" -noout -checkend 86400 >/dev/null 2>&1 \
      && doctor_ok "certificado TLS válido por más de 24 horas" || { doctor_fail "certificado TLS inválido o próximo a vencer"; failed=1; }
  else
    wait_for_url "http://$host:$port/health" 3 && doctor_ok "API HTTP saludable" || { doctor_fail "API HTTP no responde"; failed=1; }
  fi

  if [[ -e "$WANSIM_DATA_DIR/state.db" ]]; then
    local integrity bots
    integrity="$(python3 - "$WANSIM_DATA_DIR/state.db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    print(db.execute('PRAGMA integrity_check').fetchone()[0])
PY
)"
    [[ "$integrity" == ok ]] && doctor_ok "SQLite integrity_check: ok" || { doctor_fail "SQLite: $integrity"; failed=1; }
    bots="$(python3 - "$WANSIM_DATA_DIR/state.db" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    try:
        print(db.execute('SELECT COUNT(*) FROM telegram_bots WHERE enabled=1').fetchone()[0])
    except sqlite3.OperationalError:
        print(0)
PY
)"
    doctor_ok "bots Telegram habilitados: $bots (tokens no expuestos)"
  else
    doctor_fail "base SQLite ausente"; failed=1
  fi

  free_kb="$(df -Pk "$WANSIM_DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  [[ "$free_kb" =~ ^[0-9]+$ && "$free_kb" -ge 1048576 ]] && doctor_ok "espacio libre superior a 1 GiB" \
    || { doctor_fail "menos de 1 GiB libre o medición no disponible"; failed=1; }
  printf 'Modo de red: %s\n' "${WANSIM_V2_EXECUTION_MODE:-desconocido}"
  return "$failed"
}

run_doctor() {
  local report="${1:-}" status=0
  if [[ -n "$report" ]]; then
    install -d -m 0700 "$(dirname "$report")"
    if doctor_body 2>&1 | tee "${report}.tmp"; then status=0; else status=$?; fi
    mv -f "${report}.tmp" "$report"
    chmod 0600 "$report"
    printf 'Reporte guardado: %s\n' "$report"
    return "$status"
  fi
  doctor_body
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

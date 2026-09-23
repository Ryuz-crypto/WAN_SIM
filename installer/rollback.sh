#!/usr/bin/env bash

WANSIM_TRANSACTION_ACTIVE=0
WANSIM_TRANSACTION_DIR=""

capture_service_state() {
  local service="$1" active=0 enabled=0
  systemctl is-active --quiet "$service" 2>/dev/null && active=1
  systemctl is-enabled --quiet "$service" 2>/dev/null && enabled=1
  printf '%s %s %s\n' "$service" "$active" "$enabled"
}

snapshot_managed_files() {
  local list="$WANSIM_TRANSACTION_DIR/files.list" path
  : > "$list"
  for path in \
    etc/wansim opt/wansim var/lib/wansim var/log/wansim \
    etc/systemd/system/wansim-agent.service etc/systemd/system/wansim-control-plane.service \
    usr/local/libexec/wansim-compose usr/local/libexec/wansim-agent-ready usr/local/bin/wansim; do
    [[ -e "/$path" ]] && printf '%s\n' "$path" >> "$list"
  done
  if [[ -s "$list" ]]; then
    tar -C / -czpf "$WANSIM_TRANSACTION_DIR/managed-files.tar.gz" -T "$list"
    printf '1\n' > "$WANSIM_TRANSACTION_DIR/had-installation"
  else
    printf '0\n' > "$WANSIM_TRANSACTION_DIR/had-installation"
  fi
}

begin_install_transaction() {
  local transaction_id
  transaction_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  install -d -m 0700 "$WANSIM_INSTALLER_STATE_DIR/transactions"
  WANSIM_TRANSACTION_DIR="$WANSIM_INSTALLER_STATE_DIR/transactions/$transaction_id"
  install -d -m 0700 "$WANSIM_TRANSACTION_DIR"
  capture_service_state docker > "$WANSIM_TRANSACTION_DIR/services"
  capture_service_state wansim-agent.service >> "$WANSIM_TRANSACTION_DIR/services"
  capture_service_state wansim-control-plane.service >> "$WANSIM_TRANSACTION_DIR/services"
  id "$WANSIM_SERVICE_USER" >/dev/null 2>&1 && printf 1 > "$WANSIM_TRANSACTION_DIR/had-user" || printf 0 > "$WANSIM_TRANSACTION_DIR/had-user"
  command_exists iptables-save && iptables-save > "$WANSIM_TRANSACTION_DIR/iptables.rules" 2>/dev/null || true
  systemctl stop wansim-control-plane.service wansim-agent.service >/dev/null 2>&1 || true
  if ! snapshot_managed_files; then
    restore_service_states
    die "No se pudo crear el snapshot previo del instalador."
  fi
  printf 'IN_PROGRESS\n' > "$WANSIM_TRANSACTION_DIR/status"
  WANSIM_TRANSACTION_ACTIVE=1
  trap rollback_install_transaction ERR INT TERM EXIT
  log_info "Transacción del instalador: $transaction_id"
}

restore_service_states() {
  local service active enabled
  [[ -r "$WANSIM_TRANSACTION_DIR/services" ]] || return 0
  while read -r service active enabled; do
    if [[ "$enabled" == 1 ]]; then systemctl enable "$service" >/dev/null 2>&1 || true; else systemctl disable "$service" >/dev/null 2>&1 || true; fi
    if [[ "$active" == 1 ]]; then systemctl start "$service" >/dev/null 2>&1 || true; else systemctl stop "$service" >/dev/null 2>&1 || true; fi
  done < "$WANSIM_TRANSACTION_DIR/services"
}

remove_partial_installation() {
  rm -rf /etc/wansim /opt/wansim /var/lib/wansim /var/log/wansim /run/wansim
  rm -f /etc/systemd/system/wansim-agent.service /etc/systemd/system/wansim-control-plane.service \
    /usr/local/libexec/wansim-compose /usr/local/libexec/wansim-agent-ready /usr/local/bin/wansim
}

rollback_install_transaction() {
  local exit_code=$?
  [[ "$WANSIM_TRANSACTION_ACTIVE" == 1 ]] || return "$exit_code"
  WANSIM_TRANSACTION_ACTIVE=0
  trap - ERR INT TERM EXIT
  log_warn "La instalación falló; restaurando el snapshot previo."
  systemctl stop wansim-control-plane.service wansim-agent.service >/dev/null 2>&1 || true
  remove_partial_installation
  if [[ -r "$WANSIM_TRANSACTION_DIR/managed-files.tar.gz" ]]; then
    tar -C / -xzpf "$WANSIM_TRANSACTION_DIR/managed-files.tar.gz"
  elif [[ "$(cat "$WANSIM_TRANSACTION_DIR/had-user" 2>/dev/null || printf 1)" == 0 ]]; then
    userdel "$WANSIM_SERVICE_USER" >/dev/null 2>&1 || true
    groupdel "$WANSIM_SERVICE_GROUP" >/dev/null 2>&1 || true
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [[ -s "$WANSIM_TRANSACTION_DIR/iptables.rules" ]] && command_exists iptables-restore; then
    iptables-restore < "$WANSIM_TRANSACTION_DIR/iptables.rules" >/dev/null 2>&1 || true
  fi
  restore_service_states
  printf 'ROLLED_BACK exit=%s at=%s\n' "$exit_code" "$(date -u +%FT%TZ)" > "$WANSIM_TRANSACTION_DIR/status"
  log_warn "Rollback del instalador completado. Evidencia: $WANSIM_TRANSACTION_DIR"
  exit "$exit_code"
}

commit_install_transaction() {
  printf 'COMMITTED at=%s\n' "$(date -u +%FT%TZ)" > "$WANSIM_TRANSACTION_DIR/status"
  WANSIM_TRANSACTION_ACTIVE=0
  trap - ERR INT TERM EXIT
  find "$WANSIM_INSTALLER_STATE_DIR/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | awk 'NR>5 {$1=""; sub(/^ /, ""); print}' | while IFS= read -r old; do rm -rf -- "$old"; done
}

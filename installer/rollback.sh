#!/usr/bin/env bash

WANSIM_TRANSACTION_ACTIVE=0

rollback_install_transaction() {
  local exit_code=$?
  [[ "$WANSIM_TRANSACTION_ACTIVE" == "1" ]] || exit "$exit_code"
  WANSIM_TRANSACTION_ACTIVE=0
  log_warn "La instalación falló; deteniendo los servicios parcialmente desplegados."
  systemctl stop wansim-control-plane.service wansim-agent.service >/dev/null 2>&1 || true
  exit "$exit_code"
}

begin_install_transaction() {
  WANSIM_TRANSACTION_ACTIVE=1
  trap rollback_install_transaction ERR INT TERM
}

commit_install_transaction() {
  WANSIM_TRANSACTION_ACTIVE=0
  trap - ERR INT TERM
}

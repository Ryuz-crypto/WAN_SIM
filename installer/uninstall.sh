#!/usr/bin/env bash

uninstall_wansim() {
  if [[ -d "$WANSIM_ETC_DIR" || -d "$WANSIM_DATA_DIR" ]]; then
    create_backup >/dev/null
  fi
  log_info "Retirando servicios WAN_SIM 2..."
  systemctl disable --now wansim-control-plane.service wansim-agent.service >/dev/null 2>&1 || true
  if [[ -x /usr/local/libexec/wansim-compose ]]; then /usr/local/libexec/wansim-compose down >/dev/null 2>&1 || true; fi
  rm -f /etc/systemd/system/wansim-agent.service /etc/systemd/system/wansim-control-plane.service \
    /usr/local/libexec/wansim-compose /usr/local/libexec/wansim-agent-ready /usr/local/bin/wansim
  rm -rf "$WANSIM_OPT_DIR" "$WANSIM_RUN_DIR"
  systemctl daemon-reload
  if [[ "$WANSIM_PURGE" == "1" ]]; then
    rm -rf "$WANSIM_ETC_DIR" "$WANSIM_DATA_DIR" "$WANSIM_LOG_DIR"
    userdel "$WANSIM_SERVICE_USER" >/dev/null 2>&1 || true
    groupdel "$WANSIM_SERVICE_GROUP" >/dev/null 2>&1 || true
    log_ok "Aplicación, configuración y datos eliminados. Docker se conservó."
  else
    log_ok "Aplicación retirada. Se conservaron $WANSIM_ETC_DIR y $WANSIM_DATA_DIR. Docker se conservó."
  fi
}

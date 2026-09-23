#!/usr/bin/env bash

install_systemd_services() {
  atomic_install "$INSTALLER_ROOT/installer/systemd/wansim-agent.service" /etc/systemd/system/wansim-agent.service 0644
  atomic_install "$INSTALLER_ROOT/installer/systemd/wansim-control-plane.service" /etc/systemd/system/wansim-control-plane.service 0644
  atomic_install "$INSTALLER_ROOT/installer/bin/wansim-compose" /usr/local/libexec/wansim-compose 0755
  atomic_install "$INSTALLER_ROOT/installer/bin/wansim-agent-ready" /usr/local/libexec/wansim-agent-ready 0755
  systemctl daemon-reload
  systemctl enable wansim-agent.service wansim-control-plane.service
  log_ok "Servicios systemd instalados y habilitados."
}

start_wansim_services() {
  systemctl restart wansim-agent.service
  systemctl restart wansim-control-plane.service
}

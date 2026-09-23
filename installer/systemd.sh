#!/usr/bin/env bash

install_systemd_services() {
  install_managed_source
  atomic_install "$INSTALLER_ROOT/installer/systemd/wansim-agent.service" /etc/systemd/system/wansim-agent.service 0644
  atomic_install "$INSTALLER_ROOT/installer/systemd/wansim-control-plane.service" /etc/systemd/system/wansim-control-plane.service 0644
  atomic_install "$INSTALLER_ROOT/installer/bin/wansim-compose" /usr/local/libexec/wansim-compose 0755
  atomic_install "$INSTALLER_ROOT/installer/bin/wansim-agent-ready" /usr/local/libexec/wansim-agent-ready 0755
  atomic_install "$INSTALLER_ROOT/installer/bin/wansim" /usr/local/bin/wansim 0755
  systemctl daemon-reload
  systemctl enable wansim-agent.service wansim-control-plane.service
  log_ok "Servicios systemd instalados y habilitados."
}

install_managed_source() {
  local stage="$WANSIM_OPT_DIR/.source-new"
  rm -rf "$stage"
  install -d -m 0750 -o root -g "$WANSIM_SERVICE_GROUP" "$stage"
  tar -C "$INSTALLER_ROOT" \
    --exclude='node_modules' --exclude='.venv' --exclude='venv' --exclude='dist' --exclude='test-results' \
    -cf - install-v2.sh installer installer.example.yaml VERSION v2 \
    | tar -C "$stage" -xf -
  rm -rf "$WANSIM_OPT_DIR/source"
  mv "$stage" "$WANSIM_OPT_DIR/source"
  chown -R root:"$WANSIM_SERVICE_GROUP" "$WANSIM_OPT_DIR/source"
  chmod -R o-rwx "$WANSIM_OPT_DIR/source"
}

start_wansim_services() {
  systemctl restart wansim-agent.service
  systemctl restart wansim-control-plane.service
}

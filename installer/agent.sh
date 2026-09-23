#!/usr/bin/env bash

install_native_agent() {
  log_info "Instalando el agente nativo en $WANSIM_OPT_DIR/agent..."
  install -d -m 0755 "$WANSIM_OPT_DIR/agent/app"
  rm -rf "$WANSIM_OPT_DIR/agent/app/wansim_v2"
  cp -a "$INSTALLER_ROOT/v2/backend/wansim_v2" "$WANSIM_OPT_DIR/agent/app/wansim_v2"
  install -m 0644 "$INSTALLER_ROOT/v2/backend/requirements.txt" "$WANSIM_OPT_DIR/agent/requirements.txt"
  if [[ ! -x "$WANSIM_OPT_DIR/agent/venv/bin/python" ]]; then
    python3 -m venv "$WANSIM_OPT_DIR/agent/venv"
  fi
  "$WANSIM_OPT_DIR/agent/venv/bin/pip" install --disable-pip-version-check --no-cache-dir -r "$WANSIM_OPT_DIR/agent/requirements.txt"
  chown -R root:"$WANSIM_SERVICE_GROUP" "$WANSIM_OPT_DIR/agent"
  chmod -R o-rwx "$WANSIM_OPT_DIR/agent"
  log_ok "Agente nativo instalado; no se ha modificado ninguna interfaz."
}

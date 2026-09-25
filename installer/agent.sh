#!/usr/bin/env bash

install_native_agent() {
  local target="$WANSIM_OPT_DIR/agent"
  local stage="$WANSIM_OPT_DIR/.agent-new"
  log_info "Instalando el agente nativo en $target..."
  rm -rf "$stage"
  install -d -m 0755 "$stage/app"
  cp -a "$INSTALLER_ROOT/v2/backend/wansim_v2" "$stage/app/wansim_v2"
  install -m 0644 "$INSTALLER_ROOT/v2/agent/requirements.txt" "$stage/requirements.txt"
  python3 -m venv "$stage/venv"
  "$stage/venv/bin/python" -m pip install \
    --disable-pip-version-check --no-cache-dir --only-binary=:all: \
    -r "$stage/requirements.txt"
  WANSIM_V2_AGENT_TOKEN="agent-install-smoke-test-token-32chars" \
    PYTHONPATH="$stage/app" "$stage/venv/bin/python" -c \
    'from wansim_v2.agent_server import app; assert app.title == "WAN_SIM 2 Host Agent"'
  rm -rf "$target"
  mv "$stage" "$target"
  chown -R root:"$WANSIM_SERVICE_GROUP" "$target"
  chmod -R o-rwx "$target"
  log_ok "Agente nativo instalado; no se ha modificado ninguna interfaz."
}

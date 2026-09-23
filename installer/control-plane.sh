#!/usr/bin/env bash

install_control_plane() {
  local target="$WANSIM_OPT_DIR/control-plane"
  log_info "Preparando FastAPI, ReactUI y proxy en $target..."
  install -d -m 0755 "$target"
  rm -rf "$target/backend" "$target/frontend" "$target/deploy"
  cp -a "$INSTALLER_ROOT/v2/backend" "$target/backend"
  cp -a "$INSTALLER_ROOT/v2/frontend" "$target/frontend"
  cp -a "$INSTALLER_ROOT/v2/deploy" "$target/deploy"
  chown -R root:"$WANSIM_SERVICE_GROUP" "$target"
  chmod -R o-w "$target"
  (
    cd "$target/deploy"
    set -a
    # shellcheck disable=SC1091
    source "$WANSIM_ETC_DIR/wansim.env"
    set +a
    docker compose -f docker-compose.yml config --quiet
    docker compose -f docker-compose.yml build --pull
  )
  log_ok "Plano de control compilado con versiones declaradas."
}

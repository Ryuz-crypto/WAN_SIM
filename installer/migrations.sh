#!/usr/bin/env bash

run_state_migrations() {
  local database="$WANSIM_DATA_DIR/state.db" target_version
  target_version="$(tr -d '\r\n' < "$INSTALLER_ROOT/VERSION")"
  [[ -e "$database" ]] || { log_info "No hay base anterior que migrar."; return 0; }
  python3 "$INSTALLER_ROOT/installer/migrate_state.py" "$database" "$target_version"
  log_ok "Integridad y migraciones de SQLite validadas."
}

record_installed_version() {
  local target_version tmp
  target_version="$(tr -d '\r\n' < "$INSTALLER_ROOT/VERSION")"
  tmp="$(mktemp "$WANSIM_ETC_DIR/.version.XXXXXX")"
  printf '%s\n' "$target_version" > "$tmp"
  chown root:"$WANSIM_SERVICE_GROUP" "$tmp"
  chmod 0640 "$tmp"
  mv -f "$tmp" "$WANSIM_ETC_DIR/version"
}

#!/usr/bin/env bash

sanitize_support_file() {
  local file="$1" temporary
  [[ -f "$file" ]] || return 0
  temporary="${file}.redacted"
  sed -E \
    -e 's/(bot)[0-9]{6,}:[A-Za-z0-9_-]{20,}/\1<redacted>/g' \
    -e 's/((token|secret|password|passwd|api[_ -]?key|authorization)[=: ]+)[^[:space:],;]+/\1<redacted>/Ig' \
    -e 's/(Bearer )[A-Za-z0-9._~-]+/\1<redacted>/Ig' \
    "$file" > "$temporary"
  mv -f "$temporary" "$file"
}

create_support_bundle() {
  local destination="${1:-}" timestamp version archive work
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  version="$(cat "$WANSIM_ETC_DIR/version" 2>/dev/null || printf unknown)"
  archive="${destination:-$WANSIM_BACKUP_DIR/wansim-support-${version}-${timestamp}.tar.gz}"
  work="$(mktemp -d /tmp/wansim-support.XXXXXX)"
  install -d -m 0700 "$(dirname "$archive")"

  detect_platform
  run_doctor "$work/doctor.txt" || true
  printf 'version=%s\nplatform=%s %s\narch=%s\nkernel=%s\n' \
    "$version" "$WANSIM_DISTRO_ID" "$WANSIM_DISTRO_VERSION" "$WANSIM_ARCH" "$WANSIM_KERNEL" > "$work/system.txt"
  if [[ -r "$WANSIM_ETC_DIR/wansim.env" ]]; then
    sed -E 's/^([A-Z0-9_]+)=.*/\1=<redacted>/' "$WANSIM_ETC_DIR/wansim.env" > "$work/environment-redacted.txt"
  fi
  [[ ! -r "$WANSIM_ETC_DIR/config.yaml" ]] || cp "$WANSIM_ETC_DIR/config.yaml" "$work/config.yaml"
  journalctl -u wansim-agent.service -u wansim-control-plane.service -n 300 --no-pager > "$work/journal.txt" 2>&1 || true
  if command_exists docker && [[ -d "$WANSIM_OPT_DIR/control-plane/deploy" ]]; then
    (cd "$WANSIM_OPT_DIR/control-plane/deploy" && docker compose ps) > "$work/compose.txt" 2>&1 || true
  fi
  if [[ -r "$WANSIM_DATA_DIR/state.db" ]]; then
    python3 - "$WANSIM_DATA_DIR/state.db" > "$work/database.txt" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    print("integrity=" + db.execute("PRAGMA integrity_check").fetchone()[0])
    for table in ("configurations", "deployments", "snapshots", "telegram_bots", "users", "audit_events"):
        try:
            print(f"{table}=" + str(db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]))
        except sqlite3.OperationalError:
            print(f"{table}=unavailable")
PY
  fi
  for report in "$work"/*; do sanitize_support_file "$report"; done
  tar -C "$work" -czf "${archive}.tmp" . || { rm -rf -- "$work" "${archive}.tmp"; die "No se pudo crear el bundle de soporte."; }
  chmod 0600 "${archive}.tmp"
  mv -f "${archive}.tmp" "$archive"
  (cd "$(dirname "$archive")" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")
  chmod 0600 "${archive}.sha256"
  rm -rf -- "$work"
  log_ok "Bundle de soporte creado sin secretos: $archive"
  printf '%s\n' "$archive"
}

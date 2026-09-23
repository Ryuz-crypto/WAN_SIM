#!/usr/bin/env bash

create_backup() {
  local destination="${1:-}" was_active=0 timestamp version list archive checksum checksum_tmp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  version="$(cat "$WANSIM_ETC_DIR/version" 2>/dev/null || printf unknown)"
  install -d -m 0700 "$WANSIM_BACKUP_DIR"
  archive="${destination:-$WANSIM_BACKUP_DIR/wansim-${version}-${timestamp}.tar.gz}"
  checksum_tmp="${archive}.sha256.tmp"
  install -d -m 0700 "$(dirname "$archive")"
  systemctl is-active --quiet wansim-control-plane.service 2>/dev/null && was_active=1
  [[ "$was_active" == 0 ]] || systemctl stop wansim-control-plane.service
  list="$(mktemp)"
  for path in etc/wansim var/lib/wansim; do [[ -e "/$path" ]] && printf '%s\n' "$path" >> "$list"; done
  if [[ ! -s "$list" ]]; then
    rm -f "$list"
    [[ "$was_active" == 0 ]] || systemctl start wansim-control-plane.service
    die "No hay configuración ni datos de WAN_SIM para respaldar."
  fi
  if ! tar -C / -czpf "${archive}.tmp" -T "$list" ||
     ! chmod 0600 "${archive}.tmp" ||
     ! checksum="$(sha256sum "${archive}.tmp" | awk '{print $1}')" ||
     ! printf '%s  %s\n' "$checksum" "$(basename "$archive")" > "$checksum_tmp" ||
     ! chmod 0600 "$checksum_tmp" ||
     ! mv -f "${archive}.tmp" "$archive" ||
     ! mv -f "$checksum_tmp" "${archive}.sha256"; then
    rm -f "$list" "${archive}.tmp" "$checksum_tmp"
    [[ "$was_active" == 0 ]] || systemctl start wansim-control-plane.service
    die "No se pudo crear el respaldo."
  fi
  rm -f "$list"
  [[ "$was_active" == 0 ]] || systemctl start wansim-control-plane.service
  log_ok "Respaldo creado: $archive"
  printf '%s\n' "$archive"
}

validate_backup_archive() {
  local archive="$1" entry
  [[ -r "$archive" ]] || die "No se puede leer el respaldo: $archive"
  [[ -r "${archive}.sha256" ]] || die "Falta el checksum del respaldo: ${archive}.sha256"
  (cd "$(dirname "$archive")" && sha256sum -c "$(basename "${archive}.sha256")") >/dev/null \
    || die "El checksum del respaldo no coincide."
  while IFS= read -r entry; do
    [[ "$entry" != /* && "$entry" != *"../"* && "$entry" != ".." ]] || die "El respaldo contiene una ruta insegura: $entry"
    case "$entry" in etc/wansim|etc/wansim/*|var/lib/wansim|var/lib/wansim/*) ;; *) die "Ruta no permitida en respaldo: $entry" ;; esac
  done < <(tar -tzf "$archive")
}

restore_backup() {
  local archive="$1" safety control_active=0 agent_active=0
  validate_backup_archive "$archive"
  log_info "Creando respaldo de seguridad antes de restaurar..."
  safety="$(create_backup | tail -n 1)"
  systemctl is-active --quiet wansim-control-plane.service 2>/dev/null && control_active=1
  systemctl is-active --quiet wansim-agent.service 2>/dev/null && agent_active=1
  systemctl stop wansim-control-plane.service wansim-agent.service >/dev/null 2>&1 || true
  if ! tar -C / -xzpf "$archive"; then
    log_warn "La restauración falló; recuperando el respaldo de seguridad."
    tar -C / -xzpf "$safety" || die "Fallaron la restauración y su recuperación; respaldo de seguridad: $safety"
    [[ "$agent_active" == 0 ]] || systemctl start wansim-agent.service
    [[ "$control_active" == 0 ]] || systemctl start wansim-control-plane.service
    die "No se pudo restaurar $archive; se recuperó el estado previo."
  fi
  [[ "$agent_active" == 0 ]] || systemctl start wansim-agent.service
  [[ "$control_active" == 0 ]] || systemctl start wansim-control-plane.service
  log_ok "Respaldo restaurado: $archive"
}

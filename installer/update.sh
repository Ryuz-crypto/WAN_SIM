#!/usr/bin/env bash

update_to_release() {
  local release="$1" temp current
  [[ "$release" =~ ^v2\.[0-9]+\.[0-9]+-(prestable|stable|rc\.[0-9]+)$ ]] || die "Versión no permitida: $release. Usa una etiqueta V2 publicada."
  current="v$(cat "$WANSIM_ETC_DIR/version" 2>/dev/null || printf unknown)"
  [[ "$current" != "$release" ]] || { log_ok "WAN_SIM ya está en $release."; return 0; }
  git ls-remote --exit-code --tags https://github.com/Ryuz-crypto/WAN_SIM.git "refs/tags/$release" >/dev/null \
    || die "La etiqueta $release no existe en GitHub."
  temp="$(mktemp -d /tmp/wansim-update.XXXXXX)"
  git clone --quiet --branch "$release" --depth 1 https://github.com/Ryuz-crypto/WAN_SIM.git "$temp/source"
  [[ "$(git -C "$temp/source" describe --tags --exact-match)" == "$release" ]] || { rm -rf -- "$temp"; die "La descarga no coincide con $release."; }
  create_backup >/dev/null
  if ! "$temp/source/install-v2.sh" update --non-interactive; then
    rm -rf -- "$temp"
    die "La actualización a $release falló; el instalador ejecutó rollback."
  fi
  install -d -m 0700 "$WANSIM_INSTALLER_STATE_DIR"
  printf '%s\n' "$current" > "$WANSIM_INSTALLER_STATE_DIR/previous-version"
  chmod 0600 "$WANSIM_INSTALLER_STATE_DIR/previous-version"
  rm -rf -- "$temp"
  log_ok "Actualización completada: $current -> $release"
}

rollback_version() {
  local release="${1:-}"
  [[ -n "$release" ]] || release="$(cat "$WANSIM_INSTALLER_STATE_DIR/previous-version" 2>/dev/null || true)"
  [[ -n "$release" ]] || die "No existe una versión anterior registrada; indica una etiqueta explícita."
  log_warn "Se restaurará el software a $release conservando datos mediante migración y respaldo."
  update_to_release "$release"
}

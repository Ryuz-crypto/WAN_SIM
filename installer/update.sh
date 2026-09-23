#!/usr/bin/env bash

update_to_release() {
  local release="$1" temp current
  [[ "$release" =~ ^v2\.[0-9]+\.[0-9]+-(prestable|stable)$ ]] || die "Versión no permitida: $release. Usa una etiqueta v2.x.y-prestable o v2.x.y-stable."
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
  rm -rf -- "$temp"
  log_ok "Actualización completada: $current -> $release"
}

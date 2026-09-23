#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
RELEASE_VERSION="${VERSION//-/.}"
OUT="${1:-$ROOT/dist}"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$OUT"

stage_payload() {
  local stage="$1"
  mkdir -p "$stage/opt/wansim/distribution" "$stage/usr/local/sbin"
  tar -C "$ROOT" --exclude=.git --exclude=dist --exclude=test-results -cf - . | tar -C "$stage/opt/wansim/distribution" -xf -
  install -m 0755 "$ROOT/packaging/wansim-install" "$stage/usr/local/sbin/wansim-install"
}

build_deb() {
  command -v dpkg-deb >/dev/null || return 0
  local stage="$WORK/deb" deb_version="${VERSION//-/~}"
  stage_payload "$stage"
  mkdir -p "$stage/DEBIAN"
  cat > "$stage/DEBIAN/control" <<EOF
Package: wansim
Version: $deb_version
Section: net
Priority: optional
Architecture: all
Maintainer: WAN_SIM <decameru@outlook.com>
Depends: bash, git, curl, sudo
Description: WAN_SIM 2 transactional network simulator installer
 Installs a versioned WAN_SIM payload. Run sudo wansim-install install to deploy.
EOF
  dpkg-deb --root-owner-group --build "$stage" "$OUT/wansim_${deb_version}_all.deb"
}

build_rpm() {
  command -v rpmbuild >/dev/null || return 0
  local top="$WORK/rpmbuild" source="wansim-$RELEASE_VERSION"
  mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$WORK/$source"
  stage_payload "$WORK/$source"
  tar -C "$WORK" -czf "$top/SOURCES/$source.tar.gz" "$source"
  sed -e "s/@VERSION@/$RELEASE_VERSION/g" "$ROOT/packaging/wansim.spec.in" > "$top/SPECS/wansim.spec"
  rpmbuild --define "_topdir $top" -bb "$top/SPECS/wansim.spec"
  find "$top/RPMS" -type f -name '*.rpm' -exec cp {} "$OUT/" \;
}

build_deb
build_rpm
find "$OUT" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) -printf '%f\n' | sort | while read -r artifact; do
  (cd "$OUT" && sha256sum "$artifact")
done > "$OUT/SHA256SUMS"
[[ -s "$OUT/SHA256SUMS" ]] || { echo "No se construyó ningún paquete; instala dpkg-deb o rpmbuild." >&2; exit 1; }
cat "$OUT/SHA256SUMS"

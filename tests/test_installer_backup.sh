#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# shellcheck source=../installer/common.sh
source "$ROOT/installer/common.sh"
# shellcheck source=../installer/backup.sh
source "$ROOT/installer/backup.sh"

mkdir -p "$TEMP_DIR/root/etc/wansim"
printf 'schemaVersion: 1\n' > "$TEMP_DIR/root/etc/wansim/config.yaml"
tar -C "$TEMP_DIR/root" -czpf "$TEMP_DIR/valid.tar.gz" etc/wansim
(cd "$TEMP_DIR" && sha256sum valid.tar.gz > valid.tar.gz.sha256)
validate_backup_archive "$TEMP_DIR/valid.tar.gz"

cp "$TEMP_DIR/valid.tar.gz" "$TEMP_DIR/tampered.tar.gz"
sed 's/valid\.tar\.gz/tampered.tar.gz/' "$TEMP_DIR/valid.tar.gz.sha256" > "$TEMP_DIR/tampered.tar.gz.sha256"
printf 'alterado\n' >> "$TEMP_DIR/tampered.tar.gz"
if (validate_backup_archive "$TEMP_DIR/tampered.tar.gz" >/dev/null 2>&1); then
  printf 'Se aceptó un respaldo con checksum inválido.\n' >&2
  exit 1
fi

cp "$TEMP_DIR/valid.tar.gz" "$TEMP_DIR/no-checksum.tar.gz"
if (validate_backup_archive "$TEMP_DIR/no-checksum.tar.gz" >/dev/null 2>&1); then
  printf 'Se aceptó un respaldo sin checksum.\n' >&2
  exit 1
fi

printf 'Validación de respaldos aprobada.\n'

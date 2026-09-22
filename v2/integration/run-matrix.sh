#!/usr/bin/env bash
set -euo pipefail

provider="${VAGRANT_PROVIDER:-virtualbox}"
for machine in ubuntu debian fedora rocky; do
  vagrant up "$machine" --provider="$provider"
done

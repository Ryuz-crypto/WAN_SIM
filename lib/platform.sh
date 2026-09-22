#!/usr/bin/env bash
# Shared platform helpers for the V1 installer and the V2 host agent.

wansim_platform_json() {
    local os_id="unknown"
    local os_version="unknown"
    local manager="unknown"

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-unknown}"
        os_version="${VERSION_ID:-unknown}"
    fi
    if command -v apt-get >/dev/null 2>&1; then manager="apt"; fi
    if command -v dnf >/dev/null 2>&1; then manager="dnf"; fi
    if command -v yum >/dev/null 2>&1; then manager="yum"; fi
    printf '{"os":"%s","version":"%s","package_manager":"%s"}\n' "$os_id" "$os_version" "$manager"
}

wansim_require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'Falta el comando requerido: %s\n' "$1" >&2
        return 1
    }
}

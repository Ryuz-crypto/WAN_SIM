#!/usr/bin/env bash
# This wrapper lets new modules share the installer log without owning it.

wansim_log() {
    local level="$1"
    shift
    if declare -F log_message >/dev/null 2>&1; then
        log_message "$level" "$*"
    else
        printf '[%s] %s\n' "$level" "$*"
    fi
}

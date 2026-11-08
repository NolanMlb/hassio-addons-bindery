#!/usr/bin/env bash
# ==============================================================================
# Bindery app - shared helpers
#
# Everything the app can learn about an installation comes from the options the
# Supervisor validated into /data/options.json. No path, address, credential or
# device name is hardcoded here: the defaults below are generic and work on a
# stock Home Assistant OS installation.
# ==============================================================================

OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
# Private, persistent storage of the app. /data survives restarts, updates and
# is included in Home Assistant backups.
DATA_DIR="${DATA_DIR:-/data/bindery}"

info() { printf '[INFO] %s\n' "$*"; }
notice() { printf '[NOTICE] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
fatal() { printf '[FATAL] %s\n' "$*" >&2; exit 1; }

# opt <key> [default] -> prints the option value, or the default when unset.
opt() {
    local key="${1}" def="${2:-}" value=""
    if [ -r "${OPTIONS_FILE}" ]; then
        value="$(jq -r --arg k "${key}" \
            'if has($k) and (.[$k] != null) then (.[$k] | tostring) else "" end' \
            "${OPTIONS_FILE}" 2>/dev/null || true)"
    fi
    if [ -z "${value}" ]; then
        printf '%s' "${def}"
    else
        printf '%s' "${value}"
    fi
}

# opt_list <key> -> prints one list item per line.
opt_list() {
    local key="${1}"
    [ -r "${OPTIONS_FILE}" ] || return 0
    jq -r --arg k "${key}" \
        '(.[$k] // [])[]? | select(. != null) | tostring' \
        "${OPTIONS_FILE}" 2>/dev/null || true
}

# True when <path> lives on a mount that is not the container's own root
# filesystem. Used to refuse writing a library into a disk that failed to mount.
path_on_mount() {
    local path="${1}"
    while [ "${path}" != "/" ] && [ -n "${path}" ]; do
        if mountpoint -q "${path}" 2>/dev/null; then
            return 0
        fi
        path="$(dirname "${path}")"
    done
    return 1
}

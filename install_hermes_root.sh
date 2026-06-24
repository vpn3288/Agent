#!/usr/bin/env bash
################################################################################
# Hermes Agent root installer wrapper
# Kept for compatibility with older usage. It now delegates to the unified
# Debian/Ubuntu installer so dependency preparation stays identical.
################################################################################

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/debian12_hermes_openclaw_perfect_install.sh"
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/vpn3288/Agent/main/debian12_hermes_openclaw_perfect_install.sh"

if [ -f "$MAIN_SCRIPT" ]; then
    # shellcheck disable=SC1090
    . "$MAIN_SCRIPT"
else
    if ! command -v curl >/dev/null 2>&1; then
        if [ "${EUID:-$(id -u)}" -ne 0 ]; then
            echo "缺少 curl，且当前不是 root。请先安装 curl 或使用 sudo 运行。" >&2
            exit 1
        fi
        apt-get update
        apt-get install -y curl ca-certificates
    fi

    tmp_script="$(mktemp)"
    trap 'rm -f "$tmp_script"' EXIT
    curl -fsSL "$MAIN_SCRIPT_URL" -o "$tmp_script"
    # shellcheck disable=SC1090
    . "$tmp_script"
fi

agent_main --install hermes "$@"

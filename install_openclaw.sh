#!/usr/bin/env bash
################################################################################
# OpenClaw installer wrapper
# Always prepares the full Debian/Ubuntu AI Agent environment first, then asks
# whether to install OpenClaw immediately or show manual steps.
################################################################################

set -Eeuo pipefail

MAIN_SCRIPT_NAME="debian12_hermes_openclaw_perfect_install.sh"
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/vpn3288/Agent/main/${MAIN_SCRIPT_NAME}"

load_main_installer() {
    local script_dir main_script tmp_script
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    main_script="${script_dir}/${MAIN_SCRIPT_NAME}"

    if [ -f "$main_script" ]; then
        # shellcheck disable=SC1090
        . "$main_script"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        if [ "${EUID:-$(id -u)}" -ne 0 ]; then
            echo "缺少 curl，且当前不是 root。请先安装 curl 或使用 sudo 运行。" >&2
            exit 1
        fi
        apt-get update
        apt-get install -y curl ca-certificates
    fi

    tmp_script="$(mktemp)"
    curl -fsSL "$MAIN_SCRIPT_URL" -o "$tmp_script"
    # shellcheck disable=SC1090
    . "$tmp_script"
    rm -f "$tmp_script"
}

load_main_installer
agent_main --install openclaw "$@"

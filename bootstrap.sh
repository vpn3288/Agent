#!/usr/bin/env bash
################################################################################
# Debian/Ubuntu minimal bootstrap
# Installs curl/ca-certificates if needed, downloads the main installer to a
# temporary file, then executes it so interactive prompts still work.
################################################################################

set -Eeuo pipefail

MAIN_SCRIPT_URL="https://raw.githubusercontent.com/vpn3288/Agent/main/debian12_hermes_openclaw_perfect_install.sh"

echo "============================================================"
echo "  Debian/Ubuntu AI Agent minimal bootstrap"
echo "============================================================"
echo ""

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "错误：需要 root 权限"
    echo "请使用: sudo bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

echo "步骤 1/2: 准备 curl 和证书..."
apt-get update
apt-get install -y curl ca-certificates

echo "步骤 2/2: 下载并运行主安装脚本..."
tmp_script="$(mktemp)"
trap 'rm -f "$tmp_script"' EXIT
curl -fsSL "$MAIN_SCRIPT_URL" -o "$tmp_script"
if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    bash "$tmp_script" "$@" < /dev/tty
else
    bash "$tmp_script" "$@"
fi

echo ""
echo "============================================================"
echo "  bootstrap 执行完成"
echo "============================================================"

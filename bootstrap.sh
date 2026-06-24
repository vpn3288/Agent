#!/bin/bash
################################################################################
# Debian 12 超级精简版启动脚本
# 用途：在最干净的 Debian 12 上先安装 curl，然后运行主安装脚本
################################################################################

set -e

echo "=========================================="
echo "  Debian 12 超级精简版启动脚本"
echo "=========================================="
echo ""

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo "错误：需要 ROOT 权限"
    echo "请使用: sudo bash $0"
    exit 1
fi

echo "步骤 1/2: 安装 curl..."
apt-get update -qq
apt-get install -y curl

echo "步骤 2/2: 下载并运行主安装脚本..."
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/debian12_hermes_openclaw_perfect_install.sh | bash

echo ""
echo "=========================================="
echo "  启动脚本执行完成！"
echo "=========================================="

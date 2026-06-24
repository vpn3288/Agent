#!/bin/bash
################################################################################
# OpenClaw 一键安装脚本
# 前提: 已运行主安装脚本 (debian12_hermes_openclaw_perfect_install.sh)
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  OpenClaw 一键安装${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 加载环境变量
source ~/.bashrc

# 安装 OpenClaw (使用 npm)
echo -e "${GREEN}安装 OpenClaw (最新版)...${NC}"
npm install -g openclaw@latest

# 验证安装
if command -v openclaw &>/dev/null; then
    OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "已安装")
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  OpenClaw 安装完成！${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}OpenClaw 版本: $OPENCLAW_VERSION${NC}"
    echo ""
    echo -e "${YELLOW}下一步操作:${NC}"
    echo ""
    echo -e "1. 运行初始化向导 (推荐):"
    echo -e "   ${GREEN}openclaw onboard --install-daemon${NC}"
    echo ""
    echo -e "2. 启动 Gateway:"
    echo -e "   ${GREEN}openclaw gateway --port 18789 --verbose${NC}"
    echo ""
    echo -e "3. 查看帮助:"
    echo -e "   ${GREEN}openclaw --help${NC}"
    echo ""
else
    echo -e "${RED}OpenClaw 安装失败，请检查错误信息${NC}"
    exit 1
fi

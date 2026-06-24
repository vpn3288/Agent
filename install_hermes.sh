#!/bin/bash
################################################################################
# Hermes Agent 一键安装脚本
# 前提: 已运行主安装脚本 (debian12_hermes_openclaw_perfect_install.sh)
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Hermes Agent 一键安装${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# 加载环境变量
source ~/.bashrc

# 克隆仓库
if [ -d "$HOME/hermes-agent" ]; then
    echo -e "${YELLOW}检测到已存在的 Hermes 目录，更新中...${NC}"
    cd "$HOME/hermes-agent"
    git pull origin main
else
    echo -e "${GREEN}克隆 Hermes Agent 仓库...${NC}"
    cd "$HOME"
    git clone https://github.com/NousResearch/hermes-agent.git
    cd hermes-agent
fi

# 创建虚拟环境
echo -e "${GREEN}创建 Python 虚拟环境...${NC}"
if [ -d ".venv" ]; then
    rm -rf .venv
fi

uv venv .venv --python 3.11

# 激活虚拟环境并安装
echo -e "${GREEN}安装 Hermes Agent (完整版)...${NC}"
source .venv/bin/activate
uv pip install -e ".[all]"

# 创建全局命令链接
echo -e "${GREEN}创建全局命令链接...${NC}"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/hermes-agent/hermes" "$HOME/.local/bin/hermes"

# 添加到 PATH
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Hermes Agent 安装完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}下一步操作:${NC}"
echo ""
echo -e "1. 重新加载环境变量:"
echo -e "   ${GREEN}source ~/.bashrc${NC}"
echo ""
echo -e "2. 启动 Hermes:"
echo -e "   ${GREEN}hermes${NC}"
echo ""
echo -e "3. 运行初始化向导:"
echo -e "   ${GREEN}hermes setup${NC}"
echo ""

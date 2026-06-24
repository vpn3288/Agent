#!/bin/bash
################################################################################
# Hermes Agent 一键安装脚本
# 用途: 在 Debian/Ubuntu 系统上安装基础依赖、uv，并安装 Hermes Agent
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_with_privilege() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_error "需要 root 权限或 sudo 来安装系统依赖"
        exit 1
    fi
}

install_system_dependencies() {
    if ! command -v apt-get >/dev/null 2>&1; then
        log_warning "未检测到 apt-get，跳过系统依赖自动安装"
        return
    fi

    log_info "安装基础系统依赖..."
    export DEBIAN_FRONTEND=noninteractive
    run_with_privilege apt-get update -qq
    run_with_privilege apt-get install -y -qq \
        ca-certificates \
        curl \
        git \
        build-essential \
        python3 \
        python3-venv \
        python3-dev
    log_success "基础系统依赖安装完成"
}

install_uv() {
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if command -v uv >/dev/null 2>&1; then
        log_success "uv 已安装: $(uv --version)"
        return
    fi

    log_info "安装 uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if ! command -v uv >/dev/null 2>&1; then
        log_error "uv 安装失败，请检查网络或手动安装 uv"
        exit 1
    fi

    log_success "uv 安装完成: $(uv --version)"
}

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Hermes Agent 一键安装${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

install_system_dependencies
install_uv

if [ -f "$HOME/.bashrc" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.bashrc" || true
fi

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# 克隆仓库
if [ -d "$HOME/hermes-agent" ]; then
    log_info "检测到已存在的 Hermes 目录，更新中..."
    cd "$HOME/hermes-agent"
    git pull origin main
else
    log_info "克隆 Hermes Agent 仓库..."
    cd "$HOME"
    git clone https://github.com/NousResearch/hermes-agent.git
    cd hermes-agent
fi

# 创建虚拟环境
log_info "创建 Python 3.11 虚拟环境..."
if [ -d ".venv" ]; then
    rm -rf .venv
fi

uv python install 3.11
uv venv .venv --python 3.11

# 激活虚拟环境并安装
log_info "安装 Hermes Agent (完整版)..."
# shellcheck source=/dev/null
source .venv/bin/activate
uv pip install -e ".[all]"

# 创建全局命令链接
log_info "创建全局命令链接..."
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/hermes-agent/hermes" "$HOME/.local/bin/hermes"

# 添加到 PATH
touch "$HOME/.bashrc"
if ! grep -q 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
elif ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
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

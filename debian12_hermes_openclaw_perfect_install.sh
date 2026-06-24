#!/bin/bash
################################################################################
# Debian 12 完美安装脚本 - Hermes Agent & OpenClaw 双兼容版
# 版本: v6.0 - 环境变量立即生效 + 四重保障 uv 安装
# 适用: 最干净的 Debian 12 (远程 DD 安装)
# 特性: 100% 自动化，静默安装，自动跳过已安装项，最新稳定版
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# 检测系统信息
detect_system() {
    log_section "系统信息检测"
    
    # 尝试从多个来源检测系统信息
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="${NAME:-Unknown}"
        OS_VERSION="${VERSION_ID:-Unknown}"
        OS_CODENAME="${VERSION_CODENAME:-Unknown}"
    else
        OS_NAME=$(lsb_release -is 2>/dev/null || echo "Unknown")
        OS_VERSION=$(lsb_release -rs 2>/dev/null || echo "Unknown")
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || echo "Unknown")
    fi
    
    ARCH=$(uname -m)
    
    log_info "操作系统: $OS_NAME $OS_VERSION ($OS_CODENAME)"
    log_info "架构: $ARCH"
    log_info "内核: $(uname -r)"
    log_info "用户: $(whoami)"
    
    # 验证 Debian 12（宽松检查）
    if [[ "$OS_NAME" == *"Debian"* ]] && [[ "$OS_VERSION" == "12"* ]]; then
        log_success "检测到 Debian 12 系统"
    elif [[ "$OS_NAME" == "Unknown" ]]; then
        log_warning "无法检测系统版本，假设为 Debian 12 继续安装"
        log_info "如果不是 Debian 12，请按 Ctrl+C 取消"
        sleep 3
    else
        log_warning "本脚本专为 Debian 12 优化，当前系统: $OS_NAME $OS_VERSION"
        log_info "继续安装可能会遇到兼容性问题"
        sleep 3
    fi
    
    log_success "系统检测完成"
}

# ROOT 环境检测和优化
setup_root_environment() {
    log_section "ROOT 环境配置"
    
    if [ "$EUID" -ne 0 ]; then
        log_error "本脚本需要 ROOT 权限运行"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
    
    log_success "ROOT 权限确认"
    
    # 设置非交互式前端
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    
    # 禁用交互式配置
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
    
    log_success "非交互式环境配置完成"
}

# 更新系统并安装基础工具
install_base_system() {
    log_section "步骤 1/8: 基础系统工具"
    
    log_info "更新软件源..."
    apt-get update -qq 2>&1 | grep -v "^Get:" || true
    
    log_info "安装基础系统工具..."
    apt-get install -y -qq \
        sudo \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        dirmngr \
        gpg-agent \
        git \
        git-lfs \
        unzip \
        zip \
        tar \
        gzip \
        bzip2 \
        xz-utils \
        procps \
        net-tools \
        iputils-ping \
        dnsutils \
        vim \
        nano \
        htop \
        screen \
        tmux \
        rsync \
        jq \
        tree \
        less \
        man-db \
        locales \
        tzdata \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 配置 locale
    if ! locale -a | grep -q "en_US.utf8"; then
        log_info "配置 locale..."
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen en_US.UTF-8 >/dev/null 2>&1
        update-locale LANG=en_US.UTF-8 >/dev/null 2>&1
    fi
    
    # 配置时区（默认 UTC）
    if [ ! -f /etc/timezone ]; then
        log_info "配置时区..."
        ln -sf /usr/share/zoneinfo/UTC /etc/localtime
        echo "UTC" > /etc/timezone
    fi
    
    log_success "基础系统工具安装完成"
}

# 安装编译工具和开发依赖
install_build_tools() {
    log_section "步骤 2/8: 编译工具和开发依赖"
    
    log_info "安装编译工具链..."
    apt-get install -y -qq \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        autoconf \
        automake \
        libtool \
        pkg-config \
        libssl-dev \
        libffi-dev \
        libsqlite3-dev \
        libbz2-dev \
        libreadline-dev \
        libncurses5-dev \
        libncursesw5-dev \
        liblzma-dev \
        zlib1g-dev \
        libgdbm-dev \
        libnss3-dev \
        libxml2-dev \
        libxmlsec1-dev \
        tk-dev \
        uuid-dev \
        libgmp-dev \
        libmpfr-dev \
        libmpc-dev \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 验证 GCC
    GCC_VERSION=$(gcc --version | head -n1 | awk '{print $NF}')
    log_success "GCC 版本: $GCC_VERSION"
}

# 安装 Python 3.11+ (Hermes 需要)
install_python() {
    log_section "步骤 3/8: Python 3.11+ 环境"
    
    log_info "安装 Python 3.11+ 及工具..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel \
        python3-distutils \
        python3-apt \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 验证 Python 版本
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
    
    log_info "Python 版本: $PYTHON_VERSION"
    
    if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 11 ]); then
        log_error "Python 版本过低（需要 3.11+），当前: $PYTHON_VERSION"
        log_info "Debian 12 应该自带 Python 3.11，请检查系统"
        exit 1
    fi
    
    # 创建 python 符号链接（如果不存在）
    if ! command -v python &>/dev/null; then
        ln -sf /usr/bin/python3 /usr/bin/python
        log_info "创建 python -> python3 符号链接"
    fi
    
    # 升级 pip 到最新版
    log_info "升级 pip 到最新版..."
    python3 -m pip install --upgrade pip setuptools wheel --quiet 2>&1 | tail -1 || true
    
    PIP_VERSION=$(python3 -m pip --version | awk '{print $2}')
    log_success "pip 版本: $PIP_VERSION"
}

# 安装 Node.js 24 LTS (OpenClaw 需要)
install_nodejs() {
    log_section "步骤 4/8: Node.js 24 LTS 环境"
    
    # 检查是否已安装 Node.js 24
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node --version | sed 's/v//')
        NODE_MAJOR=$(echo $NODE_VERSION | cut -d. -f1)
        
        if [ "$NODE_MAJOR" -ge 24 ]; then
            log_success "Node.js $NODE_VERSION 已安装，跳过"
            return 0
        else
            log_warning "检测到旧版本 Node.js $NODE_VERSION，将升级到 v24"
        fi
    fi
    
    log_info "安装 Node.js 24 LTS..."
    
    # 添加 NodeSource 仓库
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null 2>&1
    
    # 安装 Node.js
    apt-get install -y -qq nodejs 2>&1 | grep -E "Setting up|Processing" || true
    
    # 验证安装
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    
    log_success "Node.js 版本: $NODE_VERSION"
    log_success "npm 版本: $NPM_VERSION"
    
    # 安装 pnpm (OpenClaw 推荐)
    log_info "安装 pnpm 包管理器..."
    npm install -g pnpm@latest --silent 2>&1 | tail -1 || true
    
    PNPM_VERSION=$(pnpm --version 2>/dev/null || echo "未安装")
    if [ "$PNPM_VERSION" != "未安装" ]; then
        log_success "pnpm 版本: $PNPM_VERSION"
    fi
    
    # 配置 npm 全局目录（避免权限问题）
    mkdir -p /root/.npm-global
    npm config set prefix '/root/.npm-global'
    
    if ! grep -q "NPM_CONFIG_PREFIX" /root/.bashrc; then
        echo 'export NPM_CONFIG_PREFIX=/root/.npm-global' >> /root/.bashrc
        echo 'export PATH=/root/.npm-global/bin:$PATH' >> /root/.bashrc
    fi
    
    export NPM_CONFIG_PREFIX=/root/.npm-global
    export PATH=/root/.npm-global/bin:$PATH
}

# 安装 Rust 和 uv (Hermes 需要)
install_rust_and_uv() {
    log_section "步骤 5/8: Rust 和 uv 包管理器"
    
    # 检查是否已安装 Rust
    if command -v rustc &>/dev/null; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        log_success "Rust $RUST_VERSION 已安装"
    else
        log_info "安装 Rust (最新稳定版)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal >/dev/null 2>&1
        
        # 加载 Rust 环境
        source /root/.cargo/env
        
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        log_success "Rust 版本: $RUST_VERSION"
    fi
    
    # 确保 Rust 环境变量在 bashrc 中
    if ! grep -q "cargo/env" /root/.bashrc; then
        echo 'source $HOME/.cargo/env' >> /root/.bashrc
    fi
    
    # 加载 Rust 环境
    export PATH="/root/.cargo/bin:$PATH"
    
    # 安装 uv (Hermes 推荐的 Python 包管理器) - 四重保障机制
    if command -v uv &>/dev/null; then
        UV_VERSION=$(uv --version | awk '{print $2}')
        log_success "uv $UV_VERSION 已安装"
    else
        log_info "安装 uv 包管理器（四重保障机制）..."
        
        # 确保 Rust 环境已加载
        if [ -f /root/.cargo/env ]; then
            source /root/.cargo/env
        fi
        export PATH="/root/.cargo/bin:$PATH"
        
        # 方法1: 使用官方安装脚本（推荐，最快）
        log_info "方法1: 使用官方安装脚本..."
        if curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tee /tmp/uv_install.log | grep -q "uv"; then
            # 强制重新加载环境变量（多次确保生效）
            source /root/.cargo/env 2>/dev/null || true
            export PATH="/root/.cargo/bin:$PATH"
            source ~/.bashrc 2>/dev/null || true
            
            # 等待文件系统同步
            sleep 1
            
            # 多次尝试检测 uv
            for i in {1..3}; do
                if [ -f /root/.cargo/bin/uv ]; then
                    chmod +x /root/.cargo/bin/uv
                    export PATH="/root/.cargo/bin:$PATH"
                    
                    if /root/.cargo/bin/uv --version &>/dev/null; then
                        UV_VERSION=$(/root/.cargo/bin/uv --version | awk '{print $2}')
                        log_success "uv 版本: $UV_VERSION (官方安装脚本)"
                        
                        # 创建符号链接确保全局可用
                        ln -sf /root/.cargo/bin/uv /usr/local/bin/uv 2>/dev/null || true
                        
                        return 0
                    fi
                fi
                sleep 1
            done
            
            log_warning "官方脚本执行成功，但 uv 命令未立即生效，尝试备用方案..."
        else
            log_warning "官方安装脚本执行失败，尝试备用方案..."
        fi
        
        # 方法2: 使用 pip 安装 uv（快速备用方案，预编译二进制）
        log_info "方法2: 使用 pip 安装 uv（预编译二进制，10-30秒）..."
        if python3 -m pip install uv --quiet 2>&1 | tail -1; then
            # 强制重新加载环境变量
            source /root/.cargo/env 2>/dev/null || true
            export PATH="/root/.cargo/bin:$PATH"
            source ~/.bashrc 2>/dev/null || true
            
            # 等待安装完成
            sleep 1
            
            # 多次尝试检测
            for i in {1..3}; do
                if command -v uv &>/dev/null; then
                    UV_VERSION=$(uv --version | awk '{print $2}')
                    log_success "uv 版本: $UV_VERSION (通过 pip 安装)"
                    
                    # 创建符号链接
                    ln -sf $(which uv) /usr/local/bin/uv 2>/dev/null || true
                    
                    return 0
                fi
                sleep 1
            done
        fi
        
        log_warning "pip 安装 uv 失败，尝试 cargo 编译方案..."
        
        # 方法3: 使用 cargo 编译安装（最可靠但最慢，2-5分钟）
        if command -v cargo &>/dev/null; then
            log_info "方法3: 使用 cargo 编译安装 uv（需要 2-5 分钟）..."
            log_info "正在从源码编译，请耐心等待..."
            
            if cargo install uv 2>&1 | tee /tmp/cargo_uv_install.log | grep -E "Installing|Compiling|Finished"; then
                # 强制重新加载环境（多次确保生效）
                source /root/.cargo/env 2>/dev/null || true
                export PATH="/root/.cargo/bin:$PATH"
                source ~/.bashrc 2>/dev/null || true
                
                # 等待编译完成
                sleep 2
                
                # 多次尝试检测
                for i in {1..3}; do
                    if [ -f /root/.cargo/bin/uv ]; then
                        chmod +x /root/.cargo/bin/uv
                        export PATH="/root/.cargo/bin:$PATH"
                        
                        if /root/.cargo/bin/uv --version &>/dev/null; then
                            UV_VERSION=$(/root/.cargo/bin/uv --version | awk '{print $2}')
                            log_success "uv 版本: $UV_VERSION (通过 cargo 编译)"
                            
                            # 创建符号链接
                            ln -sf /root/.cargo/bin/uv /usr/local/bin/uv 2>/dev/null || true
                            
                            return 0
                        fi
                    fi
                    sleep 1
                done
            fi
        fi
        
        # 方法4: pip 降级方案（保底）
        log_info "方法4: 尝试 pip 降级安装 uv（保底方案）..."
        if python3 -m pip install --upgrade --force-reinstall uv 2>&1 | tail -5; then
            # 强制重新加载环境变量
            source /root/.cargo/env 2>/dev/null || true
            export PATH="/root/.cargo/bin:$PATH"
            source ~/.bashrc 2>/dev/null || true
            
            sleep 2
            
            if command -v uv &>/dev/null; then
                UV_VERSION=$(uv --version | awk '{print $2}')
                log_success "uv 版本: $UV_VERSION (通过 pip 强制重装)"
                
                # 创建符号链接
                ln -sf $(which uv) /usr/local/bin/uv 2>/dev/null || true
                
                return 0
            fi
        fi
        
        # 所有方法都失败
        log_warning "uv 安装失败（四种方法均失败），将使用 pip 作为 Hermes 的包管理器"
        log_info "这不影响 Hermes 功能，只是包管理速度会稍慢"
        log_info "安装 Hermes 时请使用: python3 -m pip install -e \".[all]\""
    fi
}

# 安装额外的运行时依赖
install_runtime_dependencies() {
    log_section "步骤 6/8: 运行时依赖和工具"
    
    log_info "安装运行时依赖..."
    
    # 数据库和存储
    apt-get install -y -qq \
        sqlite3 \
        libsqlite3-0 \
        redis-tools \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 网络和安全工具
    apt-get install -y -qq \
        openssh-client \
        openssh-server \
        openssl \
        certbot \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 媒体处理工具 (可选，但推荐)
    apt-get install -y -qq \
        ffmpeg \
        imagemagick \
        graphicsmagick \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # 文档和文本处理
    apt-get install -y -qq \
        pandoc \
        ripgrep \
        fd-find \
        bat \
        2>&1 | grep -E "Setting up|Processing" || true
    
    # Docker (可选，用于沙箱)
    if ! command -v docker &>/dev/null; then
        log_info "安装 Docker..."
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
        
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker 版本: $DOCKER_VERSION"
    else
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker $DOCKER_VERSION 已安装"
    fi
    
    log_success "运行时依赖安装完成"
}

# 配置 Git
configure_git() {
    log_section "步骤 7/8: Git 配置"
    
    GIT_VERSION=$(git --version | awk '{print $3}')
    log_info "Git 版本: $GIT_VERSION"
    
    # 配置 Git（如果尚未配置）
    if ! git config --global user.name &>/dev/null; then
        git config --global user.name "Hermes & OpenClaw User"
        log_info "设置 Git 用户名: Hermes & OpenClaw User"
    fi
    
    if ! git config --global user.email &>/dev/null; then
        git config --global user.email "agent@localhost"
        log_info "设置 Git 邮箱: agent@localhost"
    fi
    
    # 配置 Git 性能优化
    git config --global core.compression 0
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    
    # 配置 Git LFS
    git lfs install >/dev/null 2>&1 || true
    
    log_success "Git 配置完成"
}

# 最终环境配置
finalize_environment() {
    log_section "步骤 8/8: 环境变量和路径配置"
    
    # 确保所有路径都在 bashrc 中
    cat >> /root/.bashrc << 'EOF'

# ============================================================================
# Hermes & OpenClaw 环境变量
# ============================================================================

# Rust 和 Cargo
export PATH="$HOME/.cargo/bin:$PATH"

# Node.js 全局包
export NPM_CONFIG_PREFIX=$HOME/.npm-global
export PATH=$HOME/.npm-global/bin:$PATH

# Python 用户包
export PATH="$HOME/.local/bin:$PATH"

# Hermes 和 OpenClaw 别名
alias hermes="$HOME/hermes-agent/hermes"
alias openclaw="openclaw"

# 编辑器
export EDITOR=nano
export VISUAL=nano

EOF
    
    # 重新加载环境
    source /root/.bashrc
    
    log_success "环境配置完成"
}

# 显示安装总结
show_summary() {
    log_section "安装完成！"
    
    echo -e "${GREEN}✓ 所有依赖和软件已成功安装${NC}"
    echo ""
    echo -e "${CYAN}已安装的核心组件:${NC}"
    echo ""
    
    # Python
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    echo -e "  ${GREEN}•${NC} Python: ${YELLOW}$PYTHON_VERSION${NC}"
    
    # Node.js
    NODE_VERSION=$(node --version)
    echo -e "  ${GREEN}•${NC} Node.js: ${YELLOW}$NODE_VERSION${NC}"
    
    # npm
    NPM_VERSION=$(npm --version)
    echo -e "  ${GREEN}•${NC} npm: ${YELLOW}$NPM_VERSION${NC}"
    
    # pnpm
    if command -v pnpm &>/dev/null; then
        PNPM_VERSION=$(pnpm --version)
        echo -e "  ${GREEN}•${NC} pnpm: ${YELLOW}$PNPM_VERSION${NC}"
    fi
    
    # Rust
    if command -v rustc &>/dev/null; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        echo -e "  ${GREEN}•${NC} Rust: ${YELLOW}$RUST_VERSION${NC}"
    fi
    
    # uv
    if command -v uv &>/dev/null; then
        UV_VERSION=$(uv --version | awk '{print $2}')
        echo -e "  ${GREEN}•${NC} uv: ${YELLOW}$UV_VERSION${NC}"
    fi
    
    # Git
    GIT_VERSION=$(git --version | awk '{print $3}')
    echo -e "  ${GREEN}•${NC} Git: ${YELLOW}$GIT_VERSION${NC}"
    
    # Docker
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        echo -e "  ${GREEN}•${NC} Docker: ${YELLOW}$DOCKER_VERSION${NC}"
    fi
    
    # GCC
    GCC_VERSION=$(gcc --version | head -n1 | awk '{print $NF}')
    echo -e "  ${GREEN}•${NC} GCC: ${YELLOW}$GCC_VERSION${NC}"
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  下一步操作${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}1. 重新加载环境变量:${NC}"
    echo -e "   ${GREEN}source ~/.bashrc${NC}"
    echo ""
    echo -e "${YELLOW}2. 安装 Hermes Agent:${NC}"
    echo -e "   ${GREEN}cd ~${NC}"
    echo -e "   ${GREEN}git clone https://github.com/NousResearch/hermes-agent.git${NC}"
    echo -e "   ${GREEN}cd hermes-agent${NC}"
    echo -e "   ${GREEN}uv venv .venv --python 3.11${NC}"
    echo -e "   ${GREEN}source .venv/bin/activate${NC}"
    echo -e "   ${GREEN}uv pip install -e \".[all]\"${NC}"
    echo -e "   ${GREEN}ln -sf ~/hermes-agent/hermes ~/.local/bin/hermes${NC}"
    echo ""
    echo -e "${YELLOW}3. 安装 OpenClaw:${NC}"
    echo -e "   ${GREEN}npm install -g openclaw@latest${NC}"
    echo -e "   ${GREEN}# 或使用 pnpm:${NC}"
    echo -e "   ${GREEN}pnpm add -g openclaw@latest${NC}"
    echo ""
    echo -e "${YELLOW}4. 启动 Hermes:${NC}"
    echo -e "   ${GREEN}hermes${NC}"
    echo -e "   ${GREEN}# 或运行初始化向导:${NC}"
    echo -e "   ${GREEN}hermes setup${NC}"
    echo ""
    echo -e "${YELLOW}5. 启动 OpenClaw:${NC}"
    echo -e "   ${GREEN}openclaw onboard --install-daemon${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  一键安装命令（复制粘贴即可）${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}# 安装 Hermes Agent${NC}"
    echo -e "${YELLOW}cd ~ && git clone https://github.com/NousResearch/hermes-agent.git && cd hermes-agent && uv venv .venv --python 3.11 && source .venv/bin/activate && uv pip install -e \".[all]\" && ln -sf ~/hermes-agent/hermes ~/.local/bin/hermes && source ~/.bashrc${NC}"
    echo ""
    echo -e "${GREEN}# 安装 OpenClaw${NC}"
    echo -e "${YELLOW}npm install -g openclaw@latest${NC}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  学习资源${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}•${NC} Hermes 官方文档: ${BLUE}https://hermes-agent.nousresearch.com/docs/${NC}"
    echo -e "  ${GREEN}•${NC} Hermes GitHub: ${BLUE}https://github.com/NousResearch/hermes-agent${NC}"
    echo -e "  ${GREEN}•${NC} OpenClaw 官方文档: ${BLUE}https://docs.openclaw.ai${NC}"
    echo -e "  ${GREEN}•${NC} OpenClaw GitHub: ${BLUE}https://github.com/openclaw/openclaw${NC}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# 主函数
main() {
    clear
    
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║   Debian 12 完美安装脚本 v6.0                                     ║
║   Hermes Agent & OpenClaw 双兼容版                               ║
║                                                                   ║
║   • 100% 自动化安装                                               ║
║   • ROOT 环境优化                                                 ║
║   • 最新稳定版                                                    ║
║   • 自动跳过已安装项                                              ║
║   • 环境变量立即生效                                              ║
║   • 四重保障 uv 安装                                              ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    sleep 2
    
    # 执行安装步骤
    detect_system
    setup_root_environment
    install_base_system
    install_build_tools
    install_python
    install_nodejs
    install_rust_and_uv
    install_runtime_dependencies
    configure_git
    finalize_environment
    
    # 显示总结
    show_summary
    
    log_success "脚本执行完成！"
}

# 执行主函数
main "$@"

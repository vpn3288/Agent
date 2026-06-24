#!/bin/bash
# Hermes Agent 完美安装脚本 v5.0 - Root 专用版
# 适用于 Debian 12 精简版，零交互全自动安装

set -e

echo "=========================================="
echo "  Hermes Agent 完美安装脚本 v5.0"
echo "  Root 环境专用 - 零交互全自动"
echo "=========================================="
echo ""

# 设置非交互模式
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# 步骤 1：更新系统并安装基础依赖
# ============================================================================

echo "📦 步骤 1/9：更新系统并安装基础依赖..."
apt update -qq
apt upgrade -y
apt install -y \
    sudo curl wget ca-certificates gnupg lsb-release \
    apt-transport-https software-properties-common dirmngr gpg-agent \
    git vim nano htop net-tools iputils-ping dnsutils \
    unzip zip tar gzip bzip2 xz-utils

echo "✅ 基础依赖安装完成"
echo ""

# ============================================================================
# 步骤 2：安装编译工具和开发依赖
# ============================================================================

echo "🔧 步骤 2/9：安装编译工具和开发依赖..."
apt install -y \
    build-essential gcc g++ make cmake autoconf automake libtool pkg-config \
    libssl-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncurses5-dev libncursesw5-dev libgdbm-dev liblzma-dev tk-dev uuid-dev \
    zlib1g-dev libxml2-dev libxmlsec1-dev libcurl4-openssl-dev libyaml-dev \
    libgmp-dev libmpfr-dev libmpc-dev

echo "✅ 编译工具安装完成"
echo ""

# ============================================================================
# 步骤 3：安装最新 Python 3.12
# ============================================================================

echo "🐍 步骤 3/9：安装 Python 3.12..."

if command -v python3.12 &> /dev/null; then
    echo "⏭️  Python 3.12 已安装，跳过"
else
    cd /tmp
    wget -q https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz
    tar -xzf Python-3.12.8.tgz
    cd Python-3.12.8
    ./configure --enable-optimizations --with-lto --enable-shared LDFLAGS="-Wl,-rpath /usr/local/lib" > /dev/null
    make -j$(nproc) > /dev/null
    make altinstall > /dev/null
    ldconfig
    cd /tmp
    rm -rf Python-3.12.8 Python-3.12.8.tgz
    
    # 设置默认 Python
    update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.12 1
    update-alternatives --install /usr/bin/python python /usr/local/bin/python3.12 1
    update-alternatives --install /usr/bin/pip3 pip3 /usr/local/bin/pip3.12 1
    update-alternatives --install /usr/bin/pip pip /usr/local/bin/pip3.12 1
fi

echo "✅ Python 3.12 安装完成"
python3 --version
echo ""

# ============================================================================
# 步骤 4：安装 pipx
# ============================================================================

echo "📦 步骤 4/9：安装 pipx..."
python3 -m pip install --upgrade pip setuptools wheel -q
python3 -m pip install pipx -q
python3 -m pipx ensurepath

echo "✅ pipx 安装完成"
echo ""

# ============================================================================
# 步骤 5：安装 uv
# ============================================================================

echo "⚡ 步骤 5/9：安装 uv..."
if command -v uv &> /dev/null; then
    echo "⏭️  uv 已安装，跳过"
else
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# 加载环境变量
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> ~/.bashrc

echo "✅ uv 安装完成"
echo ""

# ============================================================================
# 步骤 6：安装 Node.js 22 LTS
# ============================================================================

echo "🌐 步骤 6/9：安装 Node.js 22 LTS..."

if [ -d "$HOME/.nvm" ]; then
    echo "⏭️  NVM 已安装，跳过"
else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
fi

# 加载 NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 安装 Node.js
nvm install 22
nvm use 22
nvm alias default 22

echo "✅ Node.js 安装完成"
node --version
npm --version
echo ""

# ============================================================================
# 步骤 7：安装 Hermes Agent
# ============================================================================

echo "🎯 步骤 7/9：安装 Hermes Agent..."

# 确保环境变量加载
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

if command -v hermes &> /dev/null; then
    echo "⏭️  Hermes 已安装，执行升级..."
    pipx upgrade hermes-agent
else
    pipx install hermes-agent
fi

echo "✅ Hermes Agent 安装完成"
hermes --version
echo ""

# ============================================================================
# 步骤 8：创建验证脚本
# ============================================================================

echo "📝 步骤 8/9：创建验证脚本..."

cat > /root/verify_hermes.sh << 'EOFVERIFY'
#!/bin/bash

echo "=========================================="
echo "  Hermes Agent 完整环境验证"
echo "=========================================="
echo ""

# 加载环境变量
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1: $($1 --version 2>&1 | head -1)"
    else
        echo -e "${RED}✗${NC} $1: 未安装"
    fi
}

echo "📦 基础工具："
check_command curl
check_command wget
check_command git
check_command sudo
echo ""

echo "🔧 编译工具："
check_command gcc
check_command make
check_command cmake
echo ""

echo "🐍 Python 环境："
check_command python3
check_command pip3
check_command pipx
check_command uv
echo ""

echo "🌐 Node.js 环境："
check_command node
check_command npm
echo ""

echo "🎯 Hermes Agent："
check_command hermes
echo ""

echo "🔑 Hermes 配置检查："
if hermes config get anthropic.api_key &> /dev/null; then
    echo -e "${GREEN}✓${NC} API 密钥已配置"
else
    echo -e "${RED}✗${NC} API 密钥未配置（需要手动配置）"
fi
echo ""

echo "=========================================="
echo "  验证完成"
echo "=========================================="
EOFVERIFY

chmod +x /root/verify_hermes.sh

echo "✅ 验证脚本创建完成"
echo ""

# ============================================================================
# 步骤 9：创建快速启动脚本
# ============================================================================

echo "📝 步骤 9/9：创建快速启动脚本..."

cat > /root/start_hermes.sh << 'EOFSTART'
#!/bin/bash

# 加载环境变量
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# 启动 Hermes
hermes "$@"
EOFSTART

chmod +x /root/start_hermes.sh

echo "✅ 快速启动脚本创建完成"
echo ""

# ============================================================================
# 完成安装
# ============================================================================

echo "🎉 安装完成！"
echo ""
echo "=========================================="
echo "  安装成功！"
echo "=========================================="
echo ""
echo "📝 下一步操作："
echo ""
echo "1. 配置 API 密钥："
echo "   hermes config set anthropic.api_key \"your-api-key-here\""
echo ""
echo "2. 运行验证脚本："
echo "   /root/verify_hermes.sh"
echo ""
echo "3. 启动 Hermes："
echo "   /root/start_hermes.sh"
echo "   或直接运行: hermes"
echo ""
echo "⚠️  重要提醒："
echo "   - 如果当前终端无法识别 hermes 命令，请重新登录或运行："
echo "     source ~/.bashrc"
echo ""
echo "=========================================="

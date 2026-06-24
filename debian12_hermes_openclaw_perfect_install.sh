#!/usr/bin/env bash
################################################################################
# Debian/Ubuntu AI Agent stable installer
# Covers OpenClaw, Hermes Agent, and a reusable base environment for other agents.
#
# Flow:
#   1. Prepare all system dependencies first on clean Debian/Ubuntu.
#   2. Verify language/runtime/tooling support.
#   3. Ask whether to install OpenClaw/Hermes immediately or show manual steps.
################################################################################

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

AGENT_INSTALLER_VERSION="v7.0"
AGENT_NODE_MAJOR="${AGENT_NODE_MAJOR:-24}"
AGENT_LOG_FILE="${AGENT_LOG_FILE:-/var/log/agent-perfect-install.log}"
AGENT_WORKDIR="${AGENT_WORKDIR:-/opt/ai-agents}"
AGENT_APT_UPGRADE="${AGENT_APT_UPGRADE:-0}"
AGENT_INSTALL_DOCKER="${AGENT_INSTALL_DOCKER:-1}"
AGENT_INSTALL_BROWSER="${AGENT_INSTALL_BROWSER:-1}"

INSTALL_TARGET="menu"
ASSUME_YES=0
MANUAL_ONLY=0
DEPS_ONLY=0
LOGGING_INITIALIZED=0
APT_UPDATED=0

# Keep system Node/Python ahead of any nvm/asdf paths. This avoids mixed Node
# installs breaking OpenClaw after npm global installation.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/.cargo/bin"
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

log_info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

init_logging() {
    if [ "$LOGGING_INITIALIZED" -eq 1 ]; then
        return 0
    fi

    mkdir -p "$(dirname "$AGENT_LOG_FILE")"
    touch "$AGENT_LOG_FILE"
    chmod 0644 "$AGENT_LOG_FILE"
    exec > >(tee -a "$AGENT_LOG_FILE") 2>&1
    LOGGING_INITIALIZED=1
}

error_handler() {
    local exit_code=$?
    local line_no=${1:-unknown}
    log_error "脚本在第 ${line_no} 行失败，退出码: ${exit_code}"
    log_error "完整日志: ${AGENT_LOG_FILE}"
    exit "$exit_code"
}

retry() {
    local attempts=$1
    local delay=$2
    shift 2

    local n=1
    until "$@"; do
        if [ "$n" -ge "$attempts" ]; then
            return 1
        fi
        log_warning "命令失败，${delay}s 后重试 (${n}/${attempts}): $*"
        sleep "$delay"
        n=$((n + 1))
    done
}

run_bash_with_retry() {
    local attempts=$1
    local delay=$2
    local script=$3
    retry "$attempts" "$delay" bash -o pipefail -c "$script"
}

append_once() {
    local file=$1
    local line=$2

    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -Fqx "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
}

append_block_once() {
    local file=$1
    local marker=$2
    local block=$3

    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -Fq "$marker" "$file"; then
        printf '\n%s\n' "$block" >> "$file"
    fi
}

command_version() {
    local cmd=$1
    if command -v "$cmd" >/dev/null 2>&1; then
        "$cmd" --version 2>&1 | head -n 1 || true
    else
        echo "未安装"
    fi
}

has_tty() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "需要 root 权限运行。请使用: sudo bash $0"
        exit 1
    fi
}

detect_system() {
    log_section "系统检测"

    if [ ! -f /etc/os-release ]; then
        log_error "无法读取 /etc/os-release。本脚本仅支持 Debian/Ubuntu 系。"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
    ARCH="$(uname -m)"

    log_info "操作系统: ${OS_NAME}"
    log_info "版本 ID: ${OS_VERSION}"
    log_info "架构: ${ARCH}"
    log_info "内核: $(uname -r)"
    log_info "当前用户: $(whoami)"

    case "$OS_ID" in
        debian|ubuntu)
            log_success "检测到受支持的 Debian/Ubuntu 系统"
            ;;
        *)
            if [[ "$OS_LIKE" == *"debian"* ]]; then
                log_warning "检测到 Debian-like 系统 (${OS_ID})，继续使用 apt 流程"
            elif [ "${AGENT_FORCE:-0}" = "1" ]; then
                log_warning "当前系统不是 Debian/Ubuntu，但 AGENT_FORCE=1，继续执行"
            else
                log_error "当前系统不是 Debian/Ubuntu。若确认兼容，可设置 AGENT_FORCE=1 后重试。"
                exit 1
            fi
            ;;
    esac

    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
        log_warning "当前架构 ${ARCH} 不是常见服务器架构，部分上游二进制包可能不可用"
    fi
}

setup_noninteractive_apt() {
    log_section "非交互安装环境"

    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections || true
    export NEEDRESTART_MODE=a
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none

    log_success "APT 非交互模式已启用"
}

wait_for_apt_locks() {
    if ! command -v fuser >/dev/null 2>&1; then
        return 0
    fi

    local locks=(
        /var/lib/dpkg/lock
        /var/lib/dpkg/lock-frontend
        /var/lib/apt/lists/lock
        /var/cache/apt/archives/lock
    )
    local waited=0
    while fuser "${locks[@]}" >/dev/null 2>&1; do
        if [ "$waited" -ge 300 ]; then
            log_error "等待 apt/dpkg 锁超过 300 秒"
            return 1
        fi
        log_info "等待 apt/dpkg 锁释放..."
        sleep 5
        waited=$((waited + 5))
    done
}

apt_update_once() {
    if [ "$APT_UPDATED" -eq 1 ]; then
        return 0
    fi

    wait_for_apt_locks
    log_info "更新 APT 软件源..."
    retry 3 5 apt-get update
    APT_UPDATED=1
}

apt_install_required() {
    local packages=("$@")
    if [ "${#packages[@]}" -eq 0 ]; then
        return 0
    fi

    apt_update_once
    wait_for_apt_locks

    log_info "安装必需软件包: ${packages[*]}"
    if retry 2 5 apt-get install -y "${packages[@]}"; then
        return 0
    fi

    log_warning "批量安装失败，改为逐个安装以定位缺失包"
    local pkg
    for pkg in "${packages[@]}"; do
        wait_for_apt_locks
        retry 3 5 apt-get install -y "$pkg" || {
            log_error "必需软件包安装失败: ${pkg}"
            return 1
        }
    done
}

apt_install_optional() {
    local packages=("$@")
    local pkg

    apt_update_once
    for pkg in "${packages[@]}"; do
        wait_for_apt_locks
        if apt-get install -y "$pkg"; then
            log_success "可选软件包已安装: ${pkg}"
        else
            log_warning "可选软件包不可用或安装失败，已跳过: ${pkg}"
        fi
    done
}

apt_install_one_of() {
    local label=$1
    shift

    apt_update_once

    local pkg
    for pkg in "$@"; do
        wait_for_apt_locks
        if apt-get install -y "$pkg"; then
            log_success "${label}: 使用 ${pkg}"
            return 0
        fi
    done

    log_warning "${label}: 未找到可安装的候选包: $*"
    return 1
}

install_base_system() {
    log_section "步骤 1/9: 基础系统软件"

    apt_update_once
    if [ "$AGENT_APT_UPGRADE" = "1" ]; then
        log_info "AGENT_APT_UPGRADE=1，执行系统升级..."
        wait_for_apt_locks
        retry 2 10 apt-get dist-upgrade -y
    fi

    apt_install_required \
        sudo curl wget ca-certificates gnupg lsb-release apt-transport-https \
        software-properties-common dirmngr gpg-agent git unzip zip tar gzip \
        bzip2 xz-utils procps psmisc net-tools iputils-ping dnsutils locales \
        tzdata openssh-client openssh-server openssl rsync jq less nano vim htop \
        screen tmux

    apt_install_optional \
        git-lfs tree man-db bash-completion needrestart unattended-upgrades

    if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
        log_info "配置 en_US.UTF-8 locale..."
        if ! grep -Fq "en_US.UTF-8 UTF-8" /etc/locale.gen 2>/dev/null; then
            echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        fi
        locale-gen en_US.UTF-8 || true
        update-locale LANG=en_US.UTF-8 || true
    fi

    log_success "基础系统软件完成"
}

install_build_tools() {
    log_section "步骤 2/9: 编译工具和开发头文件"

    apt_install_required \
        build-essential gcc g++ make cmake autoconf automake libtool pkg-config \
        libssl-dev libffi-dev libsqlite3-dev libbz2-dev libreadline-dev \
        libncurses-dev libncursesw5-dev liblzma-dev zlib1g-dev libgdbm-dev \
        libnss3-dev libxml2-dev libxmlsec1-dev tk-dev uuid-dev libgmp-dev \
        libmpfr-dev libmpc-dev libcurl4-openssl-dev libyaml-dev

    apt_install_optional \
        clang llvm gdb strace ltrace valgrind libjpeg-dev libpng-dev \
        libsndfile1 portaudio19-dev

    log_success "GCC: $(command_version gcc)"
}

install_python_stack() {
    log_section "步骤 3/9: Python / pipx / uv 基础"

    apt_install_required \
        python3 python3-pip python3-venv python3-dev python3-setuptools \
        python3-wheel python3-apt

    apt_install_optional pipx python3-distutils python3-full

    if ! command -v python >/dev/null 2>&1; then
        ln -sf /usr/bin/python3 /usr/local/bin/python
    fi

    log_success "Python: $(command_version python3)"
    log_success "pip: $(python3 -m pip --version 2>/dev/null || echo 'pip 未就绪')"
}

node_meets_openclaw_requirement() {
    if ! command -v node >/dev/null 2>&1; then
        return 1
    fi

    local version major minor
    version="$(node --version | sed 's/^v//')"
    major="${version%%.*}"
    minor="$(echo "$version" | cut -d. -f2)"

    if [ "$major" -gt 24 ]; then
        return 0
    fi
    if [ "$major" -eq 24 ]; then
        return 0
    fi
    if [ "$major" -eq 22 ] && [ "$minor" -ge 19 ]; then
        return 0
    fi
    return 1
}

install_nodejs_stack() {
    log_section "步骤 4/9: Node.js / npm / pnpm"

    if [[ "$AGENT_NODE_MAJOR" != "24" && "$AGENT_NODE_MAJOR" != "22" ]]; then
        log_warning "AGENT_NODE_MAJOR=${AGENT_NODE_MAJOR} 不在推荐值 24/22 内，自动改为 24"
        AGENT_NODE_MAJOR=24
    fi

    if node_meets_openclaw_requirement; then
        log_success "Node.js 已满足 OpenClaw 要求: $(node --version)"
    else
        log_info "安装 Node.js ${AGENT_NODE_MAJOR}.x (OpenClaw 推荐 Node 24，兼容 Node 22.19+)"
        run_bash_with_retry 3 8 "curl -fsSL https://deb.nodesource.com/setup_${AGENT_NODE_MAJOR}.x | bash -"
        apt_install_required nodejs
        hash -r
    fi

    if ! node_meets_openclaw_requirement; then
        log_error "Node.js 版本仍不满足要求: $(command_version node)"
        exit 1
    fi

    npm config set prefix /usr/local >/dev/null
    npm config set fund false >/dev/null || true
    npm config set audit false >/dev/null || true
    npm config set update-notifier false >/dev/null || true

    log_success "Node.js: $(node --version)"
    log_success "npm: $(npm --version)"

    if command -v corepack >/dev/null 2>&1; then
        corepack enable || true
    fi

    if ! command -v pnpm >/dev/null 2>&1; then
        log_info "安装 pnpm..."
        retry 3 5 npm install -g pnpm@latest
        hash -r
    fi

    if command -v pnpm >/dev/null 2>&1; then
        log_success "pnpm: $(pnpm --version)"
    else
        log_warning "pnpm 未安装成功；OpenClaw npm 安装不依赖 pnpm，源码构建时可能需要"
    fi
}

install_rust_and_uv() {
    log_section "步骤 5/9: Rust / uv / Python 3.11 托管运行时"

    if ! command -v rustc >/dev/null 2>&1; then
        log_info "安装 Rust stable minimal..."
        run_bash_with_retry 3 8 "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal"
    fi

    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1090
        . "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"

    if command -v rustc >/dev/null 2>&1; then
        log_success "Rust: $(rustc --version)"
    else
        log_warning "Rust 未安装成功；大部分预编译包仍可继续使用"
    fi

    if ! command -v uv >/dev/null 2>&1; then
        log_info "安装 uv (官方安装脚本)..."
        if ! run_bash_with_retry 3 8 "curl -LsSf https://astral.sh/uv/install.sh | sh"; then
            log_warning "官方 uv 安装失败，尝试 pipx/pip/cargo 备用方案"
        fi
    fi

    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    hash -r || true

    if ! command -v uv >/dev/null 2>&1 && command -v pipx >/dev/null 2>&1; then
        pipx install uv || pipx upgrade uv || true
        export PATH="$HOME/.local/bin:$PATH"
        hash -r || true
    fi

    if ! command -v uv >/dev/null 2>&1; then
        python3 -m pip install --user --break-system-packages uv || true
        export PATH="$HOME/.local/bin:$PATH"
        hash -r || true
    fi

    if ! command -v uv >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
        cargo install uv || true
        export PATH="$HOME/.cargo/bin:$PATH"
        hash -r || true
    fi

    if ! command -v uv >/dev/null 2>&1; then
        log_error "uv 安装失败。Hermes Agent 需要 uv 才能稳定创建 Python 3.11 环境。"
        exit 1
    fi

    ln -sf "$(command -v uv)" /usr/local/bin/uv
    log_success "uv: $(uv --version)"

    log_info "预安装 uv 托管 Python 3.11..."
    uv python install 3.11 || log_warning "uv 托管 Python 3.11 预安装失败；Hermes 安装时会再次尝试"
}

install_runtime_dependencies() {
    log_section "步骤 6/9: AI Agent 运行时依赖"

    apt_install_required \
        sqlite3 redis-tools ffmpeg imagemagick graphicsmagick pandoc ripgrep \
        fd-find bat xclip xauth xvfb dbus-x11

    apt_install_optional \
        postgresql-client redis-server certbot \
        shellcheck shfmt graphviz

    apt_install_one_of "MySQL 客户端" default-mysql-client mysql-client || true
    apt_install_one_of "音频运行库" libasound2t64 libasound2 || true
    apt_install_one_of "Chromium 浏览器" chromium chromium-browser || true

    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    fi
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        ln -sf "$(command -v batcat)" /usr/local/bin/bat
    fi

    log_success "运行时依赖完成"
}

install_browser_dependencies() {
    log_section "步骤 7/9: 浏览器自动化依赖"

    apt_install_required \
        libnss3 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 \
        libatspi2.0-0 libglib2.0-0 libx11-6 libxcb1 libxext6 libxrender1 \
        libxtst6 libx11-xcb1 libxshmfence1 fonts-liberation fonts-noto-color-emoji

    apt_install_one_of "ATK 运行库" libatk1.0-0t64 libatk1.0-0 || true
    apt_install_one_of "ATK Bridge 运行库" libatk-bridge2.0-0t64 libatk-bridge2.0-0 || true
    apt_install_one_of "CUPS 运行库" libcups2t64 libcups2 || true
    apt_install_one_of "GTK 3 运行库" libgtk-3-0t64 libgtk-3-0 || true

    log_success "浏览器自动化依赖完成"
}

setup_docker_official_repository() {
    if [[ "${OS_ID:-}" != "debian" && "${OS_ID:-}" != "ubuntu" ]]; then
        log_warning "Docker 官方仓库仅自动配置 Debian/Ubuntu，当前 OS_ID=${OS_ID:-unknown}"
        return 1
    fi

    local codename arch repo_url keyring list_file
    codename="${VERSION_CODENAME:-}"
    if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
        codename="$(lsb_release -cs)"
    fi
    if [ -z "$codename" ]; then
        log_warning "无法检测系统代号，跳过 Docker 官方仓库配置"
        return 1
    fi

    arch="$(dpkg --print-architecture)"
    repo_url="https://download.docker.com/linux/${OS_ID}"
    keyring="/etc/apt/keyrings/docker.asc"
    list_file="/etc/apt/sources.list.d/docker.list"

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "${repo_url}/gpg" -o "$keyring"
    chmod a+r "$keyring"

    echo "deb [arch=${arch} signed-by=${keyring}] ${repo_url} ${codename} stable" > "$list_file"
    APT_UPDATED=0
    apt_update_once
}

install_docker_support() {
    log_section "步骤 8/9: Docker 沙箱支持"

    if [ "$AGENT_INSTALL_DOCKER" != "1" ]; then
        log_warning "AGENT_INSTALL_DOCKER!=1，跳过 Docker"
        return 0
    fi

    log_info "优先安装 Docker 官方 stable 版本..."
    if setup_docker_official_repository; then
        wait_for_apt_locks
        apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc >/dev/null 2>&1 || true
        if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            log_success "Docker 官方 stable 版本已安装"
        else
            log_warning "Docker 官方 stable 版本安装失败，回退发行版软件源版本"
            apt_install_optional docker.io docker-compose docker-compose-plugin
        fi
    else
        log_warning "Docker 官方仓库配置失败，回退发行版软件源版本"
        apt_install_optional docker.io docker-compose docker-compose-plugin
    fi

    if command -v docker >/dev/null 2>&1; then
        if command -v systemctl >/dev/null 2>&1 && systemctl list-system-units >/dev/null 2>&1; then
            systemctl enable docker >/dev/null 2>&1 || true
            systemctl start docker >/dev/null 2>&1 || true
        else
            service docker start >/dev/null 2>&1 || true
        fi

        if getent group docker >/dev/null 2>&1; then
            if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
                usermod -aG docker "$SUDO_USER" || true
                log_info "已将 ${SUDO_USER} 加入 docker 组；重新登录后生效"
            fi
        fi

        log_success "Docker: $(docker --version 2>/dev/null || echo '已安装')"
    else
        log_warning "Docker 未安装成功；Hermes/OpenClaw 基础安装可继续，Docker 后端需手动补装"
    fi
}

configure_git_and_permissions() {
    log_section "步骤 9/9: Git / 权限 / 稳定性优化"

    mkdir -p "$AGENT_WORKDIR" /usr/local/bin /usr/local/share/ai-agents "$HOME/.local/bin"
    chmod 0755 "$AGENT_WORKDIR" /usr/local/bin /usr/local/share/ai-agents "$HOME/.local/bin"

    if ! git config --global user.name >/dev/null 2>&1; then
        git config --global user.name "AI Agent User"
    fi
    if ! git config --global user.email >/dev/null 2>&1; then
        git config --global user.email "agent@localhost"
    fi
    git config --global core.compression 0
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git lfs install >/dev/null 2>&1 || true

    cat > /etc/profile.d/ai-agent-env.sh <<'EOF'
# AI Agent runtime environment
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-nano}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
EOF
    chmod 0644 /etc/profile.d/ai-agent-env.sh

    append_block_once "$HOME/.bashrc" "# AI Agent runtime environment" '# AI Agent runtime environment
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-nano}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"'

    cat > /etc/security/limits.d/99-ai-agent.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    chmod 0644 /etc/security/limits.d/99-ai-agent.conf

    cat > /etc/sysctl.d/99-ai-agent.conf <<'EOF'
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
net.core.somaxconn = 65535
EOF
    sysctl --system >/dev/null 2>&1 || true

    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        usermod -aG sudo "$SUDO_USER" || true
        log_info "已确认 ${SUDO_USER} 具备 sudo 组权限"
    fi

    log_success "Git/权限/稳定性优化完成"
}

write_doctor_script() {
    cat > /usr/local/bin/agent-env-doctor <<'EOF'
#!/usr/bin/env bash
set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_command() {
    local cmd=$1
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "%bOK%b %-12s %s\n" "$GREEN" "$NC" "$cmd" "$($cmd --version 2>&1 | head -n 1 || true)"
    else
        printf "%bMISS%b %-12s 未安装\n" "$RED" "$NC" "$cmd"
    fi
}

echo "AI Agent 环境检查"
echo "============================================================"
for cmd in curl wget git gcc make cmake python3 pip3 uv node npm pnpm rg ffmpeg docker; do
    check_command "$cmd"
done
echo "============================================================"

if command -v node >/dev/null 2>&1; then
    node_version="$(node --version | sed 's/^v//')"
    node_major="${node_version%%.*}"
    node_minor="$(echo "$node_version" | cut -d. -f2)"
    if [ "$node_major" -ge 24 ] || { [ "$node_major" -eq 22 ] && [ "$node_minor" -ge 19 ]; }; then
        printf "%bOK%b OpenClaw Node requirement satisfied: v%s\n" "$GREEN" "$NC" "$node_version"
    else
        printf "%bWARN%b OpenClaw needs Node 24 recommended or Node 22.19+: v%s\n" "$YELLOW" "$NC" "$node_version"
    fi
fi

if command -v hermes >/dev/null 2>&1; then
    check_command hermes
else
    printf "%bMISS%b hermes      未安装；可运行 install_hermes.sh 或主脚本菜单安装\n" "$YELLOW" "$NC"
fi

if command -v openclaw >/dev/null 2>&1; then
    check_command openclaw
else
    printf "%bMISS%b openclaw    未安装；可运行 install_openclaw.sh 或主脚本菜单安装\n" "$YELLOW" "$NC"
fi
EOF
    chmod +x /usr/local/bin/agent-env-doctor
}

prepare_all_dependencies() {
    require_root
    detect_system
    setup_noninteractive_apt
    install_base_system
    install_build_tools
    install_python_stack
    install_nodejs_stack
    install_rust_and_uv
    install_runtime_dependencies
    install_browser_dependencies
    install_docker_support
    configure_git_and_permissions
    write_doctor_script

    log_success "所有基础依赖、软件、运行时支持和稳定性优化已完成"
}

manual_openclaw_steps() {
    cat <<'EOF'

OpenClaw 手动安装步骤
============================================================
依赖已经准备完成。你可以任选一种方式手动安装:

1. 官方安装器:
   curl -fsSL https://openclaw.ai/install.sh | bash
   # 只安装本体、不立即 onboarding:
   curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard

2. npm 全局安装:
   npm install -g openclaw@latest

3. 安装后初始化:
   openclaw onboard --install-daemon
   openclaw gateway --port 18789 --verbose

验证:
   openclaw --version
   agent-env-doctor
============================================================
EOF
}

manual_hermes_steps() {
    cat <<'EOF'

Hermes Agent 手动安装步骤
============================================================
依赖已经准备完成。推荐使用官方安装器安装 Hermes 本体:

   curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup

如需源码/开发模式，再使用下面的手动方式:

   cd ~
   git clone https://github.com/NousResearch/hermes-agent.git
   cd hermes-agent
   uv python install 3.11
   uv venv .venv --python 3.11
   source .venv/bin/activate
   uv pip install -e ".[all]"
   ln -sf "$PWD/.venv/bin/hermes" /usr/local/bin/hermes

验证:
   hermes --version
   hermes doctor
   agent-env-doctor
============================================================
EOF
}

manual_other_agent_steps() {
    cat <<'EOF'

其他 AI Agent 通用环境说明
============================================================
本脚本已准备通用 agent 环境:

   - Debian/Ubuntu 基础工具和编译链
   - Python 3 / uv / uv-managed Python 3.11
   - Node.js 24 默认运行时，兼容 OpenClaw 的 Node 22.19+ 要求
   - npm / pnpm
   - ripgrep / fd / bat / jq / ffmpeg / ImageMagick / pandoc
   - browser automation 运行库和可选 Chromium
   - Docker 沙箱支持
   - Git/LFS、PATH、limits、sysctl 稳定性优化

新增其他 agent 时，建议遵循同一流程:

   1. 先运行本脚本完成依赖准备。
   2. 再安装 agent 本体。
   3. 最后运行 agent 自带 doctor/verify 命令和 agent-env-doctor。
============================================================
EOF
}

prompt_yes_no() {
    local prompt=$1
    local default=${2:-yes}
    local answer

    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi

    if ! has_tty; then
        log_warning "当前不是交互式终端，默认不立即安装。需要自动安装请加 --yes。"
        return 1
    fi

    if [ "$default" = "yes" ]; then
        read -r -p "${prompt} [Y/n]: " answer < /dev/tty
        answer="${answer:-Y}"
    else
        read -r -p "${prompt} [y/N]: " answer < /dev/tty
        answer="${answer:-N}"
    fi

    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

install_openclaw_agent() {
    log_section "安装 OpenClaw"

    if ! node_meets_openclaw_requirement; then
        log_error "Node.js 不满足 OpenClaw 要求，请先重新运行依赖准备"
        exit 1
    fi

    npm config set prefix /usr/local >/dev/null
    log_info "使用 npm 安装 OpenClaw latest..."
    if ! retry 3 8 npm install -g openclaw@latest; then
        log_warning "npm 安装 OpenClaw 失败，尝试官方安装器"
        run_bash_with_retry 2 8 "curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard"
    fi

    hash -r || true
    if ! command -v openclaw >/dev/null 2>&1; then
        log_error "OpenClaw 安装后未找到 openclaw 命令"
        manual_openclaw_steps
        exit 1
    fi

    log_success "OpenClaw: $(openclaw --version 2>/dev/null || echo '已安装')"
    cat <<'EOF'

下一步:
   openclaw onboard --install-daemon
   openclaw gateway --port 18789 --verbose
EOF
}

install_hermes_from_source() {
    local repo_dir="${HERMES_DIR:-$HOME/hermes-agent}"
    mkdir -p "$(dirname "$repo_dir")"

    if [ -d "$repo_dir/.git" ]; then
        log_info "检测到已有 Hermes 仓库，尝试更新: ${repo_dir}"
        if ! git -C "$repo_dir" pull --ff-only origin main; then
            log_warning "Hermes 仓库无法 fast-forward 更新，继续使用当前工作副本"
        fi
    else
        log_info "克隆 Hermes Agent 仓库..."
        git clone https://github.com/NousResearch/hermes-agent.git "$repo_dir"
    fi

    cd "$repo_dir"

    log_info "创建 Python 3.11 虚拟环境..."
    uv python install 3.11 || true
    rm -rf .venv
    uv venv .venv --python 3.11

    # shellcheck disable=SC1091
    . .venv/bin/activate

    log_info "安装 Hermes Agent 完整依赖..."
    uv pip install --upgrade pip setuptools wheel
    if ! uv pip install -e ".[all]"; then
        log_warning "Hermes [all] 额外依赖安装失败，尝试安装核心包"
        uv pip install -e .
    fi

    if [ "$AGENT_INSTALL_BROWSER" = "1" ] && [ -x ".venv/bin/playwright" ]; then
        log_info "安装 Playwright Chromium 浏览器资源..."
        .venv/bin/playwright install chromium || log_warning "Playwright 浏览器资源下载失败，可稍后手动运行: playwright install chromium"
    fi

    if [ -x "$repo_dir/.venv/bin/hermes" ]; then
        ln -sf "$repo_dir/.venv/bin/hermes" /usr/local/bin/hermes
    elif [ -x "$repo_dir/hermes" ]; then
        ln -sf "$repo_dir/hermes" /usr/local/bin/hermes
    else
        log_warning "未找到 Hermes 可执行文件，请检查安装日志"
    fi
}

install_hermes_agent() {
    log_section "安装 Hermes Agent"

    if ! command -v uv >/dev/null 2>&1; then
        log_error "uv 未安装，无法稳定安装 Hermes Agent"
        exit 1
    fi

    local hermes_flags="--skip-setup"
    if [ "$AGENT_INSTALL_BROWSER" != "1" ]; then
        hermes_flags="${hermes_flags} --skip-browser"
    fi

    log_info "使用 Hermes 官方安装器安装本体..."
    if ! run_bash_with_retry 2 8 "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- ${hermes_flags}"; then
        log_warning "Hermes 官方安装器失败，回退到源码安装"
        install_hermes_from_source
    fi

    if [ -x "$HOME/.local/bin/hermes" ] && ! command -v hermes >/dev/null 2>&1; then
        ln -sf "$HOME/.local/bin/hermes" /usr/local/bin/hermes
        hash -r || true
    fi

    hash -r || true
    if command -v hermes >/dev/null 2>&1; then
        log_success "Hermes: $(hermes --version 2>/dev/null || echo '已安装')"
    else
        log_error "Hermes 安装后未找到 hermes 命令"
        manual_hermes_steps
        exit 1
    fi

    cat <<'EOF'

下一步:
   hermes setup
   hermes doctor
EOF
}

handle_target_install() {
    local target=$1

    case "$target" in
        deps)
            manual_openclaw_steps
            manual_hermes_steps
            manual_other_agent_steps
            ;;
        openclaw)
            if [ "$MANUAL_ONLY" -eq 1 ]; then
                manual_openclaw_steps
            elif prompt_yes_no "依赖已全部安装完成，是否马上安装 OpenClaw？" yes; then
                install_openclaw_agent
            else
                manual_openclaw_steps
            fi
            ;;
        hermes)
            if [ "$MANUAL_ONLY" -eq 1 ]; then
                manual_hermes_steps
            elif prompt_yes_no "依赖已全部安装完成，是否马上安装 Hermes Agent？" yes; then
                install_hermes_agent
            else
                manual_hermes_steps
            fi
            ;;
        all)
            if [ "$MANUAL_ONLY" -eq 1 ]; then
                manual_openclaw_steps
                manual_hermes_steps
            else
                if prompt_yes_no "依赖已全部安装完成，是否马上安装 OpenClaw？" yes; then
                    install_openclaw_agent
                else
                    manual_openclaw_steps
                fi
                if prompt_yes_no "是否马上安装 Hermes Agent？" yes; then
                    install_hermes_agent
                else
                    manual_hermes_steps
                fi
            fi
            ;;
        other)
            manual_other_agent_steps
            ;;
        *)
            log_error "未知安装目标: ${target}"
            exit 1
            ;;
    esac
}

show_final_menu() {
    log_section "依赖准备完成，选择下一步"

    if ! has_tty; then
        log_warning "非交互模式下不会弹出菜单。"
        manual_openclaw_steps
        manual_hermes_steps
        manual_other_agent_steps
        return 0
    fi

    cat <<'EOF'
请选择要马上安装的 Agent:

  1) OpenClaw
  2) Hermes Agent
  3) OpenClaw + Hermes Agent
  4) 只显示手动安装步骤
  5) 其他 AI Agent 通用环境说明
  0) 退出
EOF

    local choice
    read -r -p "请输入选项 [1-5/0]: " choice < /dev/tty
    case "${choice:-4}" in
        1) handle_target_install openclaw ;;
        2) handle_target_install hermes ;;
        3) handle_target_install all ;;
        4) handle_target_install deps ;;
        5) handle_target_install other ;;
        0) log_info "已退出；依赖环境仍已准备完成" ;;
        *) log_warning "无效选项，显示手动安装步骤"; handle_target_install deps ;;
    esac
}

show_summary() {
    log_section "环境摘要"

    echo -e "${GREEN}基础环境已完成。可随时运行:${NC}"
    echo "   agent-env-doctor"
    echo ""
    echo -e "${CYAN}核心版本:${NC}"
    echo "   Python:  $(command_version python3)"
    echo "   uv:      $(command_version uv)"
    echo "   Node.js: $(command_version node)"
    echo "   npm:     $(command_version npm)"
    echo "   pnpm:    $(command_version pnpm)"
    echo "   Git:     $(command_version git)"
    echo "   rg:      $(command_version rg)"
    echo "   ffmpeg:  $(command_version ffmpeg)"
    echo "   Docker:  $(command_version docker)"
    echo ""
    echo "日志文件: ${AGENT_LOG_FILE}"
}

show_help() {
    cat <<EOF
用法:
  sudo bash $0 [选项]

选项:
  --install openclaw|hermes|all|deps|other
      依赖准备完成后处理指定目标。默认显示菜单。

  --yes, -y
      非交互确认，适合自动化安装。

  --manual
      只准备依赖并显示手动安装步骤，不安装 agent 本体。

  --deps-only
      只准备依赖，等价于 --install deps --manual。

  --node-major 24|22
      选择 NodeSource 大版本。默认 24；Hermes 严格需要 Node 22 时可改为 22。

环境变量:
  AGENT_APT_UPGRADE=1       依赖安装前执行 dist-upgrade
  AGENT_INSTALL_DOCKER=0    跳过 Docker
  AGENT_INSTALL_BROWSER=0   跳过 Playwright 浏览器资源下载
  HERMES_DIR=/path          指定 Hermes 仓库目录
EOF
}

parse_args() {
    INSTALL_TARGET="menu"
    ASSUME_YES=0
    MANUAL_ONLY=0
    DEPS_ONLY=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install)
                INSTALL_TARGET="${2:-}"
                shift 2
                ;;
            --install=*)
                INSTALL_TARGET="${1#*=}"
                shift
                ;;
            --yes|-y)
                ASSUME_YES=1
                shift
                ;;
            --manual)
                MANUAL_ONLY=1
                shift
                ;;
            --deps-only)
                DEPS_ONLY=1
                INSTALL_TARGET="deps"
                MANUAL_ONLY=1
                shift
                ;;
            --node-major)
                AGENT_NODE_MAJOR="${2:-24}"
                shift 2
                ;;
            --node-major=*)
                AGENT_NODE_MAJOR="${1#*=}"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    case "$INSTALL_TARGET" in
        menu|openclaw|hermes|all|deps|other) ;;
        *)
            log_error "无效 --install 目标: ${INSTALL_TARGET}"
            exit 1
            ;;
    esac

    if [ "$DEPS_ONLY" -eq 1 ]; then
        INSTALL_TARGET="deps"
        MANUAL_ONLY=1
    fi
}

show_banner() {
    echo -e "${BLUE}"
    cat <<EOF
============================================================
 Debian/Ubuntu AI Agent stable installer ${AGENT_INSTALLER_VERSION}
 OpenClaw + Hermes Agent + common AI Agent runtime
============================================================
EOF
    echo -e "${NC}"
    echo "安装流程:"
    echo "  1. 先在纯净 Debian/Ubuntu 上安装所有依赖和软件"
    echo "  2. 完成权限、PATH、limits、Docker、浏览器自动化等稳定性优化"
    echo "  3. 最后再选择马上安装 OpenClaw/Hermes，或按手动步骤安装"
    echo ""
}

agent_main() {
    trap 'error_handler $LINENO' ERR
    parse_args "$@"
    require_root
    init_logging
    show_banner
    prepare_all_dependencies
    show_summary

    if [ "$INSTALL_TARGET" = "menu" ]; then
        show_final_menu
    else
        handle_target_install "$INSTALL_TARGET"
    fi

    log_success "脚本执行完成"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    agent_main "$@"
fi

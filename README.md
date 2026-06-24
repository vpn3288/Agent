# Agent 安装脚本

这是一个面向纯净 Debian/Ubuntu 服务器的 AI Agent 环境安装项目。它的核心目标是：先把 OpenClaw、Hermes Agent 以及其他常见 AI Agent 需要的软件、依赖、运行时和系统稳定性配置一次性准备好，然后再让你选择是否马上安装具体的 Agent。

适合场景：

- 刚安装好的 Debian 12 / Ubuntu 22.04 / Ubuntu 24.04 服务器
- 远程 VPS、独立服务器、DD 后的纯净系统
- 想安装 OpenClaw、Hermes Agent，或者先准备一个通用 AI Agent 运行环境

## 一键安装

推荐新手使用 `bootstrap.sh`。它会先安装 `curl` 和证书，然后下载主安装脚本。

```bash
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/bootstrap.sh -o bootstrap.sh
sudo bash bootstrap.sh
```

脚本会先安装所有依赖和系统优化，最后出现菜单：

```text
1) OpenClaw
2) Hermes Agent
3) OpenClaw + Hermes Agent
4) 只显示手动安装步骤
5) 其他 AI Agent 通用环境说明
0) 退出
```

如果你只想准备环境，不马上安装 Agent：

```bash
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/debian12_hermes_openclaw_perfect_install.sh -o agent-install.sh
sudo bash agent-install.sh --deps-only
```

## 直接安装指定 Agent

安装 OpenClaw 前会先准备完整依赖，最后询问是否马上安装 OpenClaw：

```bash
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/install_openclaw.sh -o install_openclaw.sh
sudo bash install_openclaw.sh
```

安装 Hermes Agent 前会先准备完整依赖，最后询问是否马上安装 Hermes：

```bash
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/install_hermes.sh -o install_hermes.sh
sudo bash install_hermes.sh
```

自动安装 OpenClaw + Hermes，不再手动确认：

```bash
curl -fsSL https://raw.githubusercontent.com/vpn3288/Agent/main/debian12_hermes_openclaw_perfect_install.sh -o agent-install.sh
sudo bash agent-install.sh --install all --yes
```

## 脚本安装了什么

主脚本会尽量在纯净 Debian/Ubuntu 上补齐下面这些内容。

基础系统工具：

- `sudo`
- `curl`
- `wget`
- `ca-certificates`
- `gnupg`
- `git`
- `git-lfs`
- `unzip`
- `zip`
- `tar`
- `xz-utils`
- `jq`
- `rsync`
- `vim`
- `nano`
- `htop`
- `screen`
- `tmux`
- `openssh-client`
- `openssh-server`

编译和开发依赖：

- `build-essential`
- `gcc`
- `g++`
- `make`
- `cmake`
- `autoconf`
- `automake`
- `libtool`
- `pkg-config`
- `libssl-dev`
- `libffi-dev`
- `libsqlite3-dev`
- `libxml2-dev`
- `libxmlsec1-dev`
- `zlib1g-dev`
- 其他常见 Python/Rust/原生扩展编译头文件

Python 环境：

- 系统 Python 3
- `pip`
- `venv`
- `setuptools`
- `wheel`
- `pipx`
- `uv`
- 使用 `uv` 预装 Python 3.11，方便 Hermes Agent 创建稳定虚拟环境

Node.js 环境：

- Node.js 24.x，默认使用 NodeSource 安装
- `npm`
- `pnpm`
- npm 全局安装目录配置

OpenClaw 相关：

- 检查 Node.js 是否满足 OpenClaw 要求
- 优先使用 `npm install -g openclaw@latest`
- npm 安装失败时回退到 OpenClaw 官方安装器
- 安装完成后提示 `openclaw onboard` 和 gateway 启动命令

Hermes Agent 相关：

- 优先使用 Hermes 官方安装器
- 自动跳过交互式 setup，避免安装过程中卡住
- 官方安装器失败时回退到源码安装
- 使用 `uv` 创建 Python 3.11 虚拟环境
- 尝试安装 `.[all]` 完整依赖
- 创建全局 `hermes` 命令

AI Agent 通用运行时：

- `sqlite3`
- `redis-tools`
- `ffmpeg`
- `imagemagick`
- `graphicsmagick`
- `pandoc`
- `ripgrep`
- `fd`
- `bat`
- `xclip`
- `xauth`
- `xvfb`
- `dbus-x11`
- Chromium 或系统可用浏览器包
- Playwright/浏览器自动化需要的 GTK、NSS、X11、字体等运行库

Docker 支持：

- 默认尝试安装发行版软件源里的 Docker
- 启用并启动 Docker 服务
- 如果使用 `sudo` 用户运行，会尝试把该用户加入 `docker` 组

稳定性和权限优化：

- 写入 `/etc/profile.d/ai-agent-env.sh`
- 配置 PATH，让 `/usr/local/bin`、`~/.local/bin`、`~/.cargo/bin` 可用
- 配置 `EDITOR` / `VISUAL`
- 配置 Git 默认用户信息和大文件/低速网络参数
- 配置 `nofile` 限制
- 配置 inotify watch 限制
- 配置 `net.core.somaxconn`
- 创建环境检查命令 `agent-env-doctor`

## 常用参数

```bash
sudo bash agent-install.sh --install openclaw
sudo bash agent-install.sh --install hermes
sudo bash agent-install.sh --install all
sudo bash agent-install.sh --deps-only
sudo bash agent-install.sh --manual
sudo bash agent-install.sh --install all --yes
```

参数说明：

- `--install openclaw`：准备依赖后处理 OpenClaw
- `--install hermes`：准备依赖后处理 Hermes Agent
- `--install all`：准备依赖后处理 OpenClaw 和 Hermes
- `--deps-only`：只安装依赖和系统优化，不安装 Agent
- `--manual`：只显示手动安装步骤
- `--yes`：自动确认安装，适合自动化脚本
- `--node-major 24`：安装 Node.js 24，默认值
- `--node-major 22`：安装 Node.js 22，适合需要 Node 22 的场景

## 环境变量

```bash
AGENT_APT_UPGRADE=1 sudo bash agent-install.sh
AGENT_INSTALL_DOCKER=0 sudo bash agent-install.sh
AGENT_INSTALL_BROWSER=0 sudo bash agent-install.sh
HERMES_DIR=/opt/hermes-agent sudo bash agent-install.sh --install hermes
```

说明：

- `AGENT_APT_UPGRADE=1`：安装前执行系统升级
- `AGENT_INSTALL_DOCKER=0`：跳过 Docker
- `AGENT_INSTALL_BROWSER=0`：跳过浏览器资源下载
- `HERMES_DIR=/path`：指定 Hermes Agent 仓库目录

## 安装后验证

安装完成后运行：

```bash
agent-env-doctor
```

检查 OpenClaw：

```bash
openclaw --version
openclaw onboard --install-daemon
openclaw gateway --port 18789 --verbose
```

检查 Hermes Agent：

```bash
hermes --version
hermes setup
hermes doctor
```

## 日志位置

主脚本日志默认写入：

```text
/var/log/agent-perfect-install.log
```

如果安装失败，先查看这个日志。

## 注意事项

- 请使用 `root` 或 `sudo` 运行。
- 建议在全新的 Debian/Ubuntu 系统上运行。
- 首次安装会下载大量 apt、npm、uv、Docker、浏览器相关依赖，耗时取决于服务器网络。
- 如果 Docker 组权限刚刚添加，通常需要重新登录 SSH 才能对当前用户生效。
- 如果网络访问 GitHub、NodeSource、npm 或官方安装器较慢，可能需要重复运行脚本；脚本会尽量跳过已安装内容。

## 文件说明

- `bootstrap.sh`：新手推荐入口，最小系统启动器
- `debian12_hermes_openclaw_perfect_install.sh`：主安装脚本
- `install_openclaw.sh`：OpenClaw 包装安装入口
- `install_hermes.sh`：Hermes Agent 包装安装入口
- `install_hermes_root.sh`：旧入口兼容脚本，现在复用统一主流程

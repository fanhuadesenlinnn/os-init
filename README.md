# OS Init

面向中国大陆网络环境的系统初始化工具。它保留 TUI 多选、搜索、安装/更新/卸载体验，并会根据当前 OS 自动显示可用模块：Linux 适配 Arch 系、Debian 系、RedHat 系；macOS 显示可通过 Homebrew 或通用二进制安装的终端/开发工具。

<p align="center">
  <img src="demo.gif" alt="OS Init TUI 演示" width="720" />
</p>

## 快速开始

下载发布包，下面是 Linux amd64 示例：

```bash
curl -sSL https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/os-init_linux_amd64.tar.gz | tar xz
./os-init
```

从源码构建：

```bash
git clone https://github.com/fanhuadesenlinnn/os-init.git
cd os-init
make build
./os-init
```

## 核心能力

- 单文件 TUI：Go 二进制内嵌脚本和配置，进入后直接选择模块执行。
- 三种模式：安装、更新、卸载。
- 系统识别：Linux 下识别 Debian/Ubuntu、Rocky/RHEL/Fedora、Arch/Manjaro；macOS 识别为 Darwin 系。
- 模块过滤：Linux 显示系统优化、Docker、Mihomo 等 Linux 专属模块；macOS 只显示适配 macOS 的 Shell、终端和开发工具模块。
- 中国大陆网络适配：GitHub 专用代理、下载重试、超时、离线包目录。
- 执行保护：单模块超时，按所选模块决定是否提前校验 sudo，macOS Homebrew 模块不会无故要求 sudo。
- TCP/UDP 优化：吸收 `tcp.vpsing.de` 的有效配置，加入 IPv4 优先、BBR/FQ、ECN、MTU 探测、RPS/RSS、MSS clamp。
- 二进制 Docker：安装 Docker Engine 静态二进制和 Docker Compose CLI 插件。
- Mihomo：按 ArchDevKit 风格安装代理核心、配置模板、systemd 服务和 MetaCubeXD 面板。
- ArchDevKit：在 Arch Linux 上显示独立菜单，完整嵌入 ArchDevKit 的 base、archlinuxcn、dns、runtime、desktop、doctor、config 等能力。
- Shell 接入：Go、starship、direnv、Yazi、Neovim、nvm/fnm 等会写入 os-init 管理块，不覆盖用户自己的 rc 配置。
- 中文界面：TUI、模块描述、执行状态和 README 面向中文使用场景。

## 当前模块

### 系统优化

| 模块 | 功能 |
| --- | --- |
| 内核 sysctl.d | 网络、内存、conntrack、BBR 等参数 |
| 内核 limits.d | 文件句柄和进程数限制 |
| I/O 调度器 | SSD/NVMe 使用 `none` |
| 自动调优 | 按内存动态调整 conntrack、TCP 缓冲区、file-max |
| IPv4 优先 | 修改 `gai.conf`，双栈解析时优先使用 IPv4 |
| 队列与 MSS | RPS/RSS 多核分发、网卡 ring buffer、TCP MSS clamp |

### 软件安装

| 分组 | 模块 |
| --- | --- |
| Shell 工具 | zsh、oh-my-zsh、starship、direnv、zsh 插件、nvm/fnm、Git 配置、byobu/tmux（Linux） |
| 终端工具 | ncdu、Yazi |
| macOS 开发应用 | Chrome、Codex、OrbStack、VS Code、iTerm2、Ghostty、Sublime Text、Neovide |
| macOS 代理网络 | Clash Verge Rev、Clash Party、Royal TSX、Seafile Client |
| macOS 效率/输入/媒体 | PixPin、Bob、Loop、Ice、Stats、MonitorControl、Mos、Karabiner、AlDente、Keka、IINA、Downie、Motrix、Spotify、Steam、腾讯视频等 |
| macOS AI/办公/通讯 | ChatGPT、Cherry Studio、SiYuan、微信、Telegram、腾讯会议、WPS Office、Bitwarden、CleanMyMac X、CC Switch |
| macOS 命令行 | bat、eza、ripgrep、fd、fzf、gh、jq、mise、nmap、nushell、tmux、uv、zoxide、ffmpeg、ImageMagick、yt-dlp 等 |
| 网络代理 | Mihomo |
| 开发工具 | Docker、Go、Neovim + LazyVim |

### ArchDevKit

该菜单仅在 Arch Linux 系统显示。ArchDevKit 作为独立子系统嵌入在 `modules/archdevkit/vendor`，保留自己的配置、状态和模块逻辑。

| 模块 | 功能 |
| --- | --- |
| 基础环境 | 基础工具、排障工具、现代 CLI、tmux、AUR helper |
| archlinuxcn 软件源 | archlinuxcn 源、keyring、mirrorlist |
| 系统 DNS | systemd-resolved、NetworkManager DNS 后端、国内 DNS 基线 |
| Git / Ops Toolkit | GitHub CLI、OpenSSH、ops-toolkit 命令入口 |
| Runtime / mise | Node/npm/Python/Go、mise、国内镜像环境 |
| Neovim / Docker / 字体 | ArchDevKit 原有开发环境模块 |
| Zsh / Proxy / Hyprland | Oh My Zsh、Powerlevel10k、Mihomo/sing-box、Hyprland 桌面 |
| dev / workstation | ArchDevKit 原有组合套餐 |
| status / doctor / config | ArchDevKit 原有状态、诊断和配置命令 |

ArchDevKit 使用自己的配置文件和状态目录：

```bash
~/.config/archdevkit/config.env
~/.local/state/archdevkit
```

注意：ArchDevKit 的 `shell` 和 `desktop` 模块会按原项目逻辑生成或覆盖部分用户配置，例如 `~/.zshrc`、Hyprland、Waybar、Rofi、Dunst、Yazi、GTK 等配置。需要更温和的 Shell 接入时，优先使用 os-init 自带 Shell 模块。

## 已移除模块

以下模块不再作为新方案的一部分：

| 模块 | 删除原因 |
| --- | --- |
| GNOME Optimize | Ubuntu/GNOME 桌面强相关 |
| Nautilus Optimize | Ubuntu/GNOME/Nautilus 强相关 |
| AppArmor Setup / Monitor | Debian/Ubuntu 偏向，RedHat 默认 SELinux，Slack 在大陆不稳定 |
| USB Monitor | Webhook 目标和文案需要另行设计 |
| Browsers & Apps | 桌面浏览器和 Signal 对服务器初始化价值低，国内网络不稳定 |
| PeaZip | 与当前服务器/终端初始化目标不匹配 |
| SSH 加固 | 远程连接风险较高，移出默认初始化能力 |

各模块会修改哪些系统配置，见 [MODULE_SYSTEM_CHANGES.md](MODULE_SYSTEM_CHANGES.md)。

## 配置

程序启动时会先检查用户配置文件。如果没有发现 `/etc/os-init/config.env` 或 `~/.config/os-init/config.env`，TUI 会提示是否创建默认配置文件；默认创建到：

```bash
~/.config/os-init/config.env
```

创建出来的配置文件带中文注释，说明 GitHub 代理、资源地址和离线参数的用途。

配置加载顺序：

1. `modules/config/defaults.env`
2. `/etc/os-init/config.env`
3. `~/.config/os-init/config.env`
4. 当前环境变量

常用变量：

```bash
export GITHUB_PROXY=https://gh-proxy.com/
export OS_INIT_OFFLINE=1
export OS_INIT_FILES_DIR=/opt/os-init/packages
export OS_INIT_SCRIPT_TIMEOUT=45m
```

Docker 和 Mihomo 也可以通过同一套配置调整版本、下载地址、镜像源等参数。

也可以提前复制示例配置再修改：

```bash
mkdir -p ~/.config/os-init
cp modules/config/config.env.example ~/.config/os-init/config.env
${EDITOR:-vi} ~/.config/os-init/config.env
```

如果不想每次启动显示配置提示页，可以设置：

```bash
OS_INIT_CONFIG_PROMPT=0
```

资源下载可以按两种方式覆盖：

- 设置 GitHub 代理：`GITHUB_PROXY` 只改写 GitHub、raw.githubusercontent.com、objects.githubusercontent.com 和 github-releases.githubusercontent.com。
- 设置具体资源地址：例如 `GO_DOWNLOAD_URL`、`DOCKER_TGZ_URL`、`DOCKER_COMPOSE_DOWNLOAD_URL`、`MIHOMO_DOWNLOAD_URL`、`NVIM_DOWNLOAD_URL`、`YAZI_DOWNLOAD_URL`、`HOMEBREW_INSTALL_URL`。
- 设置资源仓库地址：例如 `OH_MY_ZSH_REPO`、`LAZYVIM_STARTER_REPO`、`METACUBEXD_REPO`。
- 设置 Homebrew 下载和元数据地址：例如 `HOMEBREW_API_DOMAIN`、`HOMEBREW_BOTTLE_DOMAIN`、`HOMEBREW_ARTIFACT_DOMAIN`、`HOMEBREW_BREW_GIT_REMOTE`、`HOMEBREW_CORE_GIT_REMOTE`。
- 设置模块执行超时：`OS_INIT_SCRIPT_TIMEOUT=45m`，也可以用纯秒数；`0` 表示不限制。

Homebrew 镜像示例：

```bash
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
export HOMEBREW_PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
```

TUI 后台更新检查也会读取同一套配置；GitHub 版本检查会和安装脚本使用一致的 `GITHUB_PROXY`。Go 版本检查默认直连 `go.dev`，如需替换请配置 `GO_VERSION_URL`。

## TUI 操作

命令行参数：

```bash
os-init --version
os-init --help
```

| 按键 | 动作 |
| --- | --- |
| `↑/↓` 或 `j/k` | 移动 |
| `Space` | 选择/取消 |
| `Ctrl+A` | 全选/取消全选 |
| `/` | 过滤搜索 |
| `Enter` | 确认 |
| `Esc` | 返回或清空过滤 |
| `q` | 退出 |

状态徽标：

- `[已安装]`：已经安装，但没有版本信息。
- `[已安装 X.Y.Z]`：已经安装，并显示当前版本。
- `[可更新 X.Y.Z → A.B.C]`：检测到新版本。

## 构建

```bash
make build
make test
make archdevkit-test
make lint
make run
```

最终发布包由 GitHub Actions 在 tag 推送后构建并发布。

发布包名称：

- `os-init_linux_amd64.tar.gz`
- `os-init_linux_arm64.tar.gz`
- `os-init_darwin_amd64.tar.gz`
- `os-init_darwin_arm64.tar.gz`
- `checksums.txt`

## 安全约定

- 不直接覆盖用户已有 `~/.zshrc`。
- 只维护 `# >>> os-init <name> >>>` 到 `# <<< os-init <name> <<<` 之间的管理块。
- 只有选中会修改系统目录、systemd、内核参数或系统包管理器的模块时，才会提前校验 sudo；普通 Homebrew app/formula 不会被 os-init 包上 sudo。
- macOS GUI 应用只负责安装；OrbStack、Clash、Royal TSX、Seafile、Bitwarden 等私有配置仍由用户在应用内完成。
- Neovim 配置安装前会备份已有目录。
- Docker 卸载时保留 `/var/lib/docker` 数据。
- 系统配置优先写入 drop-in 文件，降低对发行版默认配置的破坏。

## License

MIT

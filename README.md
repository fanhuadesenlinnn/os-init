# OS Init

面向中国大陆网络环境的跨平台系统初始化工具。它保留 TUI 多选、搜索、安装/更新/卸载体验，并会根据当前 OS 自动显示可用模块：macOS 面向开发机和日常电脑；通用 Linux 面向服务器和开发环境；Arch Linux 通过 ArchDevKit 面向最小化安装后的完整开发环境初始化。

<p align="center">
  <img src="demo.gif" alt="OS Init TUI 演示" width="720" />
</p>

## 快速开始

下载发布包，下面是 Linux amd64 示例：

```bash
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/os-init_linux_amd64.tar.gz
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/checksums.txt
grep 'os-init_linux_amd64.tar.gz$' checksums.txt | sha256sum -c -
tar xzf os-init_linux_amd64.tar.gz
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
- 中国大陆网络适配：GitHub 专用代理、镜像源、资源下载地址覆盖、下载重试和超时。
- 执行保护：单模块超时，按所选模块决定是否提前校验 sudo，macOS Homebrew 模块不会无故要求 sudo。
- TCP/UDP 优化：吸收 `tcp.vpsing.de` 的有效配置，加入 IPv4 优先、BBR/FQ、ECN、MTU 探测、RPS/RSS、MSS clamp。
- 分平台安装策略：macOS 优先 Homebrew，Arch Linux 优先 pacman/paru/yay，其它 Linux 尽量使用官方二进制。
- Docker：Arch Linux 使用 pacman/AUR 安装 Docker 组件；Debian/RedHat 系使用 Docker 静态二进制和 Docker Compose CLI 插件。
- Mihomo：按 ArchDevKit 风格安装代理核心、配置模板、systemd 服务和 MetaCubeXD 面板。
- ArchDevKit：在 Arch Linux 上显示独立菜单，完整嵌入 ArchDevKit 的 base、archlinuxcn、dns、runtime、desktop、doctor、config 等能力。
- Shell 接入：Go、starship、direnv、Yazi、Neovim、nvm/fnm 等会写入 os-init 管理块，不覆盖用户自己的 rc 配置。
- 终端体验：Starship 自动选择本地图形终端 `rich`、SSH `simple`、TTY/救援环境 `plain` 三种样式；可配置 eza/bat 友好 alias。
- 中英双语界面：启动时可选择中文或 English；菜单、确认信息、执行状态和结果页会保持所选语言一致。

### English interface

Choose `English` on startup, or set `OS_INIT_LANG=en_US` before launching. The English flow covers startup configuration, module search and selection, action selection, privilege and affected-path review, live execution status, and results. Original installer diagnostics remain available in the run log when a bundled script does not provide a native English message.

## 项目定义

长期产品语言见 [CONTEXT.md](CONTEXT.md)。关键架构决策记录在 [docs/adr](docs/adr)：

- macOS、通用 Linux、ArchDevKit 是三条接管深度不同的初始化主线。
- ArchDevKit 是 Arch Linux 最小化安装后的独立大模块，不和普通 os-init 模块统一批次执行。
- 主界面坚持模块平铺选择，但执行顺序由软件规划。
- 所有平台使用统一配置文件，首次创建时生成通用段和当前系统相关段。

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
| 终端体验 | 终端样式：本地 rich、SSH simple、TTY plain 自动切换 |
| 终端工具 | ncdu、Yazi |
| macOS 开发应用 | Chrome、Codex、OrbStack、VS Code、iTerm2、Ghostty、Sublime Text、Neovide |
| macOS 代理网络 | Clash Party、Royal TSX、Seafile Client |
| macOS 效率/输入/媒体 | PixPin、Bob、Loop、Ice、Stats、MonitorControl、Mos、Input Source Pro、Squirrel、Karabiner、AlDente、Keka、IINA、Downie、Motrix Next、Spotify、Steam、腾讯视频等 |
| macOS AI/办公/通讯 | ChatGPT、LM Studio、Cherry Studio、SiYuan、微信、Telegram、腾讯会议、WPS Office、Bitwarden、CleanMyMac X、CC Switch |
| macOS 命令行 | bat、eza、ripgrep、fd、fzf、gh、jq、mise、nmap、nushell、tmux、uv、zoxide、ffmpeg、ImageMagick、yt-dlp 等 |
| 网络代理 | Mihomo |
| 开发工具 | Docker、Go、Neovim + LazyVim |

安装来源遵循平台生态：macOS 模块会自动安装并使用 Homebrew；Arch Linux 普通模块优先使用 pacman，缺包时自动准备 paru/yay 后走 AUR；Debian/RedHat 系的版本敏感工具优先使用官方二进制或可配置下载地址。

### ArchDevKit

该菜单仅在 Arch Linux 系统显示。ArchDevKit 作为独立子系统嵌入在 `modules/archdevkit/vendor`，保留自己的配置、状态和模块逻辑。

ArchDevKit 安装目标通过“原版交互菜单”选择。进入后按 ArchDevKit 原版顺序选择安装目标、Proxy、GPU、Hyprland、输入法和浏览器等选项；os-init 会把这些选择写成临时覆盖配置，再交给 ArchDevKit 原始安装入口执行。状态检查、诊断、配置初始化、配置校验和状态重置保留为独立动作入口。

| 向导目标/动作 | 功能 |
| --- | --- |
| 基础环境 | 基础工具、排障工具、现代 CLI、tmux、AUR helper |
| archlinuxcn 软件源 | archlinuxcn 源、keyring、mirrorlist |
| 系统 DNS | systemd-resolved、NetworkManager DNS 后端、国内 DNS 基线 |
| Git / Ops Toolkit | GitHub CLI、OpenSSH、ops-toolkit 命令入口 |
| Runtime / mise | Node/npm/Python/Go、mise、国内镜像环境 |
| Neovim / Docker / 字体 | ArchDevKit 原有开发环境模块 |
| Zsh / Proxy / Hyprland | Oh My Zsh、Starship 终端样式、Mihomo/sing-box、Hyprland 桌面 |
| dev / workstation | ArchDevKit 原有组合套餐 |
| status / doctor / config | ArchDevKit 原有状态、诊断和配置命令 |

ArchDevKit 使用自己的配置文件和状态目录：

```bash
~/.config/archdevkit/config.env
~/.local/state/archdevkit
```

注意：ArchDevKit 的 `shell` 和 `desktop` 模块会生成或覆盖部分用户配置，例如 `~/.zshrc`、Hyprland、Waybar、Rofi、Dunst、Yazi、GTK 等配置。`shell` 默认使用 Starship 终端样式，`--p10k` 或 `SHELL_PROMPT_ENGINE=powerlevel10k` 可切回 Powerlevel10k。需要更温和的 Shell 接入时，优先使用 os-init 自带 Shell 和终端样式模块。

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

创建出来的配置文件带中文注释，说明 GitHub 代理、终端样式、镜像源和资源下载地址的用途。

配置加载顺序：

1. `modules/config/defaults.env`
2. `/etc/os-init/config.env`
3. `~/.config/os-init/config.env`
4. 当前环境变量

常用变量：

```bash
export GITHUB_PROXY=https://gh-proxy.com/
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
- 经 `GITHUB_PROXY` 获取将被执行或安装的内容时，默认要求配置对应的 `*_SHA256`；未提供校验值会拒绝执行。`OS_INIT_ALLOW_UNVERIFIED_PROXY=1` 仅用于明确接受旧版风险的兼容场景。
- 设置具体资源地址：例如 `GO_DOWNLOAD_URL`、`DOCKER_TGZ_URL`、`DOCKER_COMPOSE_DOWNLOAD_URL`、`MIHOMO_DOWNLOAD_URL`、`NVIM_DOWNLOAD_URL`、`YAZI_DOWNLOAD_URL`、`HOMEBREW_INSTALL_URL`。这些主要用于非 Arch Linux 的二进制安装路径；macOS/Arch 默认优先包管理器。
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
- OS Init 会在 `/var/lib/os-init/ownership` 和 `~/.local/state/os-init` 记录自己接管的资源；卸载只删除有所有权记录的内容，并恢复首次接管前的备份。
- Neovim、Yazi 等用户配置默认保留；只有显式设置 `PURGE_CONFIG=1` 或 `PURGE_DATA=1` 才会删除对应数据目录。
- 通过 GitHub 代理下载的可执行脚本和二进制必须通过预期 SHA-256 校验；Git 克隆的可执行配置默认不允许走无法验证的代理。
- 系统配置优先写入 drop-in 文件，降低对发行版默认配置的破坏。

## License

MIT

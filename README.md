# OS Init

面向中国大陆网络环境的 macOS / Linux 系统初始化工具。启动后通过 TUI 选择需要的软件或系统配置，并执行安装、更新或卸载。界面会根据当前操作系统只显示可用模块。

<p align="center">
  <img src="demo.gif" alt="OS Init TUI 演示" width="720" />
</p>

## 支持平台

| 平台 | 支持范围 |
| --- | --- |
| macOS | Apple Silicon、Intel；软件优先通过 Homebrew 安装 |
| Arch Linux / Manjaro | 独立 Arch 能力、开发环境与完整工作站组合；支持 root 和普通用户 |
| Debian / Ubuntu | 系统优化、Shell、终端工具、Docker、Mihomo、开发工具 |
| Fedora / Rocky Linux / RHEL | 系统优化、Shell、终端工具、Docker、Mihomo、开发工具 |
| WSL1 / WSL2 | 复用发行版包管理器；WSL2 可启用 systemd 和发行版内原生 Docker Engine，不接管 Windows Docker Desktop |
| OrbStack Arch Linux ARM | 识别 OrbStack 托管边界；提供 ARM 开发环境，不接管宿主机 DNS、内核或图形桌面 |

WSL 会作为 Linux 发行版的运行环境识别：Ubuntu WSL 继续使用 Debian 系逻辑，Arch WSL 继续使用 pacman。WSL 中不会显示内核调优、物理网卡优化、DNS 接管、Mihomo 服务、Hyprland/SDDM 等不合适的能力。`WSL 开发环境`只组合 Shell、tmux、Git、终端工具、mise 运行时和 Neovim。

WSL2 尚未启用 systemd 时，先安装 `WSL systemd`，然后从 PowerShell 执行 `wsl.exe --shutdown`。重新进入发行版后可以安装 `Docker（WSL 原生 Engine）`；Docker daemon、containerd、Compose、配置和数据全部由当前 WSL Linux 发行版管理。必须关闭 Docker Desktop 对当前发行版的 WSL Integration，OS Init 检测到该集成时会拒绝安装，避免连接到错误的 Docker daemon。

OrbStack Linux 机器会独立识别为 `environment=orbstack`。`OrbStack Arch 开发环境`组合 Arch 基础、archlinuxcn/AUR、Git、mise 用户运行时、Neovim、Docker、字体和 Zsh；不会启用被 OrbStack 屏蔽的 `systemd-resolved`，也不会替换指向 `/opt/orbstack-guest/etc/resolv.conf` 的 DNS 配置。Arch Linux ARM 在中国大陆区域会把台湾官方 ARM 镜像放在原有 GeoIP 镜像之前，并在下载波动时复用 pacman 缓存重试。

## 快速开始

从 [最新版本](https://github.com/fanhuadesenlinnn/os-init/releases/latest) 下载与系统匹配的发布包：

| 系统 | 文件 |
| --- | --- |
| Linux x86-64 | `os-init_linux_amd64.tar.gz` |
| Linux ARM64 | `os-init_linux_arm64.tar.gz` |
| macOS Intel | `os-init_darwin_amd64.tar.gz` |
| macOS Apple Silicon | `os-init_darwin_arm64.tar.gz` |

Linux x86-64 示例：

```bash
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/os-init_linux_amd64.tar.gz
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/checksums.txt
grep 'os-init_linux_amd64.tar.gz$' checksums.txt | sha256sum -c -
tar xzf os-init_linux_amd64.tar.gz
./os-init
```

macOS Apple Silicon 示例：

```bash
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/os-init_darwin_arm64.tar.gz
curl -fLO https://github.com/fanhuadesenlinnn/os-init/releases/latest/download/checksums.txt
grep 'os-init_darwin_arm64.tar.gz$' checksums.txt | shasum -a 256 -c
tar xzf os-init_darwin_arm64.tar.gz
./os-init
```

查看版本或帮助：

```bash
./os-init --version
./os-init --system-info
./os-init --help
```

## 非交互与静默安装

自动化、远程初始化和 CI 不需要操作 TUI。模块 ID、依赖规划、provider、超时、日志与安装后验证都与交互界面共用：

```bash
# 查看当前系统可用的稳定模块 ID
./os-init module list --format ids

# 只查看依赖展开后的执行计划
./os-init module plan terminal-ncdu docker

# 静默安装并验证；需要提权时必须已有非交互 sudo 权限
./os-init module install --yes --quiet terminal-ncdu

# 逐模块执行安装、重复安装、更新和卸载生命周期
./os-init module test --yes --quiet \
  --report reports/ncdu.json \
  --junit reports/ncdu.xml \
  terminal-ncdu

# 当前平台全部模块；失败后继续并生成完整报告
./os-init module test --all --yes --quiet --continue-on-error \
  --report reports/all.json \
  --junit reports/all.xml
```

会修改系统的非交互命令必须显式提供 `--yes`。命令不会读取或存储 sudo 密码；普通用户运行系统模块前应执行 `sudo -v`，CI 应使用 `sudo -n` 可通过的临时环境。`--quiet` 只关闭实时输出，完整日志仍写入 `logs/`。

`module list --format json` 同时输出每个模块的 GitHub 自动化范围：`container`、`hosted`、`manual`，以及 `full`、`install-only` 或 `plan-only` 生命周期。网络队列、Arch DNS 和图形桌面等可能中断 Runner 或需要图形硬件的模块不会被误报为完整自动化通过。

完整的自动化测试范围与仍需专用虚拟机/硬件验证的项目见
[测试矩阵](docs/TEST_MATRIX.md)。

## TUI 操作

启动时可以选择中文或 English，也可以预先设置 `OS_INIT_LANG=en_US` 使用英文界面。

| 按键 | 动作 |
| --- | --- |
| `↑/↓` 或 `j/k` | 移动光标 |
| `Space` | 选择或取消模块 |
| `Ctrl+A` | 全选或取消全选 |
| `/` | 搜索模块 |
| `Enter` | 确认 |
| `Esc` | 返回或清空搜索 |
| `q` | 退出 |

选择模块后，可以执行安装、更新或卸载。确认页会显示权限需求、受影响路径和需要手动完成的后续操作。执行结果及日志路径会显示在结果页。
模块只显示自身支持的操作；组合预设只展开依赖，不会执行额外脚本；诊断和状态操作不能与安装模块混在同一批次。

## 当前模块

### 通用工具

| 分组 | 可选模块 |
| --- | --- |
| Shell | Zsh + Oh My Zsh（含 Powerlevel10k、zsh-autosuggestions、zsh-syntax-highlighting）、direnv、Git 配置 |
| 终端 | 自动终端样式、ncdu、Yazi；Linux 可选 tmux |
| 开发 | Go、Neovim + Neovide + config-yuan |
| Linux 服务 | Docker、Mihomo |

### Linux 系统优化

| 模块 | 用途 |
| --- | --- |
| 内核 sysctl.d | 网络、内存、conntrack、BBR/FQ 参数 |
| 内核 limits.d | 文件句柄和进程数限制 |
| I/O 调度器 | SSD/NVMe 调度策略 |
| 自动调优 | 根据内存调整 conntrack、TCP 缓冲区和 file-max |
| IPv4 优先 | 双栈解析时优先使用 IPv4 |
| 队列与 MSS | RPS/RSS、网卡 ring buffer、TCP MSS clamp |

### macOS 应用

| 分组 | 可选软件 |
| --- | --- |
| 开发应用 | Google Chrome、Codex、OrbStack、Visual Studio Code、iTerm2、Ghostty、Sublime Text |
| 代理与远程 | Clash Party、Royal TSX、Seafile Client |
| 效率工具 | PixPin、Bob、Loop、Ice、Stats、MonitorControl、Mos、Input Source Pro、MenubarX |
| 输入与系统 | Karabiner-Elements、Squirrel、AlDente、Keka |
| 媒体与下载 | IINA、Downie 4、Motrix Next、Spotify、Steam、腾讯视频 |
| AI 与笔记 | ChatGPT、LM Studio、Cherry Studio、SiYuan |
| 通讯与办公 | 微信、Telegram、腾讯会议、WPS Office、Bitwarden、CleanMyMac X、CC Switch |
| 字体 | Hack Nerd Font、JetBrains Mono Nerd Font、Maple Mono NF |

OrbStack、Clash Party、Royal TSX、Seafile Client、Bitwarden 等软件安装完成后，仍需在应用内完成首次初始化、登录或配置导入。Karabiner-Elements 会自动部署 Caps Lock/Control 互换、左 Shift 单击切换输入法且长按保留 Shift 的配置；首次打开时仍需批准 macOS 输入监控和系统扩展权限。

### macOS 命令行工具

| 类型 | 可选软件 |
| --- | --- |
| 现代 CLI | bat、eza、ripgrep、fd、fzf、jq、zoxide、tmux、Nushell |
| 开发与格式化 | GitHub CLI、mise、uv、ShellCheck、StyLua、tree-sitter CLI |
| 网络与诊断 | htop、iftop、nload、nmap、BIND、rsync、wget |
| 媒体与数据 | FFmpeg、ImageMagick、gallery-dl、yt-dlp |
| 其他 | herdr、llmfit |

开发运行时统一安装到目标用户的 mise 数据目录：Go 1.26、Python 3.13 和 Node.js 24。系统自带 Python 保留不动，也不再安装 `/usr/local/go` 或系统包 Go。

仓库自身通过 `go.mod` 固定构建所需的 Go 1.26.1；用户全局配置保留 `1.26` 系列，其他项目可通过各自受信任的 `mise.toml` 固定精确版本。

选择 mise Go 或 Python 时会自动补齐原生编译器、头文件以及 OpenSSL、zlib、libffi 等系统开发库；这些只属于构建基础设施，不提供系统级 Go/Python。

所有系统共享同一组 `mise`、`mise-go`、`mise-python`、`mise-node` 能力。macOS 使用 Homebrew 安装 mise 本体；Arch 在当前架构仓库提供 mise 时使用 pacman，否则自动回退到官方用户目录二进制；其他 Linux 使用用户目录二进制。普通用户写入自己的 HOME，root 模式写入 `/root`。

### Arch Linux 能力与组合

Arch Linux 的全部能力都位于普通模块菜单中，可以单独选择，也可以通过组合预设一次安装。

| 模块或组合 | 用途 |
| --- | --- |
| Arch 基础环境 / AUR Helper | 基础工具、排障工具、现代 CLI、tmux；root 和普通用户均优先从 archlinuxcn 安装 paru/yay |
| archlinuxcn / Arch DNS | 软件源、keyring、mirrorlist、systemd-resolved 和 NetworkManager |
| Arch Git / Ops Toolkit | Git、GitHub CLI、OpenSSH 和运维工具入口 |
| Arch 字体 / Arch Mihomo | 中文字体、Emoji、Nerd Font、Monaco；Mihomo 完整配置预检、systemd 服务和 MetaCubeXD |
| Arch Hyprland 桌面 | Hyprland、SDDM、Fcitx5/Rime、浏览器、hyprdots、GPU 与虚拟机适配 |
| Arch 开发环境 | Arch 基础 + AUR Helper + archlinuxcn + DNS + Git + Ops Toolkit + mise + Neovim + Docker + 字体 + Zsh + Arch Mihomo |
| Arch 完整工作站 | Arch 开发环境 + Arch Hyprland 桌面 |
| OrbStack Arch 开发环境 | ARM 基础、可靠软件源、mise、Neovim、Docker、字体与 Zsh；保留 OrbStack 管理的 DNS 和内核 |
| Arch 状态详情 / 系统诊断 | 状态、配置指纹、网络、systemd、桌面与修复建议 |

Arch Hyprland 桌面默认安装 Fcitx5 + Rime，安全合并公共配置并保留用户词库、同步状态和私人短语；配置更新后会尝试通知当前 Fcitx5 会话重新部署。Linux 默认使用 Ctrl+Space 切换输入法，不自动安装全局键盘拦截器来接管单击 Shift。

所有能力共用 OS Init 配置，Arch 专用执行状态位于：

```text
~/.config/os-init/config.env
~/.local/state/os-init/arch
```

root 模式不会运行 `makepkg`，但会在配置 archlinuxcn 后直接用 pacman 安装预编译的 paru/yay。其他系统操作直接以 root 执行，用户配置写入 `/root`。普通用户运行时，系统操作通过 sudo，用户配置保持普通用户所有权；仅普通用户允许在软件源缺包时回退到 AUR 构建。

## 配置

首次启动时可以创建用户配置文件：

```text
~/.config/os-init/config.env
```

也可以从源码仓库复制完整示例：

```bash
mkdir -p ~/.config/os-init
cp modules/config/config.env.example ~/.config/os-init/config.env
${EDITOR:-vi} ~/.config/os-init/config.env
```

常用配置：

```bash
# GitHub 下载代理
GITHUB_PROXY=https://gh-proxy.com/

# 单个模块最长执行时间；0 表示不限制
OS_INIT_SCRIPT_TIMEOUT=45m

# 关闭启动时的配置提示
OS_INIT_CONFIG_PROMPT=0

# Arch pacman 网络失败重试；Arch Linux ARM 区域镜像用逗号分隔
PACMAN_RETRY_ATTEMPTS=3
ARCHLINUXARM_MIRRORS='http://tw.mirror.archlinuxarm.org/$arch/$repo,http://tw2.mirror.archlinuxarm.org/$arch/$repo'
```

配置文件中还可以调整 Homebrew 镜像、运行时版本与镜像、Docker、Mihomo，以及各类下载地址。当前环境变量的优先级高于配置文件。

## 日志与排障

- 每个执行任务都会在 `logs/` 下生成日志。
- macOS 软件逐个执行，成功、失败、耗时和日志互不影响。
- Shell 配置修改后，打开新终端或执行 `exec zsh` 使其生效。
- Docker 用户组变化通常需要重新登录。
- Arch Linux 可以从普通模块菜单运行“Arch 状态详情”和“Arch 系统诊断”。

## 数据与权限

- 普通 Homebrew formula 和 cask 不使用 sudo。
- 修改系统目录、systemd、内核参数或 Linux 系统包时，会在确认后请求 sudo。
- Linux 可以直接以 root 运行；此时 root 是目标用户，用户配置写入 `/root`，且不依赖 sudo 软件包。
- Arch root 与普通用户看到相同能力；root 可用 pacman 安装 archlinuxcn 预编译包，但不运行 AUR 构建。
- OS Init 写入 Shell 配置时使用带名称的管理块，卸载时只移除对应管理块。
- 用户配置和应用数据默认保留；只有明确启用相应的清理参数时才删除。
- Docker 数据目录默认保留。
- Neovim 配置安装前会备份已有目录。
- 通过代理下载可执行内容时会执行项目配置的完整性校验策略。

各模块可能修改的路径和卸载行为见 [MODULE_SYSTEM_CHANGES.md](MODULE_SYSTEM_CHANGES.md)。

## 从源码构建

需要 Go 环境：

```bash
git clone https://github.com/fanhuadesenlinnn/os-init.git
cd os-init
make build
make test
./os-init
```

## License

MIT

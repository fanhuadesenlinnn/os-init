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
./os-init --help
```

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

## 当前模块

### 通用工具

| 分组 | 可选模块 |
| --- | --- |
| Shell | Zsh + Oh My Zsh、Starship、direnv、zsh-autosuggestions、zsh-syntax-highlighting、Git 配置 |
| 终端 | 自动终端样式、ncdu、Yazi；Linux 可选 byobu + tmux |
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

OrbStack、Clash Party、Royal TSX、Seafile Client、Bitwarden 等软件安装完成后，仍需在应用内完成首次初始化、登录或配置导入。

### macOS 命令行工具

| 类型 | 可选软件 |
| --- | --- |
| 现代 CLI | bat、eza、ripgrep、fd、fzf、jq、zoxide、tmux、Nushell |
| 开发与格式化 | GitHub CLI、mise、uv、ShellCheck、StyLua、tree-sitter CLI |
| 网络与诊断 | htop、iftop、nload、nmap、BIND、rsync、wget |
| 媒体与数据 | FFmpeg、ImageMagick、gallery-dl、yt-dlp |
| 其他 | herdr、llmfit |

mise 模块同时安装并管理 Node.js 24、Python 3.13 和 Go 1.24。

在 Arch Linux 上，root 和普通用户使用同一个 mise 模块。普通用户只在 pacman 阶段通过 sudo 提权，运行时与 Shell 配置写入自己的 HOME；root 模式写入 `/root`。

### Arch Linux 能力与组合

Arch Linux 的全部能力都位于普通模块菜单中，可以单独选择，也可以通过组合预设一次安装。

| 模块或组合 | 用途 |
| --- | --- |
| Arch 基础环境 / AUR Helper | 基础工具、排障工具、现代 CLI、tmux；root 和普通用户均优先从 archlinuxcn 安装 paru/yay |
| archlinuxcn / Arch DNS | 软件源、keyring、mirrorlist、systemd-resolved 和 NetworkManager |
| Arch Git / Ops Toolkit | Git、GitHub CLI、OpenSSH 和运维工具入口 |
| Arch 字体 / Arch Mihomo | 中文字体、Emoji、Nerd Font、Monaco；Mihomo 完整配置预检、systemd 服务和 MetaCubeXD |
| Arch Hyprland 桌面 | Hyprland、SDDM、Fcitx5/Rime、浏览器、hyprdots、GPU 与虚拟机适配 |
| Arch 开发环境 | Arch 基础 + AUR Helper + archlinuxcn + DNS + Git + Ops Toolkit + mise + Neovim + Docker + 字体 + Zsh + Starship + Shell 插件 + 终端样式 + Arch Mihomo |
| Arch 完整工作站 | Arch 开发环境 + Arch Hyprland 桌面 |
| Arch 状态详情 / 系统诊断 | 状态、配置指纹、网络、systemd、桌面与修复建议 |

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

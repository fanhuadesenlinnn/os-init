# 模块系统配置变更说明

本文档说明 os-init 各模块会修改哪些系统配置、用户配置和运行时参数。当前项目会按 OS 自动过滤模块：Linux 目标发行版为 Arch 系、Debian 系、RedHat 系；macOS 只显示适配 Homebrew 或通用二进制安装的 Shell、终端和开发工具模块。SSH 加固模块已移除。

## 执行、权限和超时

- Go 控制面统一负责平台过滤、依赖展开、生命周期校验、执行顺序、日志和汇总；Shell 模块统一通过 provider 协议接收 script、operation 和 component。
- 模块、组合预设和一次性操作具有独立语义。组合预设不进入执行队列，不支持的更新/卸载操作会在执行前阻止。
- 安装状态使用可组合的命令、路径、文件内容、Homebrew、systemd、用户组和 Shell 管理块检查。
- TUI 会根据选中的模块判断是否需要系统权限；普通 macOS Homebrew formula/cask 模块不会提前触发 `sudo -v`。
- Linux 系统优化、Docker、Mihomo、写入 `/usr/local`、`/opt`、`/etc` 或 systemd 的模块会提前校验 sudo，避免脚本中途隐藏式等待密码。
- 脚本内部使用非交互式 sudo；如果 sudo 缓存失效，会失败并提示，而不是卡在不可见的密码输入处。
- 单个脚本执行默认最多运行 `45m`，可通过 `OS_INIT_SCRIPT_TIMEOUT` 调整；设置为 `0` 可关闭该限制。
- Homebrew 命令统一读取 `HOMEBREW_API_DOMAIN`、`HOMEBREW_BOTTLE_DOMAIN`、`HOMEBREW_BREW_GIT_REMOTE`、`HOMEBREW_CORE_GIT_REMOTE`、`HOMEBREW_PIP_INDEX_URL` 等环境变量。os-init 不会执行 `sudo brew`。
- 系统资源所有权和首次接管前的备份记录在 `/var/lib/os-init`，用户资源记录在 `~/.local/state/os-init`；没有所有权记录的路径和软件包在卸载时默认保留。
- 经 `GITHUB_PROXY` 下载的可执行内容要求对应的 SHA-256；无法校验的 Git 代理克隆默认拒绝。

## 系统优化

### 内核 sysctl.d

- 写入 `/etc/sysctl.d/99-os-init.conf`，来源文件为 `modules/kernel/sysctl.conf`。
- 执行 `sysctl --system` 让配置尽量立即生效。
- 主要调整：
  - `net.core.default_qdisc=fq`
  - `net.ipv4.tcp_congestion_control=bbr`
  - `net.core.somaxconn=65535`
  - `net.core.netdev_max_backlog=65535`
  - `net.ipv4.tcp_max_syn_backlog=16384`
  - `net.ipv4.ip_local_port_range=1024 65535`
  - `net.ipv4.tcp_notsent_lowat=16384`
  - `net.ipv4.tcp_mtu_probing=1`
  - `net.ipv4.tcp_ecn=1`
  - `net.ipv4.udp_rmem_min=16384`
  - `net.ipv4.udp_wmem_min=16384`
  - `net.ipv4.tcp_tw_reuse=1`
  - `net.ipv4.tcp_fin_timeout=15`
  - `net.ipv6.conf.all.disable_ipv6=1`
  - `net.ipv6.conf.default.disable_ipv6=1`
  - `net.ipv6.conf.lo.disable_ipv6=1`
  - conntrack、TIME_WAIT、keepalive、内存、inotify 等基础参数。
- 这部分吸收了 [tcp.vpsing.de](https://tcp.vpsing.de/) 中 BBR/FQ、ECN、MTU 探测、UDP 缓冲和跨境连接稳定性相关配置。
- 卸载时删除 `/etc/sysctl.d/99-os-init.conf`，再次执行 `sysctl --system`。

### 内核 limits.d

- 写入 `/etc/security/limits.d/99-os-init.conf`。
- 写入：
  - `nofile=1048576`
  - `nproc=65535`
  - `stack=131072`
- 在存在的 PAM 文件中追加 `session required pam_limits.so`：
  - `/etc/pam.d/common-session`
  - `/etc/pam.d/common-session-noninteractive`
  - `/etc/pam.d/system-auth`
  - `/etc/pam.d/password-auth`
  - `/etc/pam.d/system-login`
- 写入 systemd 默认限制：
  - `/etc/systemd/system.conf.d/99-os-init.conf`
  - `/etc/systemd/user.conf.d/99-os-init.conf`
- 执行 `systemctl daemon-reexec`。
- 卸载时删除上述 os-init drop-in 文件，并只删除带 `# os-init -- enable pam_limits` 标记的 PAM 追加行。

### I/O 调度器

- 写入 `/etc/udev/rules.d/60-scheduler.rules`。
- 对 `sd*`、`sr*`、`nvme*`、`mmcblk*` 设备设置 `queue/scheduler=none`。
- 执行 `udevadm control --reload` 和 `udevadm trigger`。
- 卸载时删除该 udev 规则。

### 自动调优

- 安装 `/usr/local/sbin/autotune.sh`。
- 安装并启用 `/etc/systemd/system/autotune.service`。
- 开机时按内存动态设置：
  - `net.netfilter.nf_conntrack_max`
  - `net.ipv4.tcp_max_tw_buckets`
  - `fs.file-max`
  - `net.core.rmem_max`
  - `net.core.wmem_max`
  - `net.ipv4.tcp_rmem`
  - `net.ipv4.tcp_wmem`
- 网络缓冲区目标值按总内存 5% 计算，最低 16 MiB。
- 如果内核暴露 `net.ipv4.tcp_congestion_control_version`，会尝试设置为 `3`；旧内核没有该参数时跳过。
- 卸载时停止并禁用 `autotune.service`，删除 service 和脚本。

### IPv4 优先

- 修改 `/etc/gai.conf`。
- 追加带标记的配置：
  - `# os-init -- prefer IPv4 addresses when both A and AAAA exist`
  - `precedence ::ffff:0:0/96  100`
- 作用是双栈域名同时返回 IPv4/IPv6 时优先走 IPv4，减少部分网络环境下 IPv6 绕路或握手慢的问题。
- 卸载时只删除 os-init 标记及其下一行，不还原用户自己的其他 `gai.conf` 内容。

### 队列与 MSS

- 安装 `/usr/local/sbin/os-init-network-tune.sh`。
- 安装并启用 `/etc/systemd/system/os-init-network-tune.service`。
- 启动时执行一次，开机后也会再次执行。
- 主要动作：
  - 遍历 `/sys/class/net` 下非虚拟/非隧道接口。
  - 写入 `/sys/class/net/<iface>/queues/rx-*/rps_cpus`，把收包软中断分散到多核心。
  - 写入 `/sys/class/net/<iface>/queues/rx-*/rps_flow_cnt=4096`。
  - 设置 `net.core.rps_sock_flow_entries=32768`。
  - 如果系统存在 `ethtool`，尝试把网卡 RX/TX ring buffer 调到硬件上限。
  - 如果系统存在 `iptables`，添加 mangle 表规则：
    - `POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu`
- 首次应用前把 RPS、flow count、ring buffer、sysctl 和已有 MSS 规则快照保存到 `/var/lib/os-init/network-tune.state`。
- 卸载时停止并禁用 service，删除脚本和 service，并恢复安装前快照；旧版本没有快照时保留当前运行时设置，避免用全零配置覆盖用户设置。

## 软件安装

### Arch Linux 通用能力

Arch Linux 不再运行独立控制子系统。能力直接注册为普通 OS Init 模块，并可与其他模块放在同一个执行计划中；Arch 目录只保留领域实现、诊断和配置指纹状态：

- `Arch 基础环境`：通过 pacman 安装基础、排障和现代 CLI 工具，并写入 tmux 配置。
- `AUR Helper`：root 和普通用户均优先从 archlinuxcn 用 pacman 安装 paru/yay；仅普通用户可回退到 makepkg。
- `archlinuxcn`：备份和修改 `/etc/pacman.conf`，安装 keyring 和可选 mirrorlist。
- `Arch 系统 DNS`：写入 `/etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf` 和 NetworkManager drop-in，可链接 `/etc/resolv.conf`。
- `Arch Git / GitHub CLI`：安装 git、gh、OpenSSH，并写入目标用户 Git 配置。
- `Ops Toolkit`：克隆到 `~/.local/share/ops-toolkit` 并在 `~/.local/bin` 创建命令入口。
- `Arch 字体环境`：安装中文、Emoji、Nerd Font、Monaco，并调整目标用户 fontconfig/GTK 配置。
- `Arch Mihomo + MetaCubeXD`：从 pacman/archlinuxcn 安装，写入 `/etc/mihomo`、在 `/var/lib/mihomo` 按发行版 systemd unit 运行方式预检配置，并部署 MetaCubeXD。
- `Arch Hyprland 桌面`：保留 SDDM、Fcitx5/Rime、浏览器、hyprdots、GPU 和虚拟机适配。
- `Arch 开发环境` / `Arch 完整工作站`：由执行计划的强依赖组合上述能力与共享的 mise、Neovim、Docker、Shell、终端样式和 Mihomo 模块。
- `Arch 状态详情` / `Arch 系统诊断`：保留状态指纹、服务、网络、桌面和建议动作检查。

配置统一读取 `~/.config/os-init/config.env`；Arch 专用状态位于 `~/.local/state/os-init/arch`。共享能力只保留一份实现，因此单独安装和组合安装会得到相同的状态检测及配置行为。

### Shell rc 管理约定

- 不覆盖用户已有 `~/.zshrc`、`~/.bashrc`。
- 需要接入 shell 的模块会写入带标记的 os-init 管理块：
  - `# >>> os-init <name> >>>`
  - `# <<< os-init <name> <<<`
- 重复运行会更新同名管理块，不会重复追加。
- 卸载相关模块时只删除对应 os-init 管理块，不主动清理用户自己的手写配置。

### zsh + oh-my-zsh

- Linux 通过发行版包管理器安装 `zsh`；macOS 缺少 `zsh` 时通过 Homebrew 安装。
- 使用 `chsh` 将当前用户默认 shell 改为 `zsh`。
- 使用 Oh My Zsh 官方安装脚本安装，设置 `RUNZSH=no`、`CHSH=no`、`KEEP_ZSHRC=yes`，避免安装器接管现有 rc 文件和默认 shell；已安装时通过 Git 更新。
- macOS 会自动补装 `git`、`fzf`、`kubectl`；缺少 `docker` 命令时安装 OrbStack，并提示首次打开初始化。
- 克隆 Powerlevel10k 到 `~/.oh-my-zsh/custom/themes/powerlevel10k`。
- 在 `~/.zshrc` 写入或更新 `os-init oh-my-zsh` 管理块：
  - `export ZSH="$HOME/.oh-my-zsh"`
  - 默认 `ZSH_THEME="powerlevel10k/powerlevel10k"`；启用 Starship 时置空，避免双提示符。
  - `plugins=(git zsh-autosuggestions zsh-syntax-highlighting fzf docker kubectl)`
  - 必要时 `source "$ZSH/oh-my-zsh.sh"`
- 卸载时删除 `~/.oh-my-zsh`；不删除 zsh 包，不恢复默认 shell。

### starship

- 下载并执行 starship 安装脚本。
- 如果 `~/.config/starship.toml` 不存在，复制 rich 风格模板作为兼容配置。
- 在 `~/.zshrc` 和 `~/.bashrc` 写入或更新 `os-init starship` 管理块。
- 管理块会在 shell 启动时按 `OS_INIT_TERMINAL_STYLE` 选择模板：
  - `auto`：本地图形终端使用 `rich`，SSH 使用 `simple`，TTY/救援环境使用 `plain`。
  - `rich`：类 macOS/iTerm2 的彩色 powerline 风格，适合 Nerd Font 和 truecolor。
  - `simple`：SSH 推荐，保留清晰颜色，不依赖 Nerd Font 图标。
  - `plain`：最兼容，尽量少样式，适合 TTY、救援环境或未知终端。
  - `none`：不启用 starship。
- 卸载时删除 `starship` 二进制。

### 终端样式

- 写入 `~/.config/os-init/terminal/starship-rich.toml`。
- 写入 `~/.config/os-init/terminal/starship-simple.toml`。
- 写入 `~/.config/os-init/terminal/starship-plain.toml`。
- 如目标模板已存在且内容不同，会在同目录生成 `.bak.YYYYMMDD-HHMMSS` 备份。
- 在 `~/.zshrc` 和 `~/.bashrc` 写入 `os-init terminal-style` 管理块：
  - `OS_INIT_TERMINAL_ENABLE_ALIASES=1` 时，为 `eza` 写入 `ls`、`ll`、`la`、`tree` alias。
  - 未安装 `eza` 时，`ll`、`la` 降级为系统 `ls`。
  - 未安装 `bat` 但存在 `batcat` 时，写入 `bat` alias。
  - `OS_INIT_TERMINAL_BAT_THEME` 控制 bat 默认主题。
- 卸载时删除 `os-init terminal-style` 管理块和 os-init 自己写入的三套模板；不卸载 starship。

### direnv

- Linux 通过发行版包管理器安装 `direnv`；macOS 通过 Homebrew 安装。
- 在 `~/.zshrc` 写入或更新 `os-init direnv` 管理块，执行 `eval "$(direnv hook zsh)"`。
- 卸载时通过包管理器移除 `direnv`。

### zsh 插件

- 安装 zsh 主模块时会克隆或更新：
  - `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions`
  - `~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting`
- 两个插件仍可独立选择；选择 zsh 主模块时会自动安装它们。
- 会确保 zsh 和 oh-my-zsh 已存在，并更新 `os-init oh-my-zsh` 管理块里的 `plugins=(...)`。
- 卸载时删除上述插件目录。

### mise 运行时管理

- mise 是 macOS 和 Arch Linux 唯一的 Node.js、Python、Go 版本管理器，不再提供 nvm、fnm、pyenv 或 asdf 安装入口。
- macOS 与 Arch Linux 复用 `modules/mise/install.sh`；Arch 通过官方 pacman 仓库安装 mise。
- Arch root 和普通用户使用同一个模块。普通用户只在 pacman 阶段提权；mise 运行时和 Shell 配置始终写入目标用户 HOME。
- 全局版本为 Node.js 24、Python 3.13、Go 1.24，并跟随各版本系列的最新补丁版本。
- 登录 Shell 使用 shims，交互式 Shell 使用完整 activate；安装时清理由 OS Init 写入的旧 nvm/fnm/pyenv/asdf 管理块，但保留用户数据。
- 中国大陆默认配置 Node/Go SDK 下载镜像以及 npm、pip、uv、Go module 镜像；SDK 镜像失败时使用官方源重试，始终保留校验。

### Git 配置

- 如果 `~/.gitconfig` 不存在，复制 `modules/shell/gitconfig.template`。
- 按 TUI 输入写入全局 `user.name` 和 `user.email`。
- Linux 通过发行版包管理器安装 `git-lfs`，macOS 通过 Homebrew 安装，并执行 `git lfs install`。
- 卸载时只移除 `git-lfs` 包，不删除用户 `~/.gitconfig`。

### byobu + tmux

- 仅 Linux 显示该模块。
- 通过包管理器安装 `byobu` 和 `tmux`。
- 写入或更新 `~/.byobu` 下的 byobu/tmux 配置文件。
- 设置 `~/.byobu/backend` 为 `BYOBU_BACKEND=tmux`。
- 卸载时移除 byobu 包并删除 `~/.byobu`。

### ncdu

- Linux 通过发行版包管理器安装 `ncdu`；macOS 通过 Homebrew 安装。
- 卸载时通过包管理器移除 `ncdu`。

### Yazi

- Linux 下载二进制压缩包并安装：
  - `/usr/local/bin/yazi`
  - `/usr/local/bin/ya`
- macOS 通过 Homebrew 安装或更新 `yazi`。
- 创建 `~/.config/yazi`。
- 写入 `~/.config/yazi/ya.sh`，提供退出后切换目录的 shell wrapper。
- 在 `~/.zshrc` 或 `~/.bashrc` 写入 `os-init yazi` 管理块，自动 source `~/.config/yazi/ya.sh`。
- 卸载时移除 `yazi` 包或 Linux 二进制，并删除 `~/.config/yazi`。

### macOS 应用和字体

以下模块仅 macOS 显示，通过 Homebrew 安装、更新和卸载。Stats、OrbStack、Loop 和 Squirrel 按 Homebrew 自动类型识别执行 `brew install <name>`，其他图形应用明确使用 `brew install --cask <cask>`。卸载时不主动执行 `zap`，因此默认保留应用配置和用户数据。

- 开发应用：
  - `google-chrome` -> `/Applications/Google Chrome.app`
  - `codex` -> `/Applications/Codex.app`
  - `orbstack` -> `/Applications/OrbStack.app`
  - `visual-studio-code` -> `/Applications/Visual Studio Code.app`
  - `iterm2` -> `/Applications/iTerm.app`
  - `ghostty` -> `/Applications/Ghostty.app`
  - `sublime-text` -> `/Applications/Sublime Text.app`
- 代理和网络：
  - `clash-party` -> `/Applications/Clash Party.app`
  - `royal-tsx` -> `/Applications/Royal TSX.app`
  - `seafile-client` -> `/Applications/Seafile Client.app`
- 效率工具：
  - `pixpin` -> `/Applications/PixPin.app`
  - `bob` -> `/Applications/Bob.app`
  - `loop` -> `/Applications/Loop.app`
  - `jordanbaird-ice` -> `/Applications/Ice.app`
  - `stats` -> `/Applications/Stats.app`
  - `monitorcontrol` -> `/Applications/MonitorControl.app`
  - `mos` -> `/Applications/Mos.app`
  - `input-source-pro` -> `/Applications/Input Source Pro.app`
  - `menubarx` -> `/Applications/MenubarX.app`
- 输入和系统增强：
  - `karabiner-elements` -> `/Applications/Karabiner-Elements.app`
  - `squirrel-app` -> `/Library/Input Methods/Squirrel.app`
  - `aldente` -> `/Applications/AlDente.app`
  - `keka` -> `/Applications/Keka.app`
- 媒体和下载：
  - `iina` -> `/Applications/IINA.app`
  - `downie` -> `/Applications/Downie 4.app`
  - `motrix-next` -> `/Applications/MotrixNext.app`（安装前添加 tap；Homebrew 6+ 仅信任 `aninsomniacy/motrix-next/motrix-next` cask，再使用完整引用安装）
  - `spotify` -> `/Applications/Spotify.app`
  - `steam` -> `/Applications/Steam.app`
  - `qqlive` -> `/Applications/QQLive.app`
- AI、笔记、通讯和办公：
  - `chatgpt` -> `/Applications/ChatGPT.app`
  - `lm-studio` -> `/Applications/LM Studio.app`
  - `cherry-studio` -> `/Applications/Cherry Studio.app`
  - `siyuan` -> `/Applications/SiYuan.app`
  - `wechat` -> `/Applications/WeChat.app`
  - `telegram` -> `/Applications/Telegram.app`
  - `tencent-meeting` -> `/Applications/TencentMeeting.app`
  - `wpsoffice` -> `/Applications/wpsoffice.app`
  - `bitwarden` -> `/Applications/Bitwarden.app`
  - `cleanmymac` -> `/Applications/CleanMyMac-X.app`
  - `cc-switch` -> `/Applications/CC Switch.app`
- 字体：
  - `font-hack-nerd-font`
  - `font-jetbrains-mono-nerd-font`
  - `font-maple-mono-nf`

以下 macOS GUI 应用只由 os-init 安装，不接管私有配置、账号、订阅或系统代理：

- OrbStack 安装后需要打开应用完成首次初始化。
- Clash Party 安装后需要用户在应用内导入自己的代理配置。
- Motrix Next 当前未签名；如果 macOS 阻止打开，程序只提示用户核对上游说明，不会自动移除隔离属性。
- macOS cask 和 formula 模块逐个执行，各自拥有日志、耗时和退出码；单个软件失败不会把同批已成功软件误报为失败。
- Royal TSX、Seafile Client、Bitwarden 安装后需要用户在应用内登录或导入自己的数据。

### macOS 命令行工具

以下模块仅 macOS 显示，统一通过 Homebrew formula 安装、更新和卸载。卸载时执行 `brew uninstall <formula>`。

- 现代终端工具：`bat`、`eza`、`ripgrep`、`fd`、`fzf`、`zoxide`、`tmux`、`nushell`
- 开发工具：`gh`、`mise`、`uv`、`shellcheck`、`stylua`、`tree-sitter-cli`
- 网络和诊断：`htop`、`iftop`、`nload`、`nmap`、`bind`、`rsync`、`wget`
- 媒体和数据处理：`ffmpeg`、`imagemagick`、`gallery-dl`、`yt-dlp`、`jq`
- 其他已纳入工具：`herdr`、`llmfit`
- `zoxide` 会写入 `os-init zoxide` zsh 管理块。
- `mise` 会在 `~/.zprofile` 写入 shims 管理块、在 `~/.zshrc` 写入完整 activate 管理块，并安装 Node.js 24、Python 3.13、Go 1.24。

### Mihomo

- 仅 Linux systemd 环境显示该模块。
- 安装或更新 `/usr/local/bin/mihomo`，也可能优先使用发行版仓库包。
- 写入配置目录和文件：
  - `/etc/mihomo/config.yaml`
  - `/etc/mihomo/providers`
  - `/etc/mihomo/ruleset`
- 写入状态目录：
  - `/var/lib/mihomo`
  - `/var/lib/mihomo/ui` 或配置指定的 UI 目录
- 写入 systemd unit：
  - `/etc/systemd/system/mihomo.service` 或配置指定的 service 名称
- unit 设置：
  - `LimitNOFILE=1048576`
  - `CAP_NET_ADMIN`
  - `CAP_NET_BIND_SERVICE`
  - `CAP_NET_RAW`
  - `CAP_SYS_ADMIN`
- 可安装 MetaCubeXD 面板到 Mihomo 状态目录下。
- 会在用户 `~/.bashrc`、`~/.zshrc` 中追加代理环境变量模板注释块。
- 代理环境变量模板默认保持注释状态，避免安装后直接改变用户所有终端流量。
- 安装结束会提示配置是否仍为示例订阅，以及 systemd 服务是否正在运行。
- 卸载时停止并删除 service 与二进制；默认保留配置和状态目录，设置 `PURGE_DATA=1` 才删除。

### Docker

- 仅 Linux systemd 环境显示该模块。
- 安装 Docker Engine 静态二进制到 `/usr/local/bin`。
- 安装 Docker Compose CLI 插件：
  - `/usr/local/lib/docker/cli-plugins/docker-compose`
- 写入 Docker 配置：
  - `/etc/docker/daemon.json`
- `daemon.json` 可能包含：
  - `max-concurrent-downloads`
  - `max-concurrent-uploads`
  - `log-driver`
  - `log-opts`
  - `registry-mirrors`
  - `insecure-registries`
  - `data-root`
- 写入 systemd units：
  - `/etc/systemd/system/containerd.service`
  - `/etc/systemd/system/docker.service`
- 创建 `docker` 用户组，并把当前真实用户加入该组。
- 安装结束会区分：
  - Docker 服务是否正在运行
  - 当前用户是否已加入 `docker` 组
  - 当前终端会话是否需要重新登录后才免 sudo 生效
- 卸载时停止并删除 service、Compose 插件和 Docker 静态二进制。
- 默认保留 `/var/lib/docker`、`/var/lib/containerd` 和 `/etc/docker`；设置 `PURGE_DATA=1` 或 `PURGE_CONFIG=1` 才清理。

### Go

- macOS 使用 Homebrew，Arch 使用 pacman/AUR；其他 Linux 下载官方 tarball。
- 删除并重建 `/usr/local/go`。
- 在 `~/.zshrc` 或 `~/.bashrc` 写入 `os-init go` 管理块，把 `/usr/local/go/bin` 加入 `PATH`。
- 卸载时删除 `/usr/local/go`。

### Neovim + Neovide + config-yuan

- Linux 下载 Neovim tarball 并安装到：
  - `/opt/nvim-linux-x86_64` 或 `/opt/nvim-linux-arm64`
- Linux 创建 `/usr/local/bin/nvim` 软链接。
- macOS 通过 Homebrew 安装或更新 `neovim`，并通过 `neovide-app` cask 安装或更新 `/Applications/Neovide.app`。
- 通过包管理器安装 `ripgrep` 和 `fd`/`fd-find`；macOS 使用 Homebrew 的 `ripgrep`、`fd`。
- Linux 下载 lazygit 二进制并安装到 `/usr/local/bin/lazygit`；macOS 通过 Homebrew 安装或更新 `lazygit`。
- 克隆 `https://github.com/fanhuadesenlinnn/nvim.git` 到 `~/.config/nvim`，保留 `.git` 用于后续安全更新。
- 如果已有其他配置，先保存到 OS Init 用户状态备份，再切换到 config-yuan；显式清理时恢复安装前配置。
- macOS 将仓库内 `neovide/config.toml` 链接到 `~/.config/neovide/config.toml`。
- 在 `~/.zshrc` 或 `~/.bashrc` 写入 `os-init neovim` 管理块，默认设置 `EDITOR` 和 `VISUAL` 为 `nvim`。
- 卸载时按所有权移除 Neovim、Neovide；仅在 `PURGE_CONFIG=1` 时恢复安装前配置并清理 OS Init 创建的数据。

## 已移除能力

- SSH 加固模块已移除，不再写入 `/etc/ssh/sshd_config` 或 `/etc/ssh/sshd_config.d`。

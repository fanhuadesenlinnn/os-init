# 模块系统配置变更说明

本文档说明 os-init 各模块会修改哪些系统配置、用户配置和运行时参数。当前项目会按 OS 自动过滤模块：Linux 目标发行版为 Arch 系、Debian 系、RedHat 系；macOS 只显示适配 Homebrew 或通用二进制安装的 Shell、终端和开发工具模块。SSH 加固模块已移除。

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
- 卸载时删除上述 os-init drop-in 文件；PAM 追加行当前不自动删除。

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
- 卸载时停止并禁用 service，删除脚本和 service，清理 MSS 规则，重置 RPS 配置。

## 软件安装

### zsh + oh-my-zsh

- Linux 通过发行版包管理器安装 `zsh`；macOS 缺少 `zsh` 时通过 Homebrew 安装。
- 使用 `chsh` 将当前用户默认 shell 改为 `zsh`。
- 克隆或更新 `~/.oh-my-zsh`。
- 如果 `~/.zshrc` 不存在，复制 `modules/shell/zshrc.template` 到 `~/.zshrc`。
- 卸载时删除 `~/.oh-my-zsh`；不删除 zsh 包，不恢复默认 shell。

### starship

- 下载并执行 starship 安装脚本。
- 如果 `~/.config/starship.toml` 不存在，复制 `modules/shell/starship.toml`。
- 卸载时删除 `starship` 二进制。

### direnv

- Linux 通过发行版包管理器安装 `direnv`；macOS 通过 Homebrew 安装。
- 卸载时通过包管理器移除 `direnv`。

### zsh 插件

- 克隆或更新：
  - `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions`
  - `~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting`
- 卸载时删除上述插件目录。

### nvm

- 下载并执行 nvm 安装脚本。
- 安装目录为 `~/.nvm`。
- 卸载时删除 `~/.nvm`。

### fnm

- 下载并执行 fnm 安装脚本。
- 必要时通过包管理器安装 `unzip`；macOS 使用 Homebrew。
- 卸载时删除当前 `fnm` 二进制以及 `~/.local/share/fnm`、`~/.fnm`。

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
- 卸载时移除 `yazi` 包或 Linux 二进制，并删除 `~/.config/yazi`。

### macOS 应用和字体

以下模块仅 macOS 显示，统一通过 Homebrew cask 安装、更新和卸载。卸载时执行 `brew uninstall --cask <cask>`；不主动执行 `zap`，因此默认保留应用配置和用户数据。

- 开发应用：
  - `google-chrome` -> `/Applications/Google Chrome.app`
  - `codex` -> `/Applications/Codex.app`
  - `orbstack` -> `/Applications/OrbStack.app`
  - `visual-studio-code` -> `/Applications/Visual Studio Code.app`
  - `iterm2` -> `/Applications/iTerm.app`
  - `ghostty` -> `/Applications/Ghostty.app`
  - `sublime-text` -> `/Applications/Sublime Text.app`
  - `neovide-app` -> `/Applications/Neovide.app`
- 代理和网络：
  - `clash-verge-rev` -> `/Applications/Clash Verge.app`
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
  - `aldente` -> `/Applications/AlDente.app`
  - `keka` -> `/Applications/Keka.app`
- 媒体和下载：
  - `iina` -> `/Applications/IINA.app`
  - `downie` -> `/Applications/Downie 4.app`
  - `motrix` -> `/Applications/Motrix.app`
  - `spotify` -> `/Applications/Spotify.app`
  - `steam` -> `/Applications/Steam.app`
  - `qqlive` -> `/Applications/QQLive.app`
- AI、笔记、通讯和办公：
  - `chatgpt` -> `/Applications/ChatGPT.app`
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

OrbStack 安装后需要打开应用完成首次初始化。

### macOS 命令行工具

以下模块仅 macOS 显示，统一通过 Homebrew formula 安装、更新和卸载。卸载时执行 `brew uninstall <formula>`。

- 现代终端工具：`bat`、`eza`、`ripgrep`、`fd`、`fzf`、`zoxide`、`tmux`、`nushell`
- 开发工具：`gh`、`mise`、`uv`、`shellcheck`、`stylua`、`tree-sitter-cli`
- 网络和诊断：`htop`、`iftop`、`nload`、`nmap`、`bind`、`rsync`、`wget`
- 媒体和数据处理：`ffmpeg`、`imagemagick`、`gallery-dl`、`yt-dlp`、`jq`
- 其他已纳入工具：`herdr`、`llmfit`

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
  - `proxies`
- 写入 systemd units：
  - `/etc/systemd/system/containerd.service`
  - `/etc/systemd/system/docker.service`
- 创建 `docker` 用户组，并把当前真实用户加入该组。
- 卸载时停止并删除 service、Compose 插件和 Docker 静态二进制。
- 默认保留 `/var/lib/docker`、`/var/lib/containerd` 和 `/etc/docker`；设置 `PURGE_DATA=1` 或 `PURGE_CONFIG=1` 才清理。

### Go

- 下载官方 tarball；Linux 使用 `linux-*` 包，macOS 使用 `darwin-*` 包。
- 删除并重建 `/usr/local/go`。
- 不直接修改 shell rc，只提示用户把 `/usr/local/go/bin` 加到 `PATH`。
- 卸载时删除 `/usr/local/go`。

### Neovim + LazyVim

- Linux 下载 Neovim tarball 并安装到：
  - `/opt/nvim-linux-x86_64` 或 `/opt/nvim-linux-arm64`
- Linux 创建 `/usr/local/bin/nvim` 软链接。
- macOS 通过 Homebrew 安装或更新 `neovim`。
- 通过包管理器安装 `ripgrep` 和 `fd`/`fd-find`；macOS 使用 Homebrew 的 `ripgrep`、`fd`。
- Linux 下载 lazygit 二进制并安装到 `/usr/local/bin/lazygit`；macOS 通过 Homebrew 安装或更新 `lazygit`。
- 如果 `~/.config/nvim` 不存在，克隆 LazyVim starter。
- 如果 `~/.config/nvim` 已存在但不是 LazyVim，会备份为 `~/.config/nvim.bak.<timestamp>` 后再写入。
- 卸载时移除对应包或二进制，并删除 `~/.config/nvim` 和 `~/.local/share/nvim`。

## 已移除能力

- SSH 加固模块已移除，不再写入 `/etc/ssh/sshd_config` 或 `/etc/ssh/sshd_config.d`。

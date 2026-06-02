# 模块系统配置变更说明

本文档说明 os-init 各模块会修改哪些系统配置、用户配置和运行时参数。当前项目只支持 Linux，目标发行版为 Arch 系、Debian 系、RedHat 系；macOS 支持和 SSH 加固模块已移除。

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

- 通过发行版包管理器安装 `zsh`。
- 使用 `chsh` 将当前用户默认 shell 改为 `zsh`。
- 克隆或更新 `~/.oh-my-zsh`。
- 如果 `~/.zshrc` 不存在，复制 `modules/shell/zshrc.template` 到 `~/.zshrc`。
- 卸载时删除 `~/.oh-my-zsh`；不删除 zsh 包，不恢复默认 shell。

### fzf

- 克隆或更新 `~/.fzf`。
- 执行 `~/.fzf/install --all --no-bash --no-fish`。
- 卸载时执行 fzf 自带卸载脚本并删除 `~/.fzf`。

### starship

- 下载并执行 starship 安装脚本。
- 如果 `~/.config/starship.toml` 不存在，复制 `modules/shell/starship.toml`。
- 卸载时删除 `starship` 二进制。

### direnv

- 通过发行版包管理器安装 `direnv`。
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
- 必要时通过包管理器安装 `unzip`。
- 卸载时删除当前 `fnm` 二进制以及 `~/.local/share/fnm`、`~/.fnm`。

### Git 配置

- 如果 `~/.gitconfig` 不存在，复制 `modules/shell/gitconfig.template`。
- 按 TUI 输入写入全局 `user.name` 和 `user.email`。
- 通过包管理器安装 `git-lfs` 并执行 `git lfs install`。
- 卸载时只移除 `git-lfs` 包，不删除用户 `~/.gitconfig`。

### byobu + tmux

- 通过包管理器安装 `byobu` 和 `tmux`。
- 写入或更新 `~/.byobu` 下的 byobu/tmux 配置文件。
- 设置 `~/.byobu/backend` 为 `BYOBU_BACKEND=tmux`。
- 卸载时移除 byobu 包并删除 `~/.byobu`。

### ncdu

- 通过发行版包管理器安装 `ncdu`。
- 卸载时通过包管理器移除 `ncdu`。

### Yazi

- 下载 Linux 二进制压缩包。
- 安装：
  - `/usr/local/bin/yazi`
  - `/usr/local/bin/ya`
- 创建 `~/.config/yazi`。
- 写入 `~/.config/yazi/ya.sh`，提供退出后切换目录的 shell wrapper。
- 卸载时删除二进制和 `~/.config/yazi`。

### Mihomo

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

- 下载 Linux tarball。
- 删除并重建 `/usr/local/go`。
- 不直接修改 shell rc，只提示用户把 `/usr/local/go/bin` 加到 `PATH`。
- 卸载时删除 `/usr/local/go`。

### Neovim + LazyVim

- 下载 Linux Neovim tarball。
- 安装目录：
  - `/opt/nvim-linux-x86_64` 或 `/opt/nvim-linux-arm64`
- 创建 `/usr/local/bin/nvim` 软链接。
- 通过包管理器安装 `ripgrep` 和 `fd`/`fd-find`。
- 下载 lazygit 二进制并安装到 `/usr/local/bin/lazygit`。
- 如果 `~/.config/nvim` 不存在，克隆 LazyVim starter。
- 如果 `~/.config/nvim` 已存在但不是 LazyVim，会备份为 `~/.config/nvim.bak.<timestamp>` 后再写入。
- 卸载时删除 Neovim 安装目录、`/usr/local/bin/nvim`、`/usr/local/bin/lazygit`、`~/.config/nvim` 和 `~/.local/share/nvim`。

## 已移除能力

- macOS/Homebrew 安装路径已移除。
- SSH 加固模块已移除，不再写入 `/etc/ssh/sshd_config` 或 `/etc/ssh/sshd_config.d`。

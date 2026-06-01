# OS Init

面向中国大陆网络环境的 Linux 系统初始化工具。它保留原有 TUI 的多选、搜索、安装/更新/卸载体验，同时把安装逻辑调整为适配 Arch 系、Debian 系、RedHat 系的脚本体系。

<p align="center">
  <img src="demo.gif" alt="OS Init TUI 演示" width="720" />
</p>

## 快速开始

下载发布包：

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
- 发行版识别：Linux 下识别 Debian/Ubuntu、Rocky/RHEL/Fedora、Arch/Manjaro。
- 中国大陆网络适配：统一代理变量、GitHub 代理、下载重试、超时、离线包目录。
- 二进制 Docker：安装 Docker Engine 静态二进制和 Docker Compose CLI 插件。
- Mihomo：按 ArchDevKit 风格安装代理核心、配置模板、systemd 服务和 MetaCubeXD 面板。
- 中文界面：TUI、模块描述、执行状态和 README 面向中文使用场景。

## 当前模块

### 系统优化

| 模块 | 功能 |
| --- | --- |
| 内核 sysctl.d | 网络、内存、conntrack、BBR 等参数 |
| 内核 limits.d | 文件句柄和进程数限制 |
| I/O 调度器 | SSD/NVMe 使用 `none` |
| 自动调优 | 按内存生成启动时调优 |
| SSH 加固 | 使用 `sshd_config.d` 优先写入，执行前验证配置 |

### 软件安装

| 分组 | 模块 |
| --- | --- |
| Shell 工具 | zsh、oh-my-zsh、fzf、starship、direnv、zsh 插件、nvm/fnm、Git 配置、byobu/tmux |
| 终端工具 | ncdu、Yazi |
| 网络代理 | Mihomo |
| 开发工具 | Docker、Go、Neovim + LazyVim |

## 已移除模块

以下模块不再作为新方案的一部分：

| 模块 | 删除原因 |
| --- | --- |
| GNOME Optimize | Ubuntu/GNOME 桌面强相关 |
| Nautilus Optimize | Ubuntu/GNOME/Nautilus 强相关 |
| AppArmor Setup / Monitor | Debian/Ubuntu 偏向，RedHat 默认 SELinux，Slack 在大陆不稳定 |
| USB Monitor | Webhook 目标和文案需要另行设计 |
| Browsers & Apps | 桌面浏览器和 Signal 对服务器初始化价值低，国内网络不稳定 |
| PeaZip | `.deb`/macOS 偏向，不适合三大发行版统一方案 |

## 配置

配置加载顺序：

1. `modules/config/defaults.env`
2. `/etc/os-init/config.env`
3. `~/.config/os-init/config.env`
4. 当前环境变量

常用变量：

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export NO_PROXY=localhost,127.0.0.1,::1
export GITHUB_PROXY=https://gh-proxy.com/
export OS_INIT_OFFLINE=1
export OS_INIT_OFFLINE_DIR=/opt/os-init/packages
```

Docker 和 Mihomo 也可以通过同一套配置调整版本、下载地址、镜像源、systemd 代理等参数。

## TUI 操作

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
make run
```

最终发布包由 GitHub Actions 在 tag 推送后构建并发布。

发布包名称：

- `os-init_linux_amd64.tar.gz`
- `os-init_linux_arm64.tar.gz`
- `checksums.txt`

## 安全约定

- 不直接覆盖用户已有 `~/.zshrc`。
- Neovim 配置安装前会备份已有目录。
- SSH 修改前执行 `sshd -t` 验证。
- Docker 卸载时保留 `/var/lib/docker` 数据。
- 系统配置优先写入 drop-in 文件，降低对发行版默认配置的破坏。

## License

MIT

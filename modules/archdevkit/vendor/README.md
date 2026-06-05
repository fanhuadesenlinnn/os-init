# ArchDevKit

ArchDevKit 是一个面向 Arch Linux 的个人工作站初始化工具。

它适合在最小化安装后的 Arch Linux 上快速搭建日常开发环境、Hyprland 桌面、代理环境和常用工具。项目目标不是做成复杂的平台，而是给个人或小团队留一套清晰、可重复、可调整的初始化脚本。

## 能做什么

- 安装基础命令行工具、排障工具、现代 CLI 工具和 AUR helper
- 配置 systemd-resolved、archlinuxcn、Git、运行时、Neovim、Docker、字体和 Zsh
- 安装 Hyprland 桌面、Fcitx5/Rime、浏览器、终端和个人桌面配置
- 安装 Mihomo 或 sing-box，Mihomo 可选 MetaCubeXD 面板
- 支持交互式安装，也支持命令行参数安装
- 已安装且校验通过的模块会自动跳过，需要重跑时显式加 `--force`

## 快速开始

```bash
git clone https://github.com/fanhuadesenlinnn/ArchDevKit.git
cd ArchDevKit

bash install.sh
```

无参数运行会进入交互式菜单。菜单会列出每个模块的用途，直接回车会使用当前默认值。

查看完整工作站安装计划：

```bash
bash install.sh plan workstation
```

先演练，不执行真实安装：

```bash
bash install.sh workstation --dry-run
```

确认后非交互安装：

```bash
bash install.sh workstation --yes
```

## 常用命令

```bash
# 交互式菜单
bash install.sh menu

# 安装完整工作站
bash install.sh workstation

# 安装开发环境，不安装桌面
bash install.sh dev

# 只安装某个模块
bash install.sh nvim
bash install.sh docker
bash install.sh ops-toolkit
bash install.sh desktop
bash install.sh proxy

# 查看状态和诊断
bash install.sh status
bash install.sh status --verbose
bash install.sh doctor

# 重跑某个模块
bash install.sh install proxy --force
bash install.sh reset-state proxy
```

旧的简写仍然可用：

```bash
bash install.sh workstation
bash install.sh proxy
```

等价于：

```bash
bash install.sh install workstation
bash install.sh install proxy
```

## 模块

| 模块 | 用途 |
| --- | --- |
| `base` | 基础工具、同步/排障工具、现代 CLI 工具、tmux 配置、paru/yay |
| `dns` | systemd-resolved 系统 DNS |
| `archlinuxcn` | archlinuxcn 软件源 |
| `git` | Git、GitHub CLI、OpenSSH 和基础 Git 配置 |
| `ops-toolkit` | 克隆可更新的运维脚本仓库，并写入稳定命令入口 |
| `runtime` | 系统 Node.js/npm/Python/Go 和 mise |
| `nvim` | Neovim 和个人配置 |
| `docker` | Docker、Docker Compose、镜像源和用户组 |
| `fonts` | 中文字体、Emoji、Nerd Font、可选 Monaco |
| `shell` | Zsh、Oh My Zsh、Powerlevel10k 和插件 |
| `desktop` | Hyprland、SDDM、Fcitx5/Rime、浏览器、终端和 hyprdots |
| `proxy` | Mihomo 或 sing-box，Mihomo 可选 MetaCubeXD |
| `dev` | 开发环境套餐 |
| `workstation` | 完整工作站套餐 |

默认套餐：

```text
dev = base + archlinuxcn + dns + git + ops-toolkit + runtime + nvim + docker + fonts + shell + proxy
workstation = dev + desktop
```

单独安装模块时，脚本只安装该模块需要的依赖，不会偷偷展开成完整工作站。

`base` 模块内置的现代 CLI 工具包括 `rg`、`fd`、`bat`、`eza`、`dust`、`btm`、`procs`、`bandwhich`、`sd`、`hyperfine` 和 `just`。`mise` 保持在 `runtime` 模块中安装，因为它还会写入 shell 初始化和语言镜像配置。

## 配置

项目默认值放在 `install_vars`。如果只给自己使用，直接改这里就可以；如果想保留本地私有配置，可以生成用户配置文件：

```bash
bash install.sh config init
bash install.sh config show
bash install.sh config validate
```

默认用户配置文件：

```text
~/.config/archdevkit/config.env
```

配置优先级：

```text
install_vars < 用户配置文件 < 命令行参数
```

示例：

```env
ARCHDEVKIT_DEFAULT_PROFILE=dev
ENABLE_PROXY=0
GPU_TYPE=vmware
DNS_SERVERS=223.5.5.5,119.29.29.29
```

也可以临时指定配置文件：

```bash
bash install.sh plan workstation --config-file ./my-machine.env
bash install.sh plan workstation --no-config-file
```

## 常用参数

```bash
-y, --yes          自动确认
--dry-run          只显示计划，不执行
--force            忽略状态，强制重跑目标模块
--no-state         不读取或写入模块状态
--json             plan/status/doctor 输出 JSON
--verbose, -v      status 输出更多细节
--config-file PATH 加载指定用户配置文件
--no-config-file   不加载用户配置文件
--no-china         不配置 npm/pip 国内源
--no-github-proxy  不使用 GitHub 代理
--no-dns           dev/workstation 中跳过 DNS
--no-ops-toolkit   dev/workstation 中跳过 Ops Toolkit
--no-proxy         dev/workstation 中跳过 Proxy
--proxy-core NAME  指定代理核心：mihomo / sing-box
--gpu TYPE         指定 GPU 类型：auto / intel / amd / nvidia / vmware / virtio / qxl / virtualbox / none
--no-sddm          不启用 SDDM
```

完整参数可以看：

```bash
bash install.sh help
```

## 网络和代理

默认配置偏向中国大陆网络：

- npm 使用 npmmirror
- pip 使用清华源
- GitHub clone 可通过配置的 GitHub 代理临时加速
- runtime 模块默认通过 pacman 安装系统级 Node.js/npm/Python/Go，不会自动执行 `mise use`
- mise 的后续下载镜像会写入 `~/.config/archdevkit/mise-china.env`

Proxy 模块默认使用 Mihomo：

- 配置文件：`/etc/mihomo/config.yaml`
- 运行目录：`/var/lib/mihomo`
- MetaCubeXD：`/var/lib/mihomo/ui`
- 服务：`sudo systemctl status mihomo.service`

Mihomo 模板不会写入真实节点、订阅 token 或密钥；规则依赖的外部资源使用原始 URL，不额外套 GitHub 代理前缀。订阅 provider 默认直连，避免首次启动时出现代理自举循环。

## Ops Toolkit

`ops-toolkit` 模块会把 [ops-toolkit](https://github.com/fanhuadesenlinnn/ops-toolkit) 克隆到 `~/.local/share/ops-toolkit`，并在 `~/.local/bin` 写入稳定命令入口。

常用方式：

```bash
ops list
ops sshm --list
ops linux-admin-toolkit --help

# 安装时已有的 .sh 脚本也会生成同名命令
sshm --list
linux-admin-toolkit --help
```

后续脚本仓库更新时，只需要更新本地仓库；命令入口不变：

```bash
cd ~/.local/share/ops-toolkit
git pull --ff-only
```

## 桌面

`desktop` 模块默认安装 Hyprland，并使用项目内置的 hyprdots 配置。它会处理常见物理机和虚拟机显卡环境，默认包含 Fcitx5 + Rime、Google Chrome、Alacritty/foot、Neovide wrapper 等日常桌面组件。

如果只想安装桌面软件包、不写入配置：

```bash
bash install.sh desktop --hyprland-config-mode skip
```

如果想使用轻量模板：

```bash
bash install.sh desktop --hyprland-config-mode template
```

## 项目结构

```text
install.sh                 入口：加载依赖、解析参数、分发命令
install_vars               默认配置
lib/                       配置、计划、状态、交互、执行、诊断等通用层
modules/                   各安装模块
modules/desktop/           Hyprland 子模块
modules/proxy/             Proxy 子模块
files/                     模板和静态配置文件
docs/installer-architecture.md  更详细的内部结构说明
scripts/test.sh            本地校验脚本
```

## 本地校验

```bash
bash scripts/test.sh
shellcheck -x install.sh lib/*.sh modules/*.sh modules/desktop/*.sh modules/proxy/*.sh scripts/test.sh
git diff --check
```

## 设计取向

- 默认值要能直接用
- 交互式安装直接回车即可走推荐值
- 命令行安装适合重复执行
- 模块尽量独立，单独安装不展开成大套餐
- 状态清晰，可跳过、可诊断、可强制重跑
- 文档保持够用，不把 README 写成内部实现手册

# os-init 改造 AI 实施任务书

## 给执行 AI 的说明

你要在当前仓库中实现一个面向中国大陆、多 Linux 发行版的系统初始化工具改造。请把本文当作可执行工单，而不是讨论稿。

执行时必须遵守：

- 先读项目结构和当前代码，再修改。
- 按阶段实现，不要一次性重写整个项目。
- 每个阶段完成后运行对应验证命令。
- 不要删除用户未确认删除的功能。
- 不要执行真实安装、卸载、清空数据目录、重启系统服务等破坏性操作，除非用户明确要求。
- Shell 保持现场交付风格：中文日志、可重复执行、明确报错、先备份再覆盖、离线优先、代理可配置。

推荐执行顺序：

1. 删除已确认不要的软件模块和联动逻辑。
2. 增加平台检测和模块过滤能力。
3. 增加中国大陆配置、代理、下载 helper。
4. 新增 Mihomo 代理安装和配置模块，安装逻辑对齐 `ArchDevKit`。
5. 重写 Docker 为二进制安装。
6. 逐步改造保留模块以支持 Arch/Debian/RedHat。
7. 更新 README、测试、demo 和验证脚本。
8. 删除原有构建流水线，重建构建发布包流水线，打 tag 并发布一个版本。

如果一次无法完成全部改造，优先完成阶段 1 和阶段 2，并在交付说明中写清楚已完成阶段和下一阶段入口。

## 最终目标

把当前项目从“Ubuntu/macOS 开发环境初始化工具”改造成：

- 默认中文交互和中文日志。
- 主要面向中国大陆网络环境。
- 支持 Linux 三大家族：
  - Arch 系：Arch、Manjaro、EndeavourOS 等。
  - Debian 系：Debian、Ubuntu、Linux Mint、Kali 等。
  - RedHat 系：RHEL、CentOS、Rocky、AlmaLinux、Fedora、Oracle Linux 等。
- macOS 按 OS 自动过滤模块，显示适配 Homebrew 或通用二进制安装的 Shell、终端、开发工具和指定 macOS 应用模块。
- Docker 和 Docker Compose 使用官方二进制/插件安装方式，不再通过 apt/yum/dnf/pacman 安装 Docker Engine。
- 支持安装和配置 Mihomo，配置渲染、systemd 服务检测、配置测试、MetaCubeXD 面板逻辑尽量对齐 `ArchDevKit`。
- 下载源、代理、Docker registry mirror、离线包路径都可配置。
- 系统配置尽量使用 drop-in，不覆盖全局主配置文件。
- 已确认删除的桌面、安全告警模块不再出现在菜单、README、demo 或测试期望中。

## 当前项目结构摘要

当前项目是 Go 单二进制 TUI 工具：

- `main.go`
  - 使用 `go:embed` 嵌入 `modules/`。
  - 启动 Bubble Tea TUI。
  - 通过 `sudo.Prime()` 预热 sudo。

- `internal/modules/registry.go`
  - 定义 TUI 菜单模块。
  - 当前字段包括 `ID`、`Script`、`Components`、`Label`、`Description`、`Category`、`Subsection`、`OS`、`NeedsSudo` 和安装检测字段。
  - 当前只按 `OS=all/linux/darwin` 过滤。

- `internal/tui/*`
  - 菜单、模式选择、Git/Webhook 输入、确认页、执行页、结果页。
  - 当前文案主要是英文。

- `internal/embed/embed.go`
  - 运行前把嵌入文件解压到临时目录。

- `internal/runner/runner.go`
  - 执行 `modules/` 中的 shell 脚本。
  - 把 `--update` 或 `--uninstall` 传给脚本。
  - 捕获输出并写日志。

- `modules/lib.sh`
  - 当前公共 shell helper。
  - 只区分 `macos/linux`。
  - Linux 默认只走 `apt-get`。

## 已确认删除范围

这些模块必须从新方案中删除，不再适配 Arch/Debian/RedHat。

| 模块 | 文件/目录 | registry ID | 删除原因 |
| --- | --- | --- | --- |
| GNOME Optimize | `modules/gnome/` | `gnome` | Ubuntu/GNOME 桌面强相关，不符合新的多发行版初始化定位 |
| Nautilus Optimize | `modules/nautilus/` | `nautilus` | Ubuntu/GNOME/Nautilus 强相关，服务器场景不需要 |
| AppArmor Setup | `modules/apparmor/` | `apparmor` | Debian/Ubuntu 偏向；RedHat 默认 SELinux；Slack/webhook 不适合大陆默认方案 |
| AppArmor Monitor | `modules/apparmor/` | `apparmor-monitor` | 依赖 AppArmor、systemd、webhook，跨发行版维护成本高 |
| USB Monitor | `modules/usb/` | `usb-monitor` | 属于专门安全告警能力，不进入通用初始化主线 |
| Browsers & Apps | `modules/browsers/` | `browser-chrome`、`browser-brave`、`app-signal` | 桌面应用，apt/deb/mac 偏向，国内网络不稳定 |
| PeaZip | `modules/peazip/` | `peazip` | `.deb`/mac 偏向，不适合 Arch/RedHat 主线 |
| 未纳入清单的 macOS GUI 应用 | 无固定目录 | 无固定 ID | 不默认添加；只保留用户明确列出的 Homebrew cask/formula 模块 |

删除时同步清理：

- `internal/modules/registry.go` 中的上述模块注册。
- `internal/modules/registry_test.go` 中与上述模块相关的期望。
- `internal/tui/executor.go` 中 AppArmor/USB webhook 参数路由。
- `modules.NeedsUserInfo` 中 AppArmor 相关分支，只保留 `shell-git`。
- `modules.NeedsWebhook` 如无使用者，改为始终 false 或移除相关调用链。
- `README.md` 中 GNOME、Nautilus、AppArmor、USB Monitor、Browsers & Apps、PeaZip 的说明。
- `demo.tape` 中选择 GNOME/Nautilus 等已删除模块的录制步骤。

## 保留和改造范围

这些模块进入新方案主线：

| 模块 | 目标状态 |
| --- | --- |
| Docker | 改为 Linux 二进制安装 Docker Engine 和 Docker Compose plugin，支持代理、镜像、离线包、卸载保留数据 |
| Mihomo | 新增模块，按 `ArchDevKit` 的 Mihomo 逻辑安装核心、渲染配置、测试配置、可选安装 MetaCubeXD 面板 |
| Kernel sysctl | 改为 `/etc/sysctl.d/99-os-init.conf`，不要覆盖 `/etc/sysctl.conf` |
| Kernel limits | 改为 `/etc/security/limits.d/99-os-init.conf`，并按发行版检测 PAM/systemd 路径 |
| Kernel scheduler | 保留 udev 规则，但增加 systemd/udev/设备兼容检测 |
| Kernel autotune | 保留 systemd oneshot，增加依赖检测和缺失命令提示 |
| Shell tools | zsh、starship、direnv、zsh plugins、nvm、fnm、byobu/tmux、git-lfs 进入跨发行版适配 |
| Terminal tools | ncdu 进入跨发行版适配 |
| macOS apps | 新增用户列出的常用 App、代理网络、效率工具、输入增强、媒体下载、AI/笔记、通讯办公和字体模块，仅在 macOS 目标显示并通过 Homebrew cask 安装 |
| macOS CLI | 新增用户列出的 Homebrew 顶层命令工具模块，仅在 macOS 目标显示并通过 Homebrew formula 安装 |
| Go | 改为可配置下载源、架构映射、离线包 |
| Yazi | 改为可配置下载源、架构映射、离线包 |
| Neovim + LazyVim | 暂时保留，改为可配置下载源、架构映射、离线包 |


## 运行时安装顺序

AI 实施阶段顺序和用户实际选择模块后的执行顺序不是一回事。实现时必须显式处理“运行时模块执行顺序”，不要只依赖 TUI 菜单顺序。

当前项目的 `GroupByScript` 会按菜单选中顺序生成脚本组；如果菜单仍把系统优化放在前面，用户全选时可能先改内核，再安装代理、Docker、开发工具。新方案需要调整为按优先级执行。

### 执行顺序原则

安装/更新模式建议顺序：

| 优先级 | 模块类型 | 说明 |
| --- | --- | --- |
| 10 | 预检和公共配置 | 加载配置、识别平台、检查 systemd/root/包管理器、检查离线包是否齐全 |
| 20 | 网络和代理 | Mihomo 优先执行，便于后续 Docker/Go/Neovim/Yazi/GitHub 下载使用代理；未选择 Mihomo 时使用已有 `HTTP_PROXY/HTTPS_PROXY` |
| 30 | 容器运行时 | Docker 二进制安装、daemon 配置、Compose plugin |
| 40 | 基础终端和 Shell | zsh、starship、direnv、git-lfs、byobu/tmux、ncdu |
| 50 | 语言和开发工具 | Go、Yazi、Neovim + LazyVim、lazygit、ripgrep/fd |
| 80 | 内核和系统参数 | sysctl、limits、scheduler、autotune；尽量使用 drop-in，放到软件安装后 |

注意：Mihomo 是优先网络模块，不是 Docker 的硬依赖。未选择 Mihomo 时，Docker 和其他下载模块必须仍可通过已有 `HTTP_PROXY/HTTPS_PROXY`、镜像源或离线包执行。

卸载模式不要简单反向执行全部模块。建议顺序：

| 优先级 | 模块类型 | 说明 |
| --- | --- | --- |
| 20 | 开发工具和 Shell 工具 | 先删除用户态工具 |
| 30 | Docker | 停止服务但默认保留数据 |
| 40 | Mihomo | 停止服务但默认保留配置和 state dir |
| 80 | 内核和系统参数 revert | 最后恢复系统配置 |

### 代码要求

新增一个统一预检入口，二选一：

- 简单方案：在执行器启动前调用一个 shell 预检脚本，例如 `modules/preflight/check.sh`。
- 渐进方案：每个模块脚本进入 `main` 前调用 `load_os_init_config`、`detect_platform` 和自身依赖检查。

更推荐简单方案加模块内检查并存：预检脚本负责全局平台、离线包、代理配置可用性；模块内检查负责自己的具体依赖。

`internal/modules.Module` 建议新增执行优先级字段：

```go
InstallPriority   int
UninstallPriority int
```

如果不想马上扩展两个字段，也至少新增一个 `Priority int`，并在卸载模式中对系统配置类模块做特殊排序。

执行器改造要求：

- `modules.GroupByScript` 或 `newExecutorModel` 必须稳定排序脚本组。
- 同一个脚本的多个组件仍要合并，例如 `shell/install.sh zsh starship git`。
- 同一优先级内保持菜单顺序，便于用户理解。
- `scriptGroup` 上要保留参与合并模块的最高/最低优先级，避免 shell 组件被拆散。
- README 中说明“选择多个模块时会按安全顺序执行，不完全等同菜单顺序”。

### 推荐优先级映射

| registry ID | install priority | uninstall priority |
| --- | --- | --- |
| `mihomo` | 20 | 40 |
| `docker` | 30 | 30 |
| `shell-*` | 40 | 20 |
| `terminal-ncdu` | 40 | 20 |
| `go` | 50 | 20 |
| `yazi` | 50 | 20 |
| `neovim` | 50 | 20 |
| `kernel-*` | 80 | 80 |

### 验收

新增或更新测试：

- 选择 `docker`、`mihomo`、`go` 时，执行顺序必须是 `mihomo -> docker -> go`。
- 选择多个 `shell-*` 组件时，仍合并为一次 `shell/install.sh` 调用。
- 卸载全选时，Docker/Mihomo 不删除数据目录，系统配置恢复排在最后。


## 阶段 1：删除已确认模块

### 要改的文件

- `internal/modules/registry.go`
- `internal/modules/registry_test.go`
- `internal/tui/executor.go`
- `README.md`
- `demo.tape`
- 删除目录：
  - `modules/gnome/`
  - `modules/nautilus/`
  - `modules/apparmor/`
  - `modules/usb/`
  - `modules/browsers/`
  - `modules/peazip/`

### 实施要求

- 从注册表删除对应模块项。
- 删除 AppArmor/USB webhook 特殊处理。
- `NeedsUserInfo` 只保留 `shell-git`。
- 如果没有任何模块需要 webhook，删除或禁用 webhook 输入入口。
- `NeedsSudo` 测试不应再允许已删除脚本。
- README 不再宣传已删除功能。
- demo 不再移动到已删除菜单项。

### 验收

运行：

```bash
go test ./...
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

预期：

- 测试通过。
- TUI 菜单中不再出现已删除模块。
- `rg "apparmor|usb-monitor|GNOME|Nautilus|Chrome|Brave|Signal|PeaZip"` 只允许出现在历史说明、迁移说明或本任务书中，不应出现在实际菜单、README 功能列表、demo 流程中。

## 阶段 2：平台检测和模块过滤

### 要新增的文件

- `internal/platform/platform.go`
- `internal/platform/platform_test.go`

### 平台模型

实现一个目标平台结构，至少包含：

```go
type Family string

const (
    FamilyDarwin Family = "darwin"
    FamilyDebian Family = "debian"
    FamilyRedHat Family = "redhat"
    FamilyArch   Family = "arch"
    FamilyUnknown Family = "unknown"
)

type Target struct {
    GOOS      string
    ID        string
    IDLike    []string
    Family    Family
    VersionID string
    Codename  string
    Init      string // systemd/openrc/unknown
}
```

检测规则：

| Family | 判断 |
| --- | --- |
| `arch` | `ID=arch/manjaro/endeavouros` 或 `ID_LIKE` 包含 `arch` |
| `debian` | `ID=debian/ubuntu/linuxmint/kali` 或 `ID_LIKE` 包含 `debian/ubuntu` |
| `redhat` | `ID=rhel/centos/rocky/almalinux/fedora/oracle` 或 `ID_LIKE` 包含 `rhel/fedora/centos` |
| `darwin` | `runtime.GOOS == "darwin"` |

`/etc/os-release` 解析必须支持：

- `KEY=value`
- `KEY="quoted value"`
- `ID_LIKE="rhel fedora"`
- 缺失文件时返回 `FamilyUnknown`，不要 panic。

### 修改模块注册

把 `internal/modules.Module` 从单一 `OS string` 扩展为更明确的兼容字段。

建议字段：

```go
OS       string   // 暂时保留，避免一次性大改
Families []string // "all", "debian", "redhat", "arch", "darwin"
Requires []string // "systemd", "linux"
Tags     []string // "server", "dev", "cn-ready"
```

新增：

```go
func ForTarget(target platform.Target) []Module
```

过滤规则：

- `OS=all` 兼容所有。
- `OS=linux` 只在 Linux。
- `OS=darwin` 只在 macOS。
- `Families` 为空时沿用 `OS`。
- `Families=["all"]` 时所有 family 可见。
- `Families` 指定时必须匹配 target family。

修改 `tui.New`，从 `modules.ForOS(runtime.GOOS)` 切换到 `platform.Detect()` 加 `modules.ForTarget(target)`。

### 验收

新增测试覆盖：

- Ubuntu/Debian -> `FamilyDebian`
- Rocky/Alma/CentOS/RHEL/Fedora -> `FamilyRedHat`
- Arch/Manjaro -> `FamilyArch`
- macOS -> `FamilyDarwin`
- unknown -> 不崩溃

运行：

```bash
go test ./...
```

## 阶段 3：中国大陆配置、代理和下载 helper

### 要改的文件

- `modules/lib.sh`
- 新增 `modules/config/defaults.env`
- 需要下载的模块脚本：
  - `modules/docker/install.sh`
  - `modules/go/install.sh`
  - `modules/yazi/install.sh`
  - `modules/neovim/install.sh`
  - `modules/shell/install.sh`
  - `modules/mihomo/install.sh`

### 配置加载顺序

新增配置加载函数 `load_os_init_config`：

1. `modules/config/defaults.env`
2. `/etc/os-init/config.env`
3. `$HOME/.config/os-init/config.env`
4. 当前环境变量覆盖文件配置

注意：

- 脚本经 sudo 执行时，`$HOME` 可能是 `/root`。需要优先识别真实用户：
  - `${SUDO_USER}` 非空时，通过 `getent passwd "$SUDO_USER"` 找家目录。
  - 否则用当前 `$HOME`。
- 不要把密码、token、代理认证信息写进仓库。

### 默认配置

`modules/config/defaults.env` 至少包含：

```bash
OS_INIT_LANG=zh_CN
OS_INIT_REGION=cn
OS_INIT_OFFLINE=0
OS_INIT_FILES_DIR=

HTTP_PROXY=
HTTPS_PROXY=
NO_PROXY=localhost,127.0.0.1,::1

DOWNLOAD_RETRY=3
DOWNLOAD_TIMEOUT=30
GITHUB_PROXY=

DOCKER_DOWNLOAD_BASE=https://download.docker.com
DOCKER_REGISTRY_MIRRORS=
DOCKER_INSECURE_REGISTRIES=
DOCKER_DATA_ROOT=

ENABLE_MIHOMO=1
MIHOMO_PACKAGE=mihomo
MIHOMO_VERSION=
MIHOMO_DOWNLOAD_BASE=
MIHOMO_BINARY_SOURCE=
MIHOMO_SERVICE_NAME=mihomo.service
MIHOMO_CONFIG_DIR=/etc/mihomo
MIHOMO_CONFIG_FILE=/etc/mihomo/config.yaml
MIHOMO_CONFIG_SOURCE=
MIHOMO_MIXED_PORT=7890
MIHOMO_ALLOW_LAN=0
MIHOMO_BIND_ADDRESS=127.0.0.1
MIHOMO_CONTROLLER_HOST=127.0.0.1
MIHOMO_CONTROLLER_PORT=9090
MIHOMO_DNS_LISTEN=127.0.0.1:1053
MIHOMO_SECRET=
MIHOMO_STATE_DIR=/var/lib/mihomo
MIHOMO_EXTERNAL_UI_DIR=/var/lib/mihomo/ui
MIHOMO_AUTO_ENABLE_SERVICE=1
ENABLE_METACUBEXD=1
METACUBEXD_PACKAGE=metacubexd-bin
METACUBEXD_VERSION=
METACUBEXD_SOURCE=
METACUBEXD_WEB_ROOT=/usr/share/metacubexd

GO_DOWNLOAD_BASE=https://go.dev/dl
GO_VERSION_URL=https://go.dev/VERSION?m=text
```

### Shell helper 要求

`modules/lib.sh` 增加：

```bash
detect_platform
is_family
require_linux
require_systemd
pkg_update
pkg_install
pkg_remove
pkg_is_installed
download_file
download_or_offline_file
backup_file
json_array_from_csv
```

包管理映射：

| Family | 安装 | 卸载 | 检测 |
| --- | --- | --- | --- |
| Debian 系 | `apt-get update && apt-get install -y` | `apt-get remove -y` | `dpkg-query -W` |
| RedHat 系 | `dnf install -y`，无 dnf 时 fallback `yum install -y` | `dnf/yum remove -y` | `rpm -q` |
| Arch 系 | `pacman -Sy --noconfirm --needed` | `pacman -Rns --noconfirm` | `pacman -Q` |

下载规则：

- 优先使用 `curl`，没有 curl 再使用 `wget`。
- 支持 retry、timeout。
- 导出 `HTTP_PROXY/HTTPS_PROXY/NO_PROXY` 及小写版本。
- `OS_INIT_OFFLINE=1` 时禁止触网，只从 `OS_INIT_FILES_DIR` 或模块本地 `files/` 查找。
- 缺少离线文件时必须提前报错，不要边改系统边发现文件缺失。
- 如果设置了 `GITHUB_PROXY`，GitHub release/raw URL 可以通过该代理前缀改写。

### 中文日志

公共日志函数统一中文：

```bash
skip()    { echo -e "  ${GREEN}[跳过]${NC} $1"; }
install() { echo -e "  ${YELLOW}[安装]${NC} $1"; }
update()  { echo -e "  ${CYAN}[更新]${NC} $1"; }
remove()  { echo -e "  ${RED}[删除]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[警告]${NC} $1"; }
die()     { echo -e "  ${RED}[错误]${NC} $1" >&2; exit 1; }
```

### 验收

运行：

```bash
go test ./...
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

人工检查：

- `modules/lib.sh` 不再默认把所有 Linux 都当 apt。
- 下载函数支持代理和离线模式。
- 没有硬编码唯一中国镜像站。

## 阶段 4：Mihomo 代理安装和配置

### 目标

新增 Mihomo 模块，安装和配置逻辑对齐 `/Users/caohengyuan/Documents/ArchDevKit` 中的 Proxy/Mihomo 实现。

参考文件：

- `/Users/caohengyuan/Documents/ArchDevKit/modules/proxy.sh`
- `/Users/caohengyuan/Documents/ArchDevKit/modules/proxy/mihomo.sh`
- `/Users/caohengyuan/Documents/ArchDevKit/modules/proxy/config_source.sh`
- `/Users/caohengyuan/Documents/ArchDevKit/modules/proxy/common.sh`
- `/Users/caohengyuan/Documents/ArchDevKit/files/mihomo/config.yaml.tpl`

不要简单复制 Arch-only 包安装逻辑；需要保留 ArchDevKit 的行为语义，并适配本项目的 Arch/Debian/RedHat/macOS 目标。第一期 Mihomo 只作为 Linux systemd 模块进入菜单，macOS 暂不显示。

### 要新增的文件

- `modules/mihomo/install.sh`
- `modules/mihomo/config.yaml.tpl`

### 要改的文件

- `internal/modules/registry.go`
- `internal/modules/registry_test.go`
- `modules/lib.sh`
- `README.md`

### 注册表要求

新增菜单项：

```go
{
    ID: "mihomo",
    Script: "mihomo/install.sh",
    Label: "Mihomo",
    Description: "代理核心和 MetaCubeXD 面板",
    Category: "installation",
    Subsection: "Network",
    OS: "linux",
    Families: []string{"arch", "debian", "redhat"},
    NeedsSudo: true,
    InstalledCmd: "mihomo",
}
```

如果 `InstallSubsections()` 仍是固定列表，新增 `Network` 分组，位置建议在 `Dev Tools` 前。

### 安装逻辑

对齐 ArchDevKit 的核心行为：

- `install_mihomo`
  - Arch 系优先使用 `MIHOMO_PACKAGE`，默认 `mihomo`。
  - Debian/RedHat 系如果仓库中存在 `MIHOMO_PACKAGE` 可以走 `pkg_install`；否则使用可配置二进制安装源。
  - 二进制安装路径、下载源、版本和离线包必须可配置，使用 `MIHOMO_VERSION`、`MIHOMO_DOWNLOAD_BASE`、`MIHOMO_BINARY_SOURCE` 等变量，不要硬编码最新版本。
  - 安装后必须能执行 `mihomo -v`。

- `configure_mihomo`
  - 创建 `${MIHOMO_CONFIG_DIR}`、`${MIHOMO_CONFIG_DIR}/providers`、`${MIHOMO_CONFIG_DIR}/ruleset`。
  - 默认配置来源为 `modules/mihomo/config.yaml.tpl`。
  - `MIHOMO_CONFIG_SOURCE` 支持：
    - 空值：渲染默认模板。
    - 本地 `.tpl`：按变量渲染模板。
    - 本地 `config.yaml`：直接安装为 root 配置文件。
    - `http://` 或 `https://` URL：下载后安装为 root 配置文件。
  - 目标配置文件权限为 `0600`。
  - 不允许把真实订阅链接、token、secret 写入仓库。

- 模板渲染
  - 从 ArchDevKit 的 `files/mihomo/config.yaml.tpl` 迁移模板思路。
  - 保留以下占位符语义：
    - `__MIHOMO_MIXED_PORT__`
    - `__MIHOMO_ALLOW_LAN__`
    - `__MIHOMO_BIND_ADDRESS__`
    - `__MIHOMO_CONTROLLER_HOST__`
    - `__MIHOMO_CONTROLLER_PORT__`
    - `__MIHOMO_DNS_LISTEN__`
    - `__MIHOMO_SECRET_YAML__`
    - `__METACUBEXD_EXTERNAL_UI_LINE__`
  - `allow-lan` 要输出 YAML bool：`true/false`。
  - `secret` 要做 YAML 字符串转义。
  - 默认订阅 provider 使用示例 URL，不写真实节点。
  - `proxy-providers.airport.proxy` 必须保持 `DIRECT`，避免首次启动时代理自举循环。
  - 规则源、GEO 数据源保持原始 URL，不通过 `GITHUB_PROXY` 自动改写。

- systemd 适配
  - 如果发行版包已经提供 `${MIHOMO_SERVICE_NAME}`，不要覆盖包自带 unit。
  - 像 ArchDevKit 一样通过 `systemctl show -P FragmentPath` 检查 unit。
  - 如果 unit 使用 `StateDirectory` 和 `LoadCredential`，按该运行方式测试配置。
  - 如果是二进制安装且没有 unit，则由本模块创建 `/etc/systemd/system/mihomo.service`。
  - 创建自管 unit 前先备份同名文件。

- 配置测试
  - 启动服务前必须测试配置。
  - 参考 ArchDevKit 的方式：
    - 识别 state dir，默认 `/var/lib/mihomo`。
    - 临时把配置安装到 `${state_dir}/config.yaml`。
    - 执行 `mihomo -t -d "${state_dir}"`。
    - 测试后删除临时文件。
  - 如果配置仍包含 `https://example.com/your-subscription-url`，不要自动启动服务，输出中文提示让用户替换订阅或指定 `--mihomo-config`。
  - 如果配置测试失败，不要启用服务，避免 systemd 反复重启。

- MetaCubeXD
  - `ENABLE_METACUBEXD=1` 时安装面板。
  - Arch 系可以使用 `METACUBEXD_PACKAGE=metacubexd-bin`。
  - Debian/RedHat 系需要支持 `METACUBEXD_VERSION`、`METACUBEXD_SOURCE` 或离线目录提供静态 UI。
  - 面板目录必须放在 Mihomo 可访问的 state dir 内，默认 `${MIHOMO_STATE_DIR}/ui`。
  - 如果用户配置的 `MIHOMO_EXTERNAL_UI_DIR` 不在 state dir 内，自动改为 `${state_dir}/ui` 并给中文警告。
  - 找不到 `index.html` 时只警告，不要让整个安装失败。

- shell 代理环境模板
  - 参考 ArchDevKit，在真实用户的 `.bashrc` 和 `.zshrc` 写入受管理注释块。
  - 默认全部注释，不强制打开代理：

```bash
# os-init proxy environment template. Uncomment when needed.
# export http_proxy="http://127.0.0.1:7890"
# export https_proxy="http://127.0.0.1:7890"
# export all_proxy="socks5://127.0.0.1:7890"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"
# export ALL_PROXY="$all_proxy"
# export no_proxy="localhost,127.0.0.1,::1"
# export NO_PROXY="$no_proxy"
```

- 安全提示
  - 如果 `MIHOMO_CONTROLLER_HOST=0.0.0.0` 且 `MIHOMO_SECRET` 为空，必须输出中文警告。
  - 默认建议控制接口监听 `127.0.0.1`。

### 卸载逻辑

`--uninstall` 时：

- 停止并禁用 `${MIHOMO_SERVICE_NAME}`。
- 只删除本模块创建的二进制、systemd unit、MetaCubeXD UI 和 shell 管理块。
- 默认保留 `${MIHOMO_CONFIG_FILE}` 和 `${MIHOMO_STATE_DIR}`，避免删除用户订阅和缓存。
- 只有显式 `--purge-data` 或配置开启时才删除配置和 state dir，并要求二次确认。

### 验收

静态验证：

```bash
bash -n modules/mihomo/install.sh
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
go test ./...
```

文本验证：

```bash
rg -n "example.com/your-subscription-url|proxy: DIRECT|__MIHOMO_MIXED_PORT__|METACUBEXD" modules/mihomo
```

预期：

- Mihomo 模块存在菜单注册。
- 默认模板不包含真实订阅、真实节点、token、secret。
- 启动服务前有 `mihomo -t -d` 配置测试逻辑。
- 卸载默认保留配置和 state dir。

## 阶段 5：Docker 二进制安装

### 目标

重写 `modules/docker/install.sh`，Docker Engine 和 Docker Compose 不再通过包管理器安装。

允许用包管理器安装必要前置依赖，例如 `ca-certificates`、`curl`、`tar`、`xz`、`iptables`、`procps`，但禁止用包管理器安装：

- `docker`
- `docker-ce`
- `docker-ce-cli`
- `containerd.io`
- `docker-compose`
- `docker-compose-plugin`

### 配置项

放在 `modules/config/defaults.env`，不要写死在脚本逻辑里：

```bash
DOCKER_VERSION=
DOCKER_COMPOSE_VERSION=
DOCKER_CHANNEL=stable
DOCKER_INSTALL_DIR=/opt/docker
DOCKER_BIN_DIR=/usr/local/bin
DOCKER_COMPOSE_PLUGIN_DIR=/usr/local/lib/docker/cli-plugins
DOCKER_COMPAT_COMPOSE=1
DOCKER_START_SERVICE=1
DOCKER_FORCE_BINARY=0
DOCKER_PURGE_DATA=0
```

实施时注意：

- `DOCKER_VERSION` 和 `DOCKER_COMPOSE_VERSION` 必须是可控版本。
- 如果文档或配置中没有确定版本，执行 AI 需要先查询 Docker 官方 release 或请用户提供版本。
- 不要把未验证的“最新版”硬编码进脚本。

### 架构映射

至少支持：

| `uname -m` | Docker static arch | Compose asset arch |
| --- | --- | --- |
| `x86_64` | `x86_64` | `x86_64` |
| `aarch64` | `aarch64` | `aarch64` |
| `arm64` | `aarch64` | `aarch64` |

不支持架构必须明确报错。

### 在线和离线路径

在线 Docker Engine：

```bash
${DOCKER_DOWNLOAD_BASE}/linux/static/${DOCKER_CHANNEL}/${docker_arch}/docker-${DOCKER_VERSION}.tgz
```

在线 Compose plugin：

```bash
https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}
```

离线文件建议命名：

```text
${OS_INIT_FILES_DIR}/docker/docker-${DOCKER_VERSION}-${docker_arch}.tgz
${OS_INIT_FILES_DIR}/docker/docker-compose-linux-${compose_arch}-${DOCKER_COMPOSE_VERSION}
```

离线模式下：

- 必须在 preflight 阶段检查文件存在。
- 缺文件直接退出。
- 不允许触网。

### 安装流程

1. `parse_update_flag "$@"`
2. `load_os_init_config`
3. `require_linux`
4. `require_systemd`
5. `detect_platform`
6. 检查前置依赖。
7. 如果检测到包管理器安装的 Docker：
   - 默认报错并提示设置 `DOCKER_FORCE_BINARY=1`。
   - 不要自动覆盖包管理器文件。
8. 下载或读取离线包。
9. 解压到：

```text
/opt/docker/docker-${DOCKER_VERSION}/
```

10. 检查必要二进制：

```text
docker
dockerd
containerd
containerd-shim-runc-v2
ctr
runc
```

11. 更新 symlink：

```text
/opt/docker/current -> /opt/docker/docker-${DOCKER_VERSION}
/usr/local/bin/docker -> /opt/docker/current/docker
/usr/local/bin/dockerd -> /opt/docker/current/dockerd
...
```

12. 安装 Compose plugin：

```text
/usr/local/lib/docker/cli-plugins/docker-compose
```

13. 如 `DOCKER_COMPAT_COMPOSE=1`，创建兼容命令：

```text
/usr/local/bin/docker-compose -> /usr/local/lib/docker/cli-plugins/docker-compose
```

14. 创建 `docker` 组：

```bash
groupadd -f docker
```

15. 如果有真实用户，加入 docker 组：

```bash
usermod -aG docker "$SUDO_USER"
```

16. 写入 `/etc/docker/daemon.json`。
17. 写入 systemd unit。
18. `systemctl daemon-reload`
19. 如果 `DOCKER_START_SERVICE=1`，启动并启用：

```bash
systemctl enable --now containerd
systemctl enable --now docker
```

20. 验证：

```bash
docker version
docker compose version
docker info
```

不要默认执行 `docker run hello-world`，因为大陆或离线环境会触发拉取失败。

### daemon.json

默认路径：

```text
/etc/docker/daemon.json
```

写入前必须备份已有文件：

```text
/etc/docker/daemon.json.bak-os-init-YYYYmmddHHMMSS
```

建议配置项：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "registry-mirrors": [],
  "insecure-registries": [],
  "proxies": {
    "http-proxy": "",
    "https-proxy": "",
    "no-proxy": "localhost,127.0.0.1,::1"
  }
}
```

规则：

- `registry-mirrors` 来自 `DOCKER_REGISTRY_MIRRORS`，逗号分隔。
- `insecure-registries` 来自 `DOCKER_INSECURE_REGISTRIES`，逗号分隔。
- `data-root` 只有 `DOCKER_DATA_ROOT` 非空时写入。
- `proxies` 只有代理配置非空时写入，避免空字段造成误解。
- 不要硬编码公共 Docker 镜像站。
- 生成后用 JSON parser 校验；可用 `python3 -m json.tool`，没有 python3 时至少保证模板逻辑简单且可读。

### systemd unit

写入：

```text
/etc/systemd/system/containerd.service
/etc/systemd/system/docker.service
```

`docker.service` 建议使用 Unix socket，不依赖 socket activation：

```ini
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd -H unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=2
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
```

如果目标系统不支持 `Type=notify`，脚本应在失败时提示并允许现场改为 `Type=simple`，不要静默失败。

### 更新流程

`--update` 时：

- 下载或读取新版本。
- 解压到新目录。
- 停止 `docker` 前提示可能影响运行容器。
- 切换 `/opt/docker/current`。
- 重启服务。
- 验证失败时回滚 symlink 到旧版本，并重启服务。

### 卸载流程

`--uninstall` 时：

- 停止并禁用 `docker`、`containerd`。
- 删除 systemd unit。
- 删除 `/usr/local/bin` 中由本脚本创建的 symlink。
- 删除 `/usr/local/lib/docker/cli-plugins/docker-compose`。
- 删除 `/opt/docker/current` 和对应版本目录，或保留旧版本目录由配置控制。
- 默认保留：
  - `/var/lib/docker`
  - `/var/lib/containerd`
  - `/etc/docker/daemon.json.bak-*`
- 只有 `DOCKER_PURGE_DATA=1` 或显式 `--purge-data` 才删除数据目录，并要求二次确认。

### 验收

静态验证：

```bash
bash -n modules/docker/install.sh
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
go test ./...
```

文本验证：

```bash
rg -n "apt-get install.*docker|yum install.*docker|dnf install.*docker|pacman .*docker" modules/docker modules/lib.sh
```

预期：Docker 安装脚本不能通过包管理器安装 Docker Engine 或 Compose。

## 阶段 6：保留模块跨发行版改造

按风险从低到高逐步改。

### 6.1 Shell 和 Terminal 工具

改造：

- `modules/shell/install.sh`
- `modules/terminal/install.sh`

要求：

- 使用 `pkg_install/pkg_remove/pkg_is_installed`。
- 通过 logical package name 映射不同发行版包名。
- 保持组件参数机制：`zsh`、`starship`、`direnv`、`plugins`、`nvm`、`fnm`、`byobu`、`git`。
- GitHub 下载走 `download_file` 或 git proxy 配置。
- 不覆盖用户现有 `.zshrc`、`.gitconfig`。

### 6.2 Go/Yazi/Neovim

改造：

- `modules/go/install.sh`
- `modules/yazi/install.sh`
- `modules/neovim/install.sh`

要求：

- 支持 `x86_64` 和 `aarch64`。
- 下载源可配置。
- 支持离线包。
- 缺少版本或不支持架构时明确报错。
- 不再固定 Linux x86_64。

### 6.3 Kernel

改造：

- `modules/kernel/optimize.sh`
- `modules/kernel/autotune.sh`

要求：

- sysctl 改写 `/etc/sysctl.d/99-os-init.conf`。
- limits 改写 `/etc/security/limits.d/99-os-init.conf`。
- systemd limit 用 drop-in：

```text
/etc/systemd/system.conf.d/99-os-init.conf
/etc/systemd/user.conf.d/99-os-init.conf
```

- 写入前备份已有 os-init 管理文件。
- reload/restart 前先校验：

```bash
sysctl --system
```

## 阶段 7：中文化 TUI 和文档

### TUI 文案

修改：

- `internal/tui/menu.go`
- `internal/tui/mode.go`
- `internal/tui/confirm.go`
- `internal/tui/executor.go`
- `internal/tui/summary.go`
- `internal/tui/gitinfo.go`
- `internal/tui/banner.go`
- `internal/modules/registry.go`

目标文案：

| 英文 | 中文 |
| --- | --- |
| OS Kickstart | OS Init 或 系统初始化 |
| Optimizations | 系统优化 |
| Installations | 软件安装 |
| Shell | Shell 工具 |
| Terminal | 终端工具 |
| Dev Tools | 开发工具 |
| Install | 安装 |
| Update | 更新 |
| Uninstall | 卸载 |
| Running scripts... | 正在执行脚本... |
| Results | 执行结果 |
| succeeded | 成功 |
| failed | 失败 |

### README

README 要改成中文，说明：

- 支持 Arch/Debian/RedHat 系。
- 面向中国大陆网络。
- Docker 是二进制安装。
- Mihomo 可安装配置，支持自定义配置来源和 MetaCubeXD 面板。
- 支持代理和离线包。
- 已删除桌面应用和告警模块。

## 阶段 8：构建发布流水线和版本发布

### 目标

在阶段 1-7 全部实现、测试通过并推送后，重建 GitHub 构建发布流程，并发布一个可下载的正式版本。

### 要改的文件

- `.github/workflows/*`
- `README.md`
- 如有需要，`goreleaser` 或自定义打包配置文件。

### 处理要求

- 删除原有构建/发布流水线，不保留已经不适合新项目目标的 workflow。
- 新建一个清晰的 release workflow，建议文件名为 `.github/workflows/release.yml`。
- workflow 至少支持：
  - tag `v*` 触发正式发布。
  - 手动 `workflow_dispatch` 触发测试发布。
  - Linux amd64、Linux arm64、Darwin amd64、Darwin arm64 构建。
  - 产物命名带系统、架构和版本号。
  - 每个压缩包包含主二进制、README、LICENSE。
  - 生成 checksum 文件。
  - 创建 GitHub Release 并上传所有发布包。
- 如果继续使用 GoReleaser，配置必须和当前模块、产物名称、目标平台一致。
- 如果不用 GoReleaser，workflow 中显式 `go build`、`tar.gz`、`shasum -a 256`、`gh release create/upload`。
- 发布前先通过 GitHub/gh 查看现有 tag 和 release，避免版本号冲突。
- 版本号由执行 AI 决定，推荐选择下一个合理小版本，例如 `v0.1.0`、`v0.2.0` 或在已有 tag 基础上递增。
- 打 tag 前必须确认工作区干净，且所有阶段验证通过。
- 发布后验证 GitHub Release 页面存在，且 release assets 完整。

### 验收

本地验证：

```bash
go test ./...
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
go build ./...
```

GitHub 验证：

- 新 tag 已推送到远程。
- GitHub Actions release workflow 成功。
- GitHub Release 已创建。
- Release assets 至少包含 linux/darwin 的 amd64/arm64 包和 checksum。

## 全局安全要求

必须遵守：

- 不要使用 `git reset --hard`。
- 不要还原用户已有改动。
- 不要用包管理器安装 Docker Engine 或 Compose。
- 不要默认清空 `/var/lib/docker` 或 `/var/lib/containerd`。
- 不要硬编码公共镜像站作为唯一来源。
- 不要覆盖 `/etc/sysctl.conf`、`/etc/security/limits.conf`。
- 不要在测试中执行真实 `systemctl restart docker/mihomo`。
- 不要删除 Neovim、nvm/fnm、macOS 支持，除非用户再次确认。

危险操作必须有保护：

- `rm -rf` 前检查路径非空且符合预期。
- 删除数据必须要求 `--purge-data` 或配置显式开启。
- 写系统文件必须备份。
- 生成配置必须尽可能校验。

## 全局验收标准

基础验证：

```bash
go test ./...
find modules -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

删除验证：

```bash
rg -n "gnome|nautilus|apparmor|usb-monitor|browser-chrome|browser-brave|app-signal|peazip" internal modules README.md demo.tape
```

预期：

- 不应出现实际菜单注册或脚本引用。
- 如果出现，只能是迁移说明或历史任务文档。

Mihomo 验证：

```bash
bash -n modules/mihomo/install.sh
rg -n "example.com/your-subscription-url|proxy: DIRECT|mihomo -t -d|METACUBEXD|MIHOMO_SECRET" modules/mihomo tasks/plan-cn-docker-multi-distro.md
```

预期：

- 默认模板不包含真实订阅链接、真实节点、token、secret。
- 配置来源支持本地文件、本地模板和远程 URL。
- 启动服务前必须测试配置；测试失败或仍是示例订阅时不自动启动服务。
- MetaCubeXD 面板目录必须位于 Mihomo state dir 内。
- 卸载默认保留 Mihomo 配置和 state dir。

Docker 验证：

```bash
bash -n modules/docker/install.sh
rg -n "apt-get install.*docker|yum install.*docker|dnf install.*docker|pacman .*docker" modules/docker modules/lib.sh
```

预期：

- 不通过包管理器安装 Docker Engine 或 Compose。
- `daemon.json` 生成逻辑能处理 registry mirrors、insecure registries、proxy、data-root。
- 默认卸载保留 Docker 数据目录。

平台验证：

- Go 单元测试覆盖 os-release 样例。
- Debian/Ubuntu 显示 Debian family 模块。
- Rocky/Alma/CentOS/RHEL/Fedora 显示 RedHat family 模块。
- Arch/Manjaro 显示 Arch family 模块。

## 建议提交粒度

如果需要分多次提交，推荐：

1. `remove unsupported desktop and webhook modules`
2. `add linux family platform detection`
3. `add cn config and download helpers`
4. `add mihomo proxy module`
5. `install docker from static binaries`
6. `adapt retained modules for linux families`
7. `localize tui and docs`
8. `rebuild release workflow and publish version`

每次提交前都运行基础验证。

## 官方参考

执行 Docker 相关实现时，以官方文档为准：

- Docker Engine 二进制安装：`https://docs.docker.com/engine/install/binaries/`
- Docker Compose Linux 插件安装：`https://docs.docker.com/compose/install/linux/`
- Docker daemon 配置文件：`https://docs.docker.com/engine/daemon/`
- Docker daemon 代理配置：`https://docs.docker.com/engine/daemon/proxy/`

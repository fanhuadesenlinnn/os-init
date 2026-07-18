package modules

import "github.com/fanhuadesenlinnn/os-init/internal/platform"

// ModuleKind describes what "done" means for a module.
type ModuleKind string
type PrivilegePolicy string

const (
	KindInstallOnly      ModuleKind = "install-only"
	KindShellIntegration ModuleKind = "shell-integration"
	KindSystemService    ModuleKind = "system-service"
	KindSystemTuning     ModuleKind = "system-tuning"
)

const (
	PrivilegeNone        PrivilegePolicy = ""
	PrivilegeSystem      PrivilegePolicy = "system"
	PrivilegeLinuxSystem PrivilegePolicy = "linux-system"
	PrivilegeMacOSAdmin  PrivilegePolicy = "macos-admin"
	PrivilegeArchSystem  PrivilegePolicy = "arch-system"
)

const (
	ActivationZshrc        = "zshrc"
	ActivationShellProfile = "shell-profile"
	ActivationSystemd      = "systemd"
	ActivationManual       = "manual"
	ActivationRelogin      = "relogin"
)

// Module describes a stateful capability. Presets and actions have dedicated
// source types and are adapted only at the flat catalog boundary.
type Module struct {
	ID                  string   // unique key, e.g. "kernel-sysctl"
	Script              string   // relative path, e.g. "kernel/optimize.sh"
	Components          []string // sub-components or nil for standalone
	Label               string   // display name in menu
	Description         string   // short description
	Category            string   // "optimization" or "installation"
	Subsection          string   // grouping within category (e.g. "Shell", "Dev Tools")
	OS                  string   // "all", "linux", "darwin"
	Families            []string // "all", "debian", "redhat", "arch", "darwin"
	Requires            []string // "linux", "systemd", "native-linux", "native-or-wsl2", "wsl", "wsl2", "wslg"
	EntryKind           EntryKind
	RunIndividually     bool // do not merge with modules that share the same script
	Kind                ModuleKind
	DependsOn           []string
	Activates           []string
	ManualSteps         []string
	AffectedPaths       []string // important paths changed by install/update
	DestructivePaths    []string // paths that an explicit purge may delete
	NeedsRelogin        bool
	Privilege           PrivilegePolicy
	PrivilegeReason     string
	SupportedOperations []Operation
	Delivery            DeliveryPolicy
	Verify              Check
	Phase               Phase
	Order               int
}

type PrivilegeNeed struct {
	ModuleID string
	Label    string
	Reason   string
}

var legacyModuleAliases = map[string]string{
	"arch-git":    "git",
	"shell-git":   "git",
	"arch-mihomo": "mihomo",
}

// CanonicalModuleID preserves CLI and automation compatibility when a
// platform-specific module is folded into one stable cross-platform ID.
func CanonicalModuleID(id string) string {
	if canonical, ok := legacyModuleAliases[id]; ok {
		return canonical
	}
	return id
}

// AllModules returns the full registry, unfiltered.
func AllModules() []Module {
	items := []Module{
		// ── Optimizations ──
		{ID: "kernel-sysctl", Script: "kernel/optimize.sh", Components: []string{"sysctl"}, Label: "内核 ▸ sysctl.d", Description: "BBR/FQ、TCP/UDP、conntrack、内存调优", Category: "optimization", OS: "linux", Requires: []string{"native-linux"}, Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/sysctl.d 并执行 sysctl", AffectedPaths: []string{"/etc/sysctl.d/99-os-init.conf"}, Verify: FileContains("/etc/sysctl.d/99-os-init.conf", "tcp_mtu_probing"), Phase: PhaseSystem, Order: 10},
		{ID: "kernel-limits", Script: "kernel/optimize.sh", Components: []string{"limits"}, Label: "内核 ▸ limits.d", Description: "文件句柄、进程数、systemd 默认限制", Category: "optimization", OS: "linux", Requires: []string{"native-linux"}, Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/security 和 systemd drop-in", AffectedPaths: []string{"/etc/security/limits.d/99-os-init.conf", "/etc/pam.d/*", "/etc/systemd/*.conf.d/99-os-init.conf"}, Verify: FileContains("/etc/security/limits.d/99-os-init.conf", "1048576"), Phase: PhaseSystem, Order: 20},
		{ID: "kernel-scheduler", Script: "kernel/optimize.sh", Components: []string{"scheduler"}, Label: "内核 ▸ I/O 调度器", Description: "SSD/NVMe 使用 none", Category: "optimization", OS: "linux", Requires: []string{"native-linux"}, Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/udev/rules.d", Verify: Path("/etc/udev/rules.d/60-scheduler.rules"), Phase: PhaseSystem, Order: 30},
		{ID: "kernel-autotune", Script: "kernel/optimize.sh", Components: []string{"autotune"}, Label: "内核 ▸ 自动调优", Description: "按内存动态调整 conntrack、缓冲区、file-max", Category: "optimization", OS: "linux", Requires: []string{"systemd", "native-linux"}, Kind: KindSystemTuning, Activates: []string{ActivationSystemd}, Privilege: PrivilegeSystem, PrivilegeReason: "安装 systemd 服务和 /usr/local/sbin 脚本", Verify: Path("/etc/systemd/system/autotune.service"), Phase: PhaseSystem, Order: 40},
		{ID: "network-ipv4", Script: "kernel/optimize.sh", Components: []string{"ipv4"}, Label: "网络 ▸ IPv4 优先", Description: "gai.conf 优先使用 IPv4 解析结果", Category: "optimization", OS: "linux", Requires: []string{"native-linux"}, Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "修改 /etc/gai.conf", Verify: FileContains("/etc/gai.conf", "os-init -- prefer IPv4"), Phase: PhaseNetwork, Order: 80},
		{ID: "network-tune", Script: "kernel/optimize.sh", Components: []string{"network"}, Label: "网络 ▸ 队列与 MSS", Description: "RPS/RSS 多核分发、ring buffer、MSS clamp", Category: "optimization", OS: "linux", Requires: []string{"systemd", "native-linux"}, Kind: KindSystemTuning, Activates: []string{ActivationSystemd}, Privilege: PrivilegeSystem, PrivilegeReason: "安装 systemd 服务并调整网卡/iptables 参数", Verify: Path("/etc/systemd/system/os-init-network-tune.service"), Phase: PhaseNetwork, Order: 90},

		// ── Installations / Shell ──
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}, Label: "zsh + oh-my-zsh", Description: "Powerlevel10k、命令建议与语法高亮", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 需要安装 zsh 并可能写入 /etc/shells", Verify: All(Command("zsh"), Path("$HOME/.oh-my-zsh"), Path("$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"), Path("$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"), Path("$HOME/.oh-my-zsh/custom/themes/powerlevel10k"), ZshBlock("oh-my-zsh"), FileContains("$HOME/.zshrc", "zsh-autosuggestions"), FileContains("$HOME/.zshrc", "zsh-syntax-highlighting")), Phase: PhaseShell, Order: 10},
		{ID: "shell-direnv", Script: "shell/install.sh", Components: []string{"direnv"}, Label: "direnv", Description: "目录级环境变量", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 direnv", Verify: All(Command("direnv"), ZshBlock("direnv")), Phase: PhaseShell, Order: 40},
		{ID: "git", Script: "shell/install.sh", Components: []string{"git"}, Label: "Git / GitHub", Description: "Git、LFS、用户配置；Arch 同时安装 GitHub CLI 和 OpenSSH", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindInstallOnly, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 Git 和 Git LFS", Verify: Command("git"), Phase: PhaseBootstrap, Order: 20},
		{ID: "shell-tmux", Script: "shell/install.sh", Components: []string{"tmux"}, Label: "tmux", Description: "终端复用器与基础配置", Category: "installation", Subsection: "Shell 工具", OS: "linux", Kind: KindInstallOnly, AffectedPaths: []string{"系统包 tmux", "$HOME/.tmux.conf"}, Privilege: PrivilegeSystem, PrivilegeReason: "通过系统包管理器安装 tmux", Verify: All(Command("tmux"), Path("$HOME/.tmux.conf")), Phase: PhaseShell, Order: 70},

		// ── Installations / Terminal ──
		{ID: "terminal-ncdu", Script: "terminal/install.sh", Components: []string{"ncdu"}, Label: "ncdu", Description: "磁盘占用分析", Category: "installation", Subsection: "终端工具", OS: "all", Kind: KindInstallOnly, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 ncdu", Verify: Command("ncdu"), Phase: PhaseTerminal, Order: 20},
		{ID: "yazi", Script: "yazi/install.sh", Label: "Yazi", Description: "终端文件管理器", Category: "installation", Subsection: "终端工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装二进制到 /usr/local/bin", AffectedPaths: []string{"/usr/local/bin/yazi", "$HOME/.config/yazi/ya.sh", "$HOME/.zshrc|.bashrc"}, DestructivePaths: []string{"$HOME/.config/yazi (仅 PURGE_CONFIG=1)"}, Verify: All(Command("yazi"), Path("$HOME/.config/yazi/ya.sh"), ShellBlock("yazi")), Phase: PhaseTerminal, Order: 30},

		// ── Arch Linux capabilities and presets ──
		archLinuxModule("arch-base", "base", "Arch 最小基础", "官方仓库中的下载、解压和诊断基础；不接管第三方软件源", KindInstallOnly, "curl"),
		archLinuxModule("arch-cli", "cli", "Arch 现代 CLI", "ripgrep、fzf、bat、eza、dust、bottom、procs 等命令行与排障工具", KindInstallOnly, "rg"),
		archLinuxModule("arch-aur", "aur", "AUR Helper", "优先从 archlinuxcn 安装 paru；保留已有 yay 作为兼容回退，不再重复安装两个 helper", KindInstallOnly, ""),
		archLinuxModule("arch-archlinuxcn", "archlinuxcn", "archlinuxcn 软件源", "配置软件源、keyring 和 mirrorlist", KindSystemTuning, ""),
		archLinuxModule("arch-dns", "dns", "Arch 系统 DNS", "systemd-resolved、NetworkManager 和国内 DNS 基线", KindSystemTuning, ""),
		archLinuxModule("arch-ops-toolkit", "ops-toolkit", "Ops Toolkit", "克隆运维脚本仓库并生成稳定命令入口", KindShellIntegration, "ops"),
		archLinuxModule("arch-fonts", "fonts", "Arch 字体环境", "中文、Emoji、Nerd Font、Monaco 和 fontconfig", KindInstallOnly, "fc-cache"),
		archLinuxModule("arch-desktop", "desktop", "Arch Hyprland 桌面", "Hyprland、SDDM、Fcitx5/Rime、浏览器、hyprdots 和虚拟机适配", KindSystemService, "Hyprland"),
		actionModule(archLinuxAction("arch-doctor", "doctor", "Arch 系统诊断", "检查 Arch 通用模块、网络、服务和桌面环境")),
		actionModule(archLinuxAction("arch-status", "status", "Arch 状态详情", "显示 Arch 通用能力的详细状态与建议")),
		presetModule(archPreset("arch-dev", "Arch 开发环境", "Arch 最小基础 + 现代 CLI + AUR Helper + archlinuxcn + DNS + Git + Ops Toolkit + mise + Neovim + Docker + 字体 + Zsh + tmux + Mihomo", archDevDependencies())),
		presetModule(archPreset("arch-workstation", "Arch 完整工作站", "Arch 开发环境 + Arch Hyprland 桌面", []string{"arch-dev", "arch-desktop"})),
		presetModule(orbStackArchPreset()),
		wslSystemdModule(),
		actionModule(wslDoctorAction()),
		presetModule(wslDevelopmentPreset()),

		// ── Installations / Network ──
		{ID: "mihomo", Script: "mihomo/install.sh", Label: "Mihomo + MetaCubeXD", Description: "平台原生或便携式 Mihomo、配置预检、systemd 服务和控制面板", Category: "installation", Subsection: "网络代理", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd", "native-linux"}, Kind: KindSystemService, Activates: []string{ActivationSystemd, ActivationShellProfile}, ManualSteps: []string{"替换订阅或提供 MIHOMO_CONFIG_SOURCE 后再启用服务"}, AffectedPaths: []string{"/usr/local/bin/mihomo", "/etc/mihomo", "/etc/systemd/system/mihomo.service", "/var/lib/mihomo"}, DestructivePaths: []string{"/etc/mihomo、/var/lib/mihomo (仅 PURGE_DATA=1)"}, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/mihomo、systemd 服务和系统二进制", Verify: All(Command("mihomo"), Path("/etc/mihomo/config.yaml"), SystemdService("mihomo.service"), ShellBlock("proxy-env")), Phase: PhaseService, Order: 20},

		// ── Installations / Dev Tools ──
		{ID: "docker", Script: "docker/install.sh", Label: "Docker", Description: "静态二进制、Compose 插件、daemon 配置", Category: "installation", Subsection: "开发工具", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd", "native-or-wsl2"}, Kind: KindSystemService, Activates: []string{ActivationSystemd, ActivationRelogin}, NeedsRelogin: true, AffectedPaths: []string{"/usr/local/bin/docker*", "/etc/docker/daemon.json", "/etc/systemd/system/docker.service", "/var/lib/os-init/ownership"}, DestructivePaths: []string{"/var/lib/docker、/var/lib/containerd (仅 PURGE_DATA=1)", "/etc/docker (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeSystem, PrivilegeReason: "安装系统二进制、写入 Docker systemd 服务和用户组", Verify: All(CommandRun("docker", "--version"), CommandRun("dockerd", "--version"), CommandRun("docker", "compose", "version"), SystemdService("docker.service"), SystemdService("containerd.service"), UserGroup("docker")), Phase: PhaseService, Order: 10},
		{ID: "dev-build-deps", Script: "devdeps/install.sh", Label: "开发运行时编译依赖", Description: "系统编译器、头文件和基础库；不安装系统 Go/Python", Category: "installation", Subsection: "开发工具", OS: "all", Kind: KindInstallOnly, Activates: []string{ActivationManual}, AffectedPaths: []string{"系统包：编译器、pkg-config、OpenSSL/zlib/libffi 等开发库"}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装开发头文件和编译工具", Verify: All(Command("cc"), Command("make")), Phase: PhaseBootstrap, Order: 40},
		{ID: "mise", Script: "mise/install.sh", Components: []string{"core"}, Label: "mise", Description: "用户级开发运行时管理器、镜像配置和 Shell 激活", Category: "installation", Subsection: "开发工具", OS: "all", RunIndividually: true, Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, AffectedPaths: []string{"Homebrew/pacman 软件包，或 $HOME/.local/bin/mise", "$HOME/.config/mise/config.toml", "$HOME/.config/os-init/mise-china.env", "$HOME/.zprofile|.profile|.zshrc|.bashrc"}, DestructivePaths: []string{"$HOME/.config/mise、$HOME/.local/share/mise (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeArchSystem, PrivilegeReason: "Arch Linux 通过 pacman 安装 mise；运行时始终写入目标用户 HOME", Verify: All(Any(Command("mise"), Path("$HOME/.local/bin/mise")), Path("$HOME/.config/os-init/mise-china.env"), ZshBlock("mise"), ShellBlock("mise")), Phase: PhaseRuntime, Order: 10},
		{ID: "mise-go", Script: "mise/install.sh", Components: []string{"go"}, Label: "Go（mise 用户运行时）", Description: "由 mise 管理的用户级 Go；普通用户和 root 各自隔离", Category: "installation", Subsection: "开发工具", OS: "all", RunIndividually: true, Kind: KindShellIntegration, DependsOn: []string{"mise", "dev-build-deps"}, AffectedPaths: []string{"$HOME/.config/mise/config.toml", "$HOME/.local/share/mise/installs/go"}, DestructivePaths: []string{"$HOME/.local/share/mise/installs/go"}, Verify: MiseToolExec("go", "go", "version"), Phase: PhaseRuntime, Order: 20},
		{ID: "mise-python", Script: "mise/install.sh", Components: []string{"python"}, Label: "Python（mise 用户运行时）", Description: "由 mise 管理的用户级 Python；保留系统自带 Python", Category: "installation", Subsection: "开发工具", OS: "all", RunIndividually: true, Kind: KindShellIntegration, DependsOn: []string{"mise", "dev-build-deps"}, AffectedPaths: []string{"$HOME/.config/mise/config.toml", "$HOME/.local/share/mise/installs/python"}, DestructivePaths: []string{"$HOME/.local/share/mise/installs/python"}, Verify: MiseToolExec("python", "python", "--version"), Phase: PhaseRuntime, Order: 30},
		{ID: "mise-node", Script: "mise/install.sh", Components: []string{"node"}, Label: "Node.js（mise 用户运行时）", Description: "由 mise 管理的用户级 Node.js 与 Corepack", Category: "installation", Subsection: "开发工具", OS: "all", RunIndividually: true, Kind: KindShellIntegration, DependsOn: []string{"mise"}, AffectedPaths: []string{"$HOME/.config/mise/config.toml", "$HOME/.local/share/mise/installs/node"}, DestructivePaths: []string{"$HOME/.local/share/mise/installs/node"}, Verify: All(MiseToolExec("node", "node", "--version"), MiseToolExec("node", "npm", "--version"), MiseToolExec("node", "corepack", "--version")), Phase: PhaseRuntime, Order: 40},
		presetModule(Preset{ID: "mise-dev-runtimes", Label: "mise 开发运行时", Description: "用户级 Go、Python 和 Node.js；普通用户与 root 分别安装到自己的 HOME", Subsection: "开发工具", OS: "all", Includes: []string{"mise-go", "mise-python", "mise-node"}, Phase: PhaseRuntime, Order: 5}),
		{ID: "neovim", Script: "neovim/install.sh", Label: "Neovim + Neovide + config-yuan", Description: "终端编辑器、macOS 图形客户端和个人配置", Category: "installation", Subsection: "开发工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, AffectedPaths: []string{"Homebrew/pacman 软件包，或 Linux /opt/nvim-*、/usr/local/bin/nvim", "/Applications/Neovide.app (macOS)", "$HOME/.config/nvim", "$HOME/.config/neovide/config.toml"}, DestructivePaths: []string{"$HOME/.config/nvim、$HOME/.config/neovide/config.toml、$HOME/.local/share/nvim (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装二进制到 /opt 和 /usr/local/bin", Verify: All(Command("nvim"), Path("$HOME/.config/nvim/init.lua"), OnGOOS("darwin", Path("/Applications/Neovide.app")), OnGOOS("darwin", Path("$HOME/.config/neovide/config.toml")), ShellBlock("neovim")), Phase: PhaseApplication, Order: 20},
	}
	items = append(items, macOSCatalogModules()...)
	for i := range items {
		items[i] = applyDeclaredLifecycle(items[i])
		items[i] = applyDeclaredDelivery(items[i])
		items[i] = normalizeModule(items[i])
	}
	return items
}

// DeliveryFor returns the effective payload delivery strategy for a target.
func (m Module) DeliveryFor(target platform.Target) DeliveryKind {
	if target.Family == platform.FamilyDarwin && m.Delivery.Darwin != "" {
		return m.Delivery.Darwin
	}
	if target.Family == platform.FamilyArch && m.Delivery.Arch != "" {
		return m.Delivery.Arch
	}
	return m.Delivery.Default
}

func actionModule(action Action) Module {
	return Module{
		ID: action.ID, Script: action.Script, Components: action.Components,
		Label: action.Label, Description: action.Description, Category: "installation",
		Subsection: action.Subsection, OS: action.OS, Families: action.Families,
		Requires:  action.Requires,
		EntryKind: EntryAction, RunIndividually: true, Privilege: action.Privilege,
		SupportedOperations: []Operation{OperationInstall}, Phase: action.Phase, Order: action.Order,
	}
}

func presetModule(preset Preset) Module {
	return Module{
		ID: preset.ID, Label: preset.Label, Description: preset.Description,
		Category: "installation", Subsection: preset.Subsection, OS: preset.OS,
		Families: preset.Families, Requires: preset.Requires, EntryKind: EntryPreset, DependsOn: preset.Includes,
		SupportedOperations: []Operation{OperationInstall}, Phase: preset.Phase, Order: preset.Order,
	}
}

func normalizeModule(module Module) Module {
	if module.EntryKind == "" {
		module.EntryKind = EntryModule
	}
	if module.Phase == 0 {
		module.Phase = PhaseApplication
	}
	return module
}

func PrivilegeNeeds(selected []Module, target platform.Target) []PrivilegeNeed {
	needs := make([]PrivilegeNeed, 0)
	for _, m := range selected {
		if !moduleMatchesTarget(m, target) || !moduleNeedsPrivilege(m, target) {
			continue
		}
		reason := m.PrivilegeReason
		if reason == "" {
			reason = "需要修改系统级配置或安装系统级组件"
		}
		needs = append(needs, PrivilegeNeed{
			ModuleID: m.ID,
			Label:    m.Label,
			Reason:   reason,
		})
	}
	return needs
}

func SelectionNeedsPrivilege(selected []Module, target platform.Target) bool {
	return len(PrivilegeNeeds(selected, target)) > 0
}

// ForOS returns modules matching the given OS.
func ForOS(goos string) []Module {
	return ForTarget(platform.Target{
		GOOS:   goos,
		Family: familyForGOOS(goos),
		Init:   "unknown",
	})
}

// ForTarget returns modules matching the detected operating system target.
func ForTarget(target platform.Target) []Module {
	all := AllModules()
	filtered := make([]Module, 0, len(all))
	for _, m := range all {
		if moduleMatchesTarget(m, target) {
			if target.Family == platform.FamilyArch {
				switch m.ID {
				case "mihomo":
					m = archMihomoVariant(m)
				case "git":
					m.Delivery = DeliveryPolicy{Default: DeliveryArchNative}
					m.Verify = All(CommandRun("git", "--version"), CommandRun("gh", "--version"))
				}
			}
			if target.Environment == platform.EnvironmentWSL && m.ID == "docker" {
				m.Label = "Docker（WSL 原生 Engine）"
				m.Description = "由当前 WSL2 Linux 发行版独立管理的 dockerd、containerd 和 Compose"
				m.ManualSteps = append(m.ManualSteps, "不要为当前发行版启用 Docker Desktop WSL Integration")
			}
			filtered = append(filtered, m)
		}
	}
	return filtered
}

func moduleMatchesTarget(m Module, target platform.Target) bool {
	goos := normalizedGOOS(target)
	if goos != "linux" && goos != "darwin" {
		return false
	}
	if m.OS != "" && m.OS != "all" && m.OS != goos {
		return false
	}
	if len(m.Families) > 0 && !familyMatches(m.Families, target.Family) {
		return false
	}
	for _, requirement := range m.Requires {
		switch requirement {
		case "linux":
			if goos != "linux" {
				return false
			}
		case "systemd":
			if target.Init != "systemd" {
				return false
			}
		case "native-linux":
			if goos != "linux" || (target.Environment != "" && target.Environment != platform.EnvironmentNative) {
				return false
			}
		case "native-or-wsl2":
			if target.Environment == platform.EnvironmentWSL && target.WSLVersion != 2 {
				return false
			}
		case "wsl":
			if target.Environment != platform.EnvironmentWSL {
				return false
			}
		case "wsl2":
			if target.Environment != platform.EnvironmentWSL || target.WSLVersion != 2 {
				return false
			}
		case "wslg":
			if target.Environment != platform.EnvironmentWSL || !target.WSLg {
				return false
			}
		case "orbstack":
			if target.Environment != platform.EnvironmentOrbStack {
				return false
			}
		}
	}
	return true
}

func moduleNeedsPrivilege(m Module, target platform.Target) bool {
	switch m.Privilege {
	case PrivilegeSystem:
		return true
	case PrivilegeLinuxSystem:
		return normalizedGOOS(target) == "linux"
	case PrivilegeMacOSAdmin:
		return normalizedGOOS(target) == "darwin"
	case PrivilegeArchSystem:
		return target.Family == platform.FamilyArch
	default:
		return false
	}
}

func normalizedGOOS(target platform.Target) string {
	if target.GOOS != "" {
		return target.GOOS
	}
	switch target.Family {
	case platform.FamilyDarwin:
		return "darwin"
	case platform.FamilyArch, platform.FamilyDebian, platform.FamilyRedHat:
		return "linux"
	default:
		return ""
	}
}

func familyMatches(families []string, family platform.Family) bool {
	for _, item := range families {
		if item == "all" || item == string(family) {
			return true
		}
	}
	return false
}

func familyForGOOS(goos string) platform.Family {
	if goos == "darwin" {
		return platform.FamilyDarwin
	}
	return platform.FamilyUnknown
}

// NeedsUserInfo returns true if any module in the selection requires the GitInfo screen.
func NeedsUserInfo(selected []Module) bool {
	for _, m := range selected {
		if m.ID == "git" {
			return true
		}
	}
	return false
}

// NeedsWebhook returns true if any selected module needs a webhook URL.
func NeedsWebhook(selected []Module) bool {
	return false
}

// InstallSubsections returns the ordered list of subsection names for installations.
func InstallSubsections() []string {
	return []string{
		"Shell 工具",
		"终端体验",
		"终端工具",
		"macOS 开发应用",
		"macOS 代理网络",
		"macOS 效率工具",
		"macOS 输入增强",
		"macOS 媒体下载",
		"macOS AI 笔记",
		"macOS 通讯办公",
		"macOS 字体",
		"macOS 命令行",
		"网络代理",
		"开发工具",
		"Arch Linux 能力",
		"Arch Linux 开发",
		"Arch Linux 套餐",
		"Arch Linux 操作",
	}
}

// SupportsOperation reports whether an entry can participate in an operation.
func (m Module) SupportsOperation(operation Operation) bool {
	for _, supported := range m.SupportedOperations {
		if supported == operation {
			return true
		}
	}
	return false
}

// PrimaryCommand returns the first command suitable for a lightweight version
// display. Verification remains authoritative for installed state.
func (m Module) PrimaryCommand() string {
	return primaryCommand(m.Verify)
}

// MiseToolExec first proves that mise resolves the requested managed tool,
// then runs a command in that environment. This prevents a system Python or
// Go on PATH from being mistaken for a mise-managed runtime.
func MiseToolExec(tool string, args ...string) Check {
	command := `home="$HOME"; [ -n "$home" ] || exit 1; cd "$home" || exit 1; unset MISE_CONFIG_FILE MISE_TRUSTED_CONFIG_PATHS MISE_NODE_VERSION MISE_PYTHON_VERSION MISE_GO_VERSION; export HOME="$home" XDG_CONFIG_HOME="$home/.config" MISE_CONFIG_DIR="$home/.config/mise" MISE_GLOBAL_CONFIG_FILE="$home/.config/mise/config.toml" MISE_DATA_DIR="$home/.local/share/mise" MISE_CEILING_PATHS="$home"; if command -v mise >/dev/null 2>&1; then m=mise; elif [ -x "$home/.local/bin/mise" ]; then m="$home/.local/bin/mise"; else exit 127; fi; "$m" which "$1" >/dev/null 2>&1 || exit 1; shift; exec "$m" exec -- "$@"`
	values := []string{"sh", "-c", command, "mise-runtime", tool}
	values = append(values, args...)
	return CommandRun(values...)
}

func primaryCommand(check Check) string {
	if check.Kind == CheckCommand && len(check.Values) > 0 {
		return check.Values[0]
	}
	for _, child := range check.All {
		if command := primaryCommand(child); command != "" {
			return command
		}
	}
	for _, child := range check.Any {
		if command := primaryCommand(child); command != "" {
			return command
		}
	}
	return ""
}

// ResolveForContext applies target-user policy outside the TUI layer.
func ResolveForContext(mods []Module, root bool) []Module {
	resolved := make([]Module, 0, len(mods))
	for _, mod := range mods {
		if root && mod.ID == "docker" {
			mod.NeedsRelogin = false
			activations := make([]string, 0, len(mod.Activates))
			for _, activation := range mod.Activates {
				if activation != ActivationRelogin {
					activations = append(activations, activation)
				}
			}
			mod.Activates = activations
			mod.Verify = withoutCheckKind(mod.Verify, CheckUserGroup)
		}
		resolved = append(resolved, mod)
	}
	return resolved
}

func withoutCheckKind(check Check, kind CheckKind) Check {
	if check.Kind == kind {
		return Check{}
	}
	if len(check.All) > 0 {
		check.All = compactChecks(mapChecks(check.All, func(item Check) Check { return withoutCheckKind(item, kind) }))
	}
	if len(check.Any) > 0 {
		check.Any = compactChecks(mapChecks(check.Any, func(item Check) Check { return withoutCheckKind(item, kind) }))
	}
	return check
}

func mapChecks(checks []Check, transform func(Check) Check) []Check {
	out := make([]Check, 0, len(checks))
	for _, check := range checks {
		out = append(out, transform(check))
	}
	return out
}

// ScriptGroup represents a single script invocation with merged components.
type ScriptGroup struct {
	Script       string
	Components   []string
	Label        string
	Privilege    PrivilegePolicy
	ModuleIDs    []string
	ModuleLabels []string
}

// GroupByScript merges selected modules that share the same script path.
func GroupByScript(selected []Module) []ScriptGroup {
	seen := map[string]int{}
	var groups []ScriptGroup

	for _, m := range selected {
		if m.RunIndividually {
			groups = append(groups, ScriptGroup{
				Script:       m.Script,
				Components:   appendUnique(nil, m.Components...),
				Label:        m.Label,
				Privilege:    m.Privilege,
				ModuleIDs:    []string{m.ID},
				ModuleLabels: []string{m.Label},
			})
			continue
		}
		key := m.Script
		if idx, ok := seen[key]; ok && len(m.Components) > 0 {
			groups[idx].Components = appendUnique(groups[idx].Components, m.Components...)
			groups[idx].Privilege = mergePrivilege(groups[idx].Privilege, m.Privilege)
			groups[idx].ModuleIDs = append(groups[idx].ModuleIDs, m.ID)
			groups[idx].ModuleLabels = append(groups[idx].ModuleLabels, m.Label)
		} else {
			seen[key] = len(groups)
			groups = append(groups, ScriptGroup{
				Script:       m.Script,
				Components:   appendUnique(nil, m.Components...),
				Label:        m.Label,
				Privilege:    m.Privilege,
				ModuleIDs:    []string{m.ID},
				ModuleLabels: []string{m.Label},
			})
		}
	}
	return groups
}

func mergePrivilege(current, next PrivilegePolicy) PrivilegePolicy {
	if current == PrivilegeSystem || next == PrivilegeSystem {
		return PrivilegeSystem
	}
	if current == PrivilegeLinuxSystem || next == PrivilegeLinuxSystem {
		return PrivilegeLinuxSystem
	}
	if current == PrivilegeMacOSAdmin || next == PrivilegeMacOSAdmin {
		return PrivilegeMacOSAdmin
	}
	if current == PrivilegeArchSystem || next == PrivilegeArchSystem {
		return PrivilegeArchSystem
	}
	return PrivilegeNone
}

func appendUnique(values []string, candidates ...string) []string {
	for _, candidate := range candidates {
		if candidate == "" || contains(values, candidate) {
			continue
		}
		values = append(values, candidate)
	}
	return values
}

func contains(values []string, needle string) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

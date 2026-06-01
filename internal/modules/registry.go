package modules

import "github.com/fanhuadesenlinnn/os-init/internal/platform"

// Module describes a selectable item in the TUI menu.
type Module struct {
	ID                string   // unique key, e.g. "kernel-sysctl"
	Script            string   // relative path, e.g. "kernel/optimize.sh"
	Components        []string // sub-components or nil for standalone
	Label             string   // display name in menu
	Description       string   // short description
	Category          string   // "optimization" or "installation"
	Subsection        string   // grouping within category (e.g. "Shell", "Dev Tools")
	OS                string   // "all", "linux", "darwin"
	Families          []string // "all", "debian", "redhat", "arch", "darwin"
	Requires          []string // "linux", "systemd"
	Tags              []string // "server", "dev", "cn-ready"
	NeedsSudo         bool     // invoke with sudo bash
	InstalledCmd      string   // command to check if installed (empty = no check)
	InstalledCheck    string   // file path to check if exists (empty = no check)
	InstalledGrepFile string   // "filepath:pattern" — check if file contains pattern
}

// AllModules returns the full registry, unfiltered.
func AllModules() []Module {
	return []Module{
		// ── Optimizations ──
		{ID: "kernel-sysctl", Script: "kernel/optimize.sh", Components: []string{"sysctl"}, Label: "内核 ▸ sysctl.d", Description: "网络、内存、conntrack 调优", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/sysctl.d/99-os-init.conf:bbr"},
		{ID: "kernel-limits", Script: "kernel/optimize.sh", Components: []string{"limits"}, Label: "内核 ▸ limits.d", Description: "文件句柄和进程数限制", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/security/limits.d/99-os-init.conf:2097152"},
		{ID: "kernel-scheduler", Script: "kernel/optimize.sh", Components: []string{"scheduler"}, Label: "内核 ▸ I/O 调度器", Description: "SSD/NVMe 使用 none", Category: "optimization", OS: "linux", InstalledCheck: "/etc/udev/rules.d/60-scheduler.rules"},
		{ID: "kernel-autotune", Script: "kernel/optimize.sh", Components: []string{"autotune"}, Label: "内核 ▸ 自动调优", Description: "按内存自动生成启动调优", Category: "optimization", OS: "linux", InstalledCheck: "/etc/systemd/system/autotune.service"},
		{ID: "sshd", Script: "sshd/setup.sh", Label: "SSH ▸ sshd 加固", Description: "禁用密码登录并验证配置", Category: "optimization", OS: "linux", InstalledCmd: "sshd"},

		// ── Installations / Shell ──
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}, Label: "zsh + oh-my-zsh", Description: "交互式 Shell 环境", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "zsh"},
		{ID: "shell-fzf", Script: "shell/install.sh", Components: []string{"fzf"}, Label: "fzf", Description: "模糊查找工具", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "fzf"},
		{ID: "shell-starship", Script: "shell/install.sh", Components: []string{"starship"}, Label: "starship 提示符", Description: "跨 Shell 提示符", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "starship"},
		{ID: "shell-direnv", Script: "shell/install.sh", Components: []string{"direnv"}, Label: "direnv", Description: "目录级环境变量", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "direnv"},
		{ID: "shell-autosuggestions", Script: "shell/install.sh", Components: []string{"plugins"}, Label: "zsh-autosuggestions", Description: "命令历史建议", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"},
		{ID: "shell-syntax-hl", Script: "shell/install.sh", Components: []string{"plugins"}, Label: "zsh-syntax-highlighting", Description: "命令语法高亮", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"},
		{ID: "shell-nvm", Script: "shell/install.sh", Components: []string{"nvm"}, Label: "nvm", Description: "Node 版本管理", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCheck: "$HOME/.nvm/nvm.sh"},
		{ID: "shell-fnm", Script: "shell/install.sh", Components: []string{"fnm"}, Label: "fnm", Description: "快速 Node 版本管理", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "fnm"},
		{ID: "shell-git", Script: "shell/install.sh", Components: []string{"git"}, Label: "Git 配置", Description: "LFS、SSH-over-HTTPS、模板配置", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "git"},
		{ID: "shell-byobu", Script: "shell/install.sh", Components: []string{"byobu"}, Label: "byobu + tmux", Description: "终端复用器", Category: "installation", Subsection: "Shell 工具", OS: "linux", InstalledCmd: "byobu"},

		// ── Installations / Terminal ──
		{ID: "terminal-ncdu", Script: "terminal/install.sh", Components: []string{"ncdu"}, Label: "ncdu", Description: "磁盘占用分析", Category: "installation", Subsection: "终端工具", OS: "all", InstalledCmd: "ncdu"},
		{ID: "yazi", Script: "yazi/install.sh", Label: "Yazi", Description: "终端文件管理器", Category: "installation", Subsection: "终端工具", OS: "all", InstalledCmd: "yazi"},

		// ── Installations / Network ──
		{ID: "mihomo", Script: "mihomo/install.sh", Label: "Mihomo", Description: "代理核心、配置测试、MetaCubeXD 面板", Category: "installation", Subsection: "网络代理", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, InstalledCmd: "mihomo"},

		// ── Installations / Dev Tools ──
		{ID: "docker", Script: "docker/install.sh", Label: "Docker", Description: "静态二进制、Compose 插件、daemon 配置", Category: "installation", Subsection: "开发工具", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, InstalledCmd: "docker"},
		{ID: "go", Script: "go/install.sh", Label: "Go", Description: "Go 语言工具链", Category: "installation", Subsection: "开发工具", OS: "all", InstalledCmd: "go"},
		{ID: "neovim", Script: "neovim/install.sh", Label: "Neovim + LazyVim", Description: "带 IDE 能力的编辑器", Category: "installation", Subsection: "开发工具", OS: "all", InstalledCmd: "nvim"},
	}
}

// ForOS returns modules matching the given OS ("linux" or "darwin").
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
			filtered = append(filtered, m)
		}
	}
	return filtered
}

func moduleMatchesTarget(m Module, target platform.Target) bool {
	goos := normalizedGOOS(target)
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
		}
	}
	return true
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
		if m.ID == "shell-git" {
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
	return []string{"Shell 工具", "终端工具", "网络代理", "开发工具"}
}

// ScriptGroup represents a single script invocation with merged components.
type ScriptGroup struct {
	Script     string
	Components []string
	Label      string
	NeedsSudo  bool
	ModuleIDs  []string
}

// GroupByScript merges selected modules that share the same script path.
func GroupByScript(selected []Module) []ScriptGroup {
	seen := map[string]int{}
	var groups []ScriptGroup

	for _, m := range selected {
		key := m.Script
		if idx, ok := seen[key]; ok && len(m.Components) > 0 {
			groups[idx].Components = append(groups[idx].Components, m.Components...)
			groups[idx].ModuleIDs = append(groups[idx].ModuleIDs, m.ID)
		} else {
			seen[key] = len(groups)
			groups = append(groups, ScriptGroup{
				Script:     m.Script,
				Components: append([]string{}, m.Components...),
				Label:      m.Label,
				NeedsSudo:  m.NeedsSudo,
				ModuleIDs:  []string{m.ID},
			})
		}
	}
	return groups
}

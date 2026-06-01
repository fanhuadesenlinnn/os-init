package modules

import "github.com/dpanic/os-kickstart/internal/platform"

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
		{ID: "kernel-sysctl", Script: "kernel/optimize.sh", Components: []string{"sysctl"}, Label: "Kernel ▸ sysctl.conf", Description: "network, memory, conntrack tuning", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/sysctl.conf:bbr"},
		{ID: "kernel-limits", Script: "kernel/optimize.sh", Components: []string{"limits"}, Label: "Kernel ▸ limits", Description: "file descriptor & process limits", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/security/limits.conf:2097152"},
		{ID: "kernel-scheduler", Script: "kernel/optimize.sh", Components: []string{"scheduler"}, Label: "Kernel ▸ I/O scheduler", Description: "none (SSD/NVMe)", Category: "optimization", OS: "linux", InstalledCheck: "/etc/udev/rules.d/60-scheduler.rules"},
		{ID: "kernel-autotune", Script: "kernel/optimize.sh", Components: []string{"autotune"}, Label: "Kernel ▸ autotune", Description: "RAM-based autotune service", Category: "optimization", OS: "linux", InstalledCheck: "/etc/systemd/system/autotune.service"},
		{ID: "sshd", Script: "sshd/setup.sh", Label: "SSH ▸ sshd hardening", Description: "disables password auth", Category: "optimization", OS: "linux", InstalledCmd: "sshd"},

		// ── Installations / Shell ──
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}, Label: "zsh + oh-my-zsh", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "zsh"},
		{ID: "shell-fzf", Script: "shell/install.sh", Components: []string{"fzf"}, Label: "fzf", Description: "fuzzy finder", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "fzf"},
		{ID: "shell-starship", Script: "shell/install.sh", Components: []string{"starship"}, Label: "starship prompt", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "starship"},
		{ID: "shell-direnv", Script: "shell/install.sh", Components: []string{"direnv"}, Label: "direnv", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "direnv"},
		{ID: "shell-autosuggestions", Script: "shell/install.sh", Components: []string{"plugins"}, Label: "zsh-autosuggestions", Category: "installation", Subsection: "Shell", OS: "all", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"},
		{ID: "shell-syntax-hl", Script: "shell/install.sh", Components: []string{"plugins"}, Label: "zsh-syntax-highlighting", Category: "installation", Subsection: "Shell", OS: "all", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"},
		{ID: "shell-nvm", Script: "shell/install.sh", Components: []string{"nvm"}, Label: "nvm", Description: "Node version manager", Category: "installation", Subsection: "Shell", OS: "all", InstalledCheck: "$HOME/.nvm/nvm.sh"},
		{ID: "shell-fnm", Script: "shell/install.sh", Components: []string{"fnm"}, Label: "fnm", Description: "Fast Node Manager", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "fnm"},
		{ID: "shell-git", Script: "shell/install.sh", Components: []string{"git"}, Label: "git config", Description: "LFS, SSH-over-HTTPS", Category: "installation", Subsection: "Shell", OS: "all", InstalledCmd: "git"},
		{ID: "shell-byobu", Script: "shell/install.sh", Components: []string{"byobu"}, Label: "byobu + tmux", Category: "installation", Subsection: "Shell", OS: "linux", InstalledCmd: "byobu"},

		// ── Installations / Terminal ──
		{ID: "terminal-ncdu", Script: "terminal/install.sh", Components: []string{"ncdu"}, Label: "ncdu", Description: "disk analyzer", Category: "installation", Subsection: "Terminal", OS: "all", InstalledCmd: "ncdu"},
		{ID: "yazi", Script: "yazi/install.sh", Label: "Yazi", Description: "terminal file manager", Category: "installation", Subsection: "Terminal", OS: "all", InstalledCmd: "yazi"},

		// ── Installations / Dev Tools ──
		{ID: "docker", Script: "docker/install.sh", Label: "Docker", Description: "engine, compose, buildx, daemon config", Category: "installation", Subsection: "Dev Tools", OS: "all", InstalledCmd: "docker"},
		{ID: "go", Script: "go/install.sh", Label: "Go", Description: "programming language from go.dev", Category: "installation", Subsection: "Dev Tools", OS: "all", InstalledCmd: "go"},
		{ID: "neovim", Script: "neovim/install.sh", Label: "Neovim + LazyVim", Description: "editor with IDE features", Category: "installation", Subsection: "Dev Tools", OS: "all", InstalledCmd: "nvim"},
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
	return []string{"Shell", "Terminal", "Dev Tools"}
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

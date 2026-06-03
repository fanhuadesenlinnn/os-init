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
		{ID: "kernel-sysctl", Script: "kernel/optimize.sh", Components: []string{"sysctl"}, Label: "内核 ▸ sysctl.d", Description: "BBR/FQ、TCP/UDP、conntrack、内存调优", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/sysctl.d/99-os-init.conf:tcp_mtu_probing"},
		{ID: "kernel-limits", Script: "kernel/optimize.sh", Components: []string{"limits"}, Label: "内核 ▸ limits.d", Description: "文件句柄、进程数、systemd 默认限制", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/security/limits.d/99-os-init.conf:1048576"},
		{ID: "kernel-scheduler", Script: "kernel/optimize.sh", Components: []string{"scheduler"}, Label: "内核 ▸ I/O 调度器", Description: "SSD/NVMe 使用 none", Category: "optimization", OS: "linux", InstalledCheck: "/etc/udev/rules.d/60-scheduler.rules"},
		{ID: "kernel-autotune", Script: "kernel/optimize.sh", Components: []string{"autotune"}, Label: "内核 ▸ 自动调优", Description: "按内存动态调整 conntrack、缓冲区、file-max", Category: "optimization", OS: "linux", Requires: []string{"systemd"}, InstalledCheck: "/etc/systemd/system/autotune.service"},
		{ID: "network-ipv4", Script: "kernel/optimize.sh", Components: []string{"ipv4"}, Label: "网络 ▸ IPv4 优先", Description: "gai.conf 优先使用 IPv4 解析结果", Category: "optimization", OS: "linux", InstalledGrepFile: "/etc/gai.conf:os-init -- prefer IPv4"},
		{ID: "network-tune", Script: "kernel/optimize.sh", Components: []string{"network"}, Label: "网络 ▸ 队列与 MSS", Description: "RPS/RSS 多核分发、ring buffer、MSS clamp", Category: "optimization", OS: "linux", Requires: []string{"systemd"}, InstalledCheck: "/etc/systemd/system/os-init-network-tune.service"},

		// ── Installations / Shell ──
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}, Label: "zsh + oh-my-zsh", Description: "交互式 Shell 环境", Category: "installation", Subsection: "Shell 工具", OS: "all", InstalledCmd: "zsh"},
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

		// ── Installations / macOS Apps ──
		macOSCask("macOS 开发应用", "google-chrome", "Google Chrome", "浏览器", "/Applications/Google Chrome.app"),
		macOSCask("macOS 开发应用", "codex", "Codex", "OpenAI Codex 桌面端", "/Applications/Codex.app"),
		macOSCask("macOS 开发应用", "orbstack", "OrbStack", "Docker Desktop 替代、容器和 Linux 机器", "/Applications/OrbStack.app"),
		macOSCask("macOS 开发应用", "visual-studio-code", "Visual Studio Code", "代码编辑器", "/Applications/Visual Studio Code.app"),
		macOSCask("macOS 开发应用", "iterm2", "iTerm2", "macOS 终端模拟器", "/Applications/iTerm.app"),
		macOSCask("macOS 开发应用", "ghostty", "Ghostty", "GPU 加速终端模拟器", "/Applications/Ghostty.app"),
		macOSCask("macOS 开发应用", "sublime-text", "Sublime Text", "轻量代码编辑器", "/Applications/Sublime Text.app"),
		macOSCask("macOS 开发应用", "neovide-app", "Neovide", "Neovim 图形客户端", "/Applications/Neovide.app"),

		macOSCask("macOS 代理网络", "clash-verge-rev", "Clash Verge Rev", "基于 Mihomo/Clash Meta 的代理 GUI", "/Applications/Clash Verge.app"),
		macOSCask("macOS 代理网络", "clash-party", "Clash Party", "Mihomo/Clash 代理 GUI", "/Applications/Clash Party.app"),
		macOSCask("macOS 代理网络", "royal-tsx", "Royal TSX", "远程连接管理器", "/Applications/Royal TSX.app"),
		macOSCask("macOS 代理网络", "seafile-client", "Seafile Client", "文件同步客户端", "/Applications/Seafile Client.app"),

		macOSCask("macOS 效率工具", "pixpin", "PixPin", "截图和标注工具", "/Applications/PixPin.app"),
		macOSCask("macOS 效率工具", "bob", "Bob", "翻译和 OCR 工具", "/Applications/Bob.app"),
		macOSCask("macOS 效率工具", "loop", "Loop", "窗口管理工具", "/Applications/Loop.app"),
		macOSCask("macOS 效率工具", "jordanbaird-ice", "Ice", "菜单栏管理工具", "/Applications/Ice.app"),
		macOSCask("macOS 效率工具", "stats", "Stats", "菜单栏系统监控", "/Applications/Stats.app"),
		macOSCask("macOS 效率工具", "monitorcontrol", "MonitorControl", "外接显示器亮度和音量控制", "/Applications/MonitorControl.app"),
		macOSCask("macOS 效率工具", "mos", "Mos", "鼠标滚动优化", "/Applications/Mos.app"),
		macOSCask("macOS 效率工具", "input-source-pro", "Input Source Pro", "输入法自动切换", "/Applications/Input Source Pro.app"),
		macOSCask("macOS 效率工具", "menubarx", "MenubarX", "菜单栏浏览器", "/Applications/MenubarX.app"),

		macOSCask("macOS 输入增强", "karabiner-elements", "Karabiner-Elements", "键盘映射工具", "/Applications/Karabiner-Elements.app"),
		macOSCask("macOS 输入增强", "aldente", "AlDente", "电池充电管理", "/Applications/AlDente.app"),
		macOSCask("macOS 输入增强", "keka", "Keka", "压缩解压工具", "/Applications/Keka.app"),

		macOSCask("macOS 媒体下载", "iina", "IINA", "视频播放器", "/Applications/IINA.app"),
		macOSCask("macOS 媒体下载", "downie", "Downie 4", "视频下载工具", "/Applications/Downie 4.app"),
		macOSCask("macOS 媒体下载", "motrix", "Motrix", "下载工具", "/Applications/Motrix.app"),
		macOSCask("macOS 媒体下载", "spotify", "Spotify", "音乐客户端", "/Applications/Spotify.app"),
		macOSCask("macOS 媒体下载", "steam", "Steam", "游戏平台", "/Applications/Steam.app"),
		macOSCask("macOS 媒体下载", "qqlive", "腾讯视频", "视频客户端", "/Applications/QQLive.app"),

		macOSCask("macOS AI 笔记", "chatgpt", "ChatGPT", "ChatGPT 桌面端", "/Applications/ChatGPT.app"),
		macOSCask("macOS AI 笔记", "cherry-studio", "Cherry Studio", "AI 客户端", "/Applications/Cherry Studio.app"),
		macOSCask("macOS AI 笔记", "siyuan", "SiYuan", "本地优先笔记工具", "/Applications/SiYuan.app"),

		macOSCask("macOS 通讯办公", "wechat", "微信", "即时通讯", "/Applications/WeChat.app"),
		macOSCask("macOS 通讯办公", "telegram", "Telegram", "即时通讯", "/Applications/Telegram.app"),
		macOSCask("macOS 通讯办公", "tencent-meeting", "腾讯会议", "会议客户端", "/Applications/TencentMeeting.app"),
		macOSCask("macOS 通讯办公", "wpsoffice", "WPS Office", "办公套件", "/Applications/wpsoffice.app"),
		macOSCask("macOS 通讯办公", "bitwarden", "Bitwarden", "密码管理器", "/Applications/Bitwarden.app"),
		macOSCask("macOS 通讯办公", "cleanmymac", "CleanMyMac X", "系统清理工具", "/Applications/CleanMyMac-X.app"),
		macOSCask("macOS 通讯办公", "cc-switch", "CC Switch", "菜单栏开关工具", "/Applications/CC Switch.app"),

		macOSCask("macOS 字体", "font-hack-nerd-font", "Hack Nerd Font", "Nerd Font 字体", ""),
		macOSCask("macOS 字体", "font-jetbrains-mono-nerd-font", "JetBrains Mono Nerd Font", "Nerd Font 字体", ""),
		macOSCask("macOS 字体", "font-maple-mono-nf", "Maple Mono NF", "Nerd Font 字体", ""),

		macOSFormula("bat", "bat", "cat 替代工具", "bat"),
		macOSFormula("eza", "eza", "ls 替代工具", "eza"),
		macOSFormula("ripgrep", "ripgrep", "高速文本搜索", "rg"),
		macOSFormula("fd", "fd", "find 替代工具", "fd"),
		macOSFormula("fzf", "fzf", "命令行模糊查找", "fzf"),
		macOSFormula("gh", "GitHub CLI", "GitHub 命令行工具", "gh"),
		macOSFormula("htop", "htop", "进程监控", "htop"),
		macOSFormula("iftop", "iftop", "网络流量监控", "iftop"),
		macOSFormula("jq", "jq", "JSON 处理工具", "jq"),
		macOSFormula("mise", "mise", "多语言运行时管理", "mise"),
		macOSFormula("nmap", "nmap", "网络扫描工具", "nmap"),
		macOSFormula("nushell", "Nushell", "结构化 shell", "nu"),
		macOSFormula("rsync", "rsync", "文件同步工具", ""),
		macOSFormula("shellcheck", "ShellCheck", "Shell 静态检查", "shellcheck"),
		macOSFormula("tmux", "tmux", "终端复用器", "tmux"),
		macOSFormula("uv", "uv", "Python 包和项目管理", "uv"),
		macOSFormula("wget", "wget", "命令行下载工具", "wget"),
		macOSFormula("zoxide", "zoxide", "智能目录跳转", "zoxide"),
		macOSFormula("ffmpeg", "FFmpeg", "音视频处理", "ffmpeg"),
		macOSFormula("imagemagick", "ImageMagick", "图片处理", "magick"),
		macOSFormula("gallery-dl", "gallery-dl", "图库下载工具", "gallery-dl"),
		macOSFormula("yt-dlp", "yt-dlp", "视频下载工具", "yt-dlp"),
		macOSFormula("stylua", "StyLua", "Lua 格式化工具", "stylua"),
		macOSFormula("tree-sitter-cli", "tree-sitter CLI", "tree-sitter 命令行工具", "tree-sitter"),
		macOSFormula("nload", "nload", "网络流量监控", "nload"),
		macOSFormula("bind", "BIND DNS tools", "DNS 工具集", ""),
		macOSFormula("herdr", "herdr", "命令行工具", "herdr"),
		macOSFormula("llmfit", "llmfit", "命令行工具", "llmfit"),

		// ── Installations / Network ──
		{ID: "mihomo", Script: "mihomo/install.sh", Label: "Mihomo", Description: "代理核心、配置测试、MetaCubeXD 面板", Category: "installation", Subsection: "网络代理", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, InstalledCmd: "mihomo"},

		// ── Installations / Dev Tools ──
		{ID: "docker", Script: "docker/install.sh", Label: "Docker", Description: "静态二进制、Compose 插件、daemon 配置", Category: "installation", Subsection: "开发工具", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, InstalledCmd: "docker"},
		{ID: "go", Script: "go/install.sh", Label: "Go", Description: "Go 语言工具链", Category: "installation", Subsection: "开发工具", OS: "all", InstalledCmd: "go"},
		{ID: "neovim", Script: "neovim/install.sh", Label: "Neovim + LazyVim", Description: "带 IDE 能力的编辑器", Category: "installation", Subsection: "开发工具", OS: "all", InstalledCmd: "nvim"},
	}
}

func macOSCask(subsection, component, label, description, installedCheck string) Module {
	return Module{
		ID:             "macos-" + component,
		Script:         "macos/install.sh",
		Components:     []string{component},
		Label:          label,
		Description:    description,
		Category:       "installation",
		Subsection:     subsection,
		OS:             "darwin",
		InstalledCheck: installedCheck,
	}
}

func macOSFormula(component, label, description, installedCmd string) Module {
	return Module{
		ID:           "macos-cli-" + component,
		Script:       "macos/cli.sh",
		Components:   []string{component},
		Label:        label,
		Description:  description,
		Category:     "installation",
		Subsection:   "macOS 命令行",
		OS:           "darwin",
		InstalledCmd: installedCmd,
	}
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
	return []string{
		"Shell 工具",
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
	}
}

// ScriptGroup represents a single script invocation with merged components.
type ScriptGroup struct {
	Script       string
	Components   []string
	Label        string
	NeedsSudo    bool
	ModuleIDs    []string
	ModuleLabels []string
}

// GroupByScript merges selected modules that share the same script path.
func GroupByScript(selected []Module) []ScriptGroup {
	seen := map[string]int{}
	var groups []ScriptGroup

	for _, m := range selected {
		key := m.Script
		if idx, ok := seen[key]; ok && len(m.Components) > 0 {
			groups[idx].Components = appendUnique(groups[idx].Components, m.Components...)
			groups[idx].ModuleIDs = append(groups[idx].ModuleIDs, m.ID)
			groups[idx].ModuleLabels = append(groups[idx].ModuleLabels, m.Label)
		} else {
			seen[key] = len(groups)
			groups = append(groups, ScriptGroup{
				Script:       m.Script,
				Components:   appendUnique(nil, m.Components...),
				Label:        m.Label,
				NeedsSudo:    m.NeedsSudo,
				ModuleIDs:    []string{m.ID},
				ModuleLabels: []string{m.Label},
			})
		}
	}
	return groups
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

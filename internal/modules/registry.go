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
)

const (
	ActivationZshrc        = "zshrc"
	ActivationShellProfile = "shell-profile"
	ActivationSystemd      = "systemd"
	ActivationManual       = "manual"
	ActivationRelogin      = "relogin"
)

// Module describes a selectable item in the TUI menu.
type Module struct {
	ID                        string   // unique key, e.g. "kernel-sysctl"
	Script                    string   // relative path, e.g. "kernel/optimize.sh"
	Components                []string // sub-components or nil for standalone
	Label                     string   // display name in menu
	Description               string   // short description
	Category                  string   // "optimization" or "installation"
	Subsection                string   // grouping within category (e.g. "Shell", "Dev Tools")
	OS                        string   // "all", "linux", "darwin"
	Families                  []string // "all", "debian", "redhat", "arch", "darwin"
	Requires                  []string // "linux", "systemd"
	Tags                      []string // "server", "dev", "cn-ready"
	NeedsSudo                 bool     // invoke with sudo bash
	RunIndividually           bool     // do not merge with modules that share the same script
	RootOnly                  bool     // expose only when root is the target user
	Kind                      ModuleKind
	DependsOn                 []string
	Activates                 []string
	ManualSteps               []string
	AffectedPaths             []string // important paths changed by install/update
	DestructivePaths          []string // paths that an explicit purge may delete
	NeedsRelogin              bool
	Privilege                 PrivilegePolicy
	PrivilegeReason           string
	InstalledCmd              string // command to check if installed (empty = no check)
	InstalledCommands         [][]string
	InstalledAnyCommands      [][]string
	InstalledCheck            string // file path to check if exists (empty = no check)
	InstalledChecks           []string
	InstalledAnyChecks        []string
	InstalledGrepFile         string // "filepath:pattern" — check if file contains pattern
	InstalledGrepFiles        []string
	InstalledBrewCask         string
	InstalledBrewFormula      string
	InstalledMacOSBrewFormula string
	InstalledMacOSChecks      []string
	InstalledLinuxChecks      []string
	InstalledZshBlocks        []string
	InstalledShellBlocks      []string
	InstalledSystemdServices  []string
	InstalledUserGroups       []string
}

type PrivilegeNeed struct {
	ModuleID string
	Label    string
	Reason   string
}

// AllModules returns the full registry, unfiltered.
func AllModules() []Module {
	return []Module{
		// ── Optimizations ──
		{ID: "kernel-sysctl", Script: "kernel/optimize.sh", Components: []string{"sysctl"}, Label: "内核 ▸ sysctl.d", Description: "BBR/FQ、TCP/UDP、conntrack、内存调优", Category: "optimization", OS: "linux", Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/sysctl.d 并执行 sysctl", AffectedPaths: []string{"/etc/sysctl.d/99-os-init.conf"}, InstalledGrepFile: "/etc/sysctl.d/99-os-init.conf:tcp_mtu_probing"},
		{ID: "kernel-limits", Script: "kernel/optimize.sh", Components: []string{"limits"}, Label: "内核 ▸ limits.d", Description: "文件句柄、进程数、systemd 默认限制", Category: "optimization", OS: "linux", Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/security 和 systemd drop-in", AffectedPaths: []string{"/etc/security/limits.d/99-os-init.conf", "/etc/pam.d/*", "/etc/systemd/*.conf.d/99-os-init.conf"}, InstalledGrepFile: "/etc/security/limits.d/99-os-init.conf:1048576"},
		{ID: "kernel-scheduler", Script: "kernel/optimize.sh", Components: []string{"scheduler"}, Label: "内核 ▸ I/O 调度器", Description: "SSD/NVMe 使用 none", Category: "optimization", OS: "linux", Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/udev/rules.d", InstalledCheck: "/etc/udev/rules.d/60-scheduler.rules"},
		{ID: "kernel-autotune", Script: "kernel/optimize.sh", Components: []string{"autotune"}, Label: "内核 ▸ 自动调优", Description: "按内存动态调整 conntrack、缓冲区、file-max", Category: "optimization", OS: "linux", Requires: []string{"systemd"}, Kind: KindSystemTuning, Activates: []string{ActivationSystemd}, Privilege: PrivilegeSystem, PrivilegeReason: "安装 systemd 服务和 /usr/local/sbin 脚本", InstalledCheck: "/etc/systemd/system/autotune.service"},
		{ID: "network-ipv4", Script: "kernel/optimize.sh", Components: []string{"ipv4"}, Label: "网络 ▸ IPv4 优先", Description: "gai.conf 优先使用 IPv4 解析结果", Category: "optimization", OS: "linux", Kind: KindSystemTuning, Privilege: PrivilegeSystem, PrivilegeReason: "修改 /etc/gai.conf", InstalledGrepFile: "/etc/gai.conf:os-init -- prefer IPv4"},
		{ID: "network-tune", Script: "kernel/optimize.sh", Components: []string{"network"}, Label: "网络 ▸ 队列与 MSS", Description: "RPS/RSS 多核分发、ring buffer、MSS clamp", Category: "optimization", OS: "linux", Requires: []string{"systemd"}, Kind: KindSystemTuning, Activates: []string{ActivationSystemd}, Privilege: PrivilegeSystem, PrivilegeReason: "安装 systemd 服务并调整网卡/iptables 参数", InstalledCheck: "/etc/systemd/system/os-init-network-tune.service"},

		// ── Installations / Shell ──
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}, Label: "zsh + oh-my-zsh", Description: "交互式 Shell 环境", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 需要安装 zsh 并可能写入 /etc/shells", InstalledCmd: "zsh", InstalledCheck: "$HOME/.oh-my-zsh", InstalledChecks: []string{"$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions", "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting", "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"}, InstalledZshBlocks: []string{"oh-my-zsh"}},
		{ID: "shell-starship", Script: "shell/install.sh", Components: []string{"starship"}, Label: "starship 提示符", Description: "bash/zsh 跨 Shell 提示符", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装脚本默认写入系统二进制目录", InstalledCmd: "starship", InstalledShellBlocks: []string{"starship"}},
		{ID: "shell-direnv", Script: "shell/install.sh", Components: []string{"direnv"}, Label: "direnv", Description: "目录级环境变量", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 direnv", InstalledCmd: "direnv", InstalledZshBlocks: []string{"direnv"}},
		{ID: "shell-autosuggestions", Script: "shell/install.sh", Components: []string{"autosuggestions"}, Label: "zsh-autosuggestions", Description: "命令历史建议", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, DependsOn: []string{"shell-zsh"}, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 可能需要先安装 zsh", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions", InstalledZshBlocks: []string{"oh-my-zsh"}, InstalledGrepFile: "$HOME/.zshrc:zsh-autosuggestions"},
		{ID: "shell-syntax-hl", Script: "shell/install.sh", Components: []string{"syntax-highlighting"}, Label: "zsh-syntax-highlighting", Description: "命令语法高亮", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindShellIntegration, DependsOn: []string{"shell-zsh"}, Activates: []string{ActivationZshrc}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 可能需要先安装 zsh", InstalledCheck: "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting", InstalledZshBlocks: []string{"oh-my-zsh"}, InstalledGrepFile: "$HOME/.zshrc:zsh-syntax-highlighting"},
		{ID: "shell-git", Script: "shell/install.sh", Components: []string{"git"}, Label: "Git 配置", Description: "LFS、SSH-over-HTTPS、模板配置", Category: "installation", Subsection: "Shell 工具", OS: "all", Kind: KindInstallOnly, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 git-lfs", InstalledCmd: "git"},
		{ID: "shell-byobu", Script: "shell/install.sh", Components: []string{"byobu"}, Label: "byobu + tmux", Description: "终端复用器", Category: "installation", Subsection: "Shell 工具", OS: "linux", Kind: KindInstallOnly, Privilege: PrivilegeSystem, PrivilegeReason: "通过系统包管理器安装 byobu/tmux", InstalledCmd: "byobu"},

		// ── Installations / Terminal ──
		{ID: "terminal-style", Script: "terminal/style.sh", Components: []string{"style"}, Label: "终端样式", Description: "本地 rich、SSH simple、TTY plain 自动切换", Category: "installation", Subsection: "终端体验", OS: "all", Kind: KindShellIntegration, DependsOn: []string{"shell-starship"}, Activates: []string{ActivationShellProfile}, ManualSteps: []string{"SSH 会自动使用 simple 提示符，TTY 会自动使用 plain 提示符"}, InstalledCmd: "starship", InstalledCheck: "$HOME/.config/os-init/terminal/starship-rich.toml", InstalledShellBlocks: []string{"terminal-style", "starship"}},
		{ID: "terminal-ncdu", Script: "terminal/install.sh", Components: []string{"ncdu"}, Label: "ncdu", Description: "磁盘占用分析", Category: "installation", Subsection: "终端工具", OS: "all", Kind: KindInstallOnly, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 通过系统包管理器安装 ncdu", InstalledCmd: "ncdu"},
		{ID: "yazi", Script: "yazi/install.sh", Label: "Yazi", Description: "终端文件管理器", Category: "installation", Subsection: "终端工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装二进制到 /usr/local/bin", AffectedPaths: []string{"/usr/local/bin/yazi", "$HOME/.config/yazi/ya.sh", "$HOME/.zshrc|.bashrc"}, DestructivePaths: []string{"$HOME/.config/yazi (仅 PURGE_CONFIG=1)"}, InstalledCmd: "yazi", InstalledCheck: "$HOME/.config/yazi/ya.sh", InstalledShellBlocks: []string{"yazi"}},

		// ── ArchDevKit ──
		archDevKitMenu(),
		archDevKitAction("status", "状态检查", "查看 ArchDevKit 模块状态和建议动作"),
		archDevKitAction("doctor", "诊断", "运行 ArchDevKit doctor 诊断"),
		archDevKitAction("config-init", "初始化配置", "创建 ~/.config/archdevkit/config.env"),
		archDevKitAction("config-show", "查看配置", "显示当前 ArchDevKit 配置"),
		archDevKitAction("config-validate", "校验配置", "校验 ArchDevKit 配置文件"),
		archDevKitAction("reset-state", "重置状态记录", "清理 ArchDevKit 状态记录，不卸载系统软件"),

		// ── Installations / macOS Apps ──
		macOSCask("macOS 开发应用", "google-chrome", "Google Chrome", "浏览器", "/Applications/Google Chrome.app"),
		macOSCask("macOS 开发应用", "codex", "Codex", "OpenAI Codex 桌面端", "/Applications/Codex.app"),
		macOSCask("macOS 开发应用", "orbstack", "OrbStack", "Docker Desktop 替代、容器和 Linux 机器", "/Applications/OrbStack.app"),
		macOSCask("macOS 开发应用", "visual-studio-code", "Visual Studio Code", "代码编辑器", "/Applications/Visual Studio Code.app"),
		macOSCask("macOS 开发应用", "iterm2", "iTerm2", "macOS 终端模拟器", "/Applications/iTerm.app"),
		macOSCask("macOS 开发应用", "ghostty", "Ghostty", "GPU 加速终端模拟器", "/Applications/Ghostty.app"),
		macOSCask("macOS 开发应用", "sublime-text", "Sublime Text", "轻量代码编辑器", "/Applications/Sublime Text.app"),

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
		macOSCask("macOS 输入增强", "squirrel-app", "Squirrel", "Rime 中文输入法", "/Library/Input Methods/Squirrel.app"),
		macOSCask("macOS 输入增强", "aldente", "AlDente", "电池充电管理", "/Applications/AlDente.app"),
		macOSCask("macOS 输入增强", "keka", "Keka", "压缩解压工具", "/Applications/Keka.app"),

		macOSCask("macOS 媒体下载", "iina", "IINA", "视频播放器", "/Applications/IINA.app"),
		macOSCask("macOS 媒体下载", "downie", "Downie 4", "视频下载工具", "/Applications/Downie 4.app"),
		macOSCask("macOS 媒体下载", "motrix-next", "Motrix Next", "现代化下载管理器", "/Applications/MotrixNext.app"),
		macOSCask("macOS 媒体下载", "spotify", "Spotify", "音乐客户端", "/Applications/Spotify.app"),
		macOSCask("macOS 媒体下载", "steam", "Steam", "游戏平台", "/Applications/Steam.app"),
		macOSCask("macOS 媒体下载", "qqlive", "腾讯视频", "视频客户端", "/Applications/QQLive.app"),

		macOSCask("macOS AI 笔记", "chatgpt", "ChatGPT", "ChatGPT 桌面端", "/Applications/ChatGPT.app"),
		macOSCask("macOS AI 笔记", "lm-studio", "LM Studio", "本地大语言模型运行与管理", "/Applications/LM Studio.app"),
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
		{ID: "mihomo", Script: "mihomo/install.sh", Label: "Mihomo", Description: "代理核心、配置测试、MetaCubeXD 面板", Category: "installation", Subsection: "网络代理", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, Kind: KindSystemService, Activates: []string{ActivationSystemd, ActivationShellProfile}, ManualSteps: []string{"替换订阅或提供 MIHOMO_CONFIG_SOURCE 后再启用服务"}, AffectedPaths: []string{"/usr/local/bin/mihomo", "/etc/mihomo", "/etc/systemd/system/mihomo.service", "/var/lib/mihomo"}, DestructivePaths: []string{"/etc/mihomo、/var/lib/mihomo (仅 PURGE_DATA=1)"}, Privilege: PrivilegeSystem, PrivilegeReason: "写入 /etc/mihomo、systemd 服务和系统二进制", InstalledCmd: "mihomo", InstalledCheck: "/etc/mihomo/config.yaml", InstalledSystemdServices: []string{"mihomo.service"}, InstalledShellBlocks: []string{"proxy-env"}},

		// ── Installations / Dev Tools ──
		{ID: "docker", Script: "docker/install.sh", Label: "Docker", Description: "静态二进制、Compose 插件、daemon 配置", Category: "installation", Subsection: "开发工具", OS: "linux", Families: []string{"arch", "debian", "redhat"}, Requires: []string{"systemd"}, Kind: KindSystemService, Activates: []string{ActivationSystemd, ActivationRelogin}, NeedsRelogin: true, AffectedPaths: []string{"/usr/local/bin/docker*", "/etc/docker/daemon.json", "/etc/systemd/system/docker.service", "/var/lib/os-init/ownership"}, DestructivePaths: []string{"/var/lib/docker、/var/lib/containerd (仅 PURGE_DATA=1)", "/etc/docker (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeSystem, PrivilegeReason: "安装系统二进制、写入 Docker systemd 服务和用户组", InstalledCommands: [][]string{{"docker", "--version"}, {"dockerd", "--version"}, {"docker", "compose", "version"}}, InstalledSystemdServices: []string{"docker.service", "containerd.service"}, InstalledUserGroups: []string{"docker"}},
		{ID: "arch-root-mise", Script: "mise/install.sh", Label: "mise + Node.js 24 + Python 3.13 + Go 1.24", Description: "root 运行时、国内镜像和 Shell 激活", Category: "installation", Subsection: "开发工具", OS: "linux", Families: []string{"arch"}, RootOnly: true, RunIndividually: true, Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, AffectedPaths: []string{"pacman 软件包 mise", "$HOME/.config/mise/config.toml", "$HOME/.config/os-init/mise-china.env", "$HOME/.local/share/mise", "$HOME/.zprofile|.profile|.zshrc|.bashrc"}, DestructivePaths: []string{"$HOME/.config/mise/config.toml、$HOME/.local/share/mise (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeSystem, PrivilegeReason: "Arch Linux 通过 pacman 安装 mise，并为 root 管理运行时", InstalledCmd: "mise", InstalledCommands: [][]string{{"mise", "exec", "--", "node", "--version"}, {"mise", "exec", "--", "python", "--version"}, {"mise", "exec", "--", "go", "version"}}, InstalledCheck: "$HOME/.config/os-init/mise-china.env", InstalledZshBlocks: []string{"mise"}, InstalledShellBlocks: []string{"mise"}},
		{ID: "go", Script: "go/install.sh", Label: "Go", Description: "Go 语言工具链", Category: "installation", Subsection: "开发工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, AffectedPaths: []string{"Homebrew/pacman 软件包，或 Linux /usr/local/go", "$HOME/.zshrc|.bashrc", "OS Init 所有权状态目录"}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装或更新 /usr/local/go", InstalledAnyCommands: [][]string{{"go", "version"}, {"/usr/local/go/bin/go", "version"}}, InstalledShellBlocks: []string{"go"}},
		{ID: "neovim", Script: "neovim/install.sh", Label: "Neovim + Neovide + config-yuan", Description: "终端编辑器、macOS 图形客户端和个人配置", Category: "installation", Subsection: "开发工具", OS: "all", Kind: KindShellIntegration, Activates: []string{ActivationShellProfile}, AffectedPaths: []string{"Homebrew/pacman 软件包，或 Linux /opt/nvim-*、/usr/local/bin/nvim", "/Applications/Neovide.app (macOS)", "$HOME/.config/nvim", "$HOME/.config/neovide/config.toml"}, DestructivePaths: []string{"$HOME/.config/nvim、$HOME/.config/neovide/config.toml、$HOME/.local/share/nvim (仅 PURGE_CONFIG=1)"}, Privilege: PrivilegeLinuxSystem, PrivilegeReason: "Linux 安装二进制到 /opt 和 /usr/local/bin", InstalledCmd: "nvim", InstalledCheck: "$HOME/.config/nvim/init.lua", InstalledMacOSChecks: []string{"/Applications/Neovide.app", "$HOME/.config/neovide/config.toml"}, InstalledShellBlocks: []string{"neovim"}},
	}
}

func archDevKitMenu() Module {
	return Module{
		ID:              "archdevkit-menu",
		Script:          "archdevkit/run.sh",
		Components:      []string{"menu"},
		Label:           "原版交互菜单",
		Description:     "按 ArchDevKit 原版流程选择安装目标和安装选项",
		Category:        "archdevkit",
		OS:              "linux",
		Families:        []string{"arch"},
		Kind:            KindSystemService,
		Privilege:       PrivilegeSystem,
		PrivilegeReason: "ArchDevKit 会通过 pacman、systemd 或用户 shell/桌面配置修改 Arch 系统",
		ManualSteps:     []string{"ArchDevKit 保留独立配置和状态：~/.config/archdevkit/config.env、~/.local/state/archdevkit"},
	}
}

// ArchDevKitInstallModule returns a runnable module for an ArchDevKit install target.
func ArchDevKitInstallModule(component string) (Module, bool) {
	switch component {
	case "base":
		return archDevKitInstall("base", "基础环境", "基础工具、排障工具、现代 CLI、tmux、AUR helper", KindInstallOnly, "rg"), true
	case "archlinuxcn":
		return archDevKitInstall("archlinuxcn", "archlinuxcn 软件源", "配置 archlinuxcn 源、keyring 和 mirrorlist", KindSystemTuning, ""), true
	case "dns":
		return archDevKitInstall("dns", "系统 DNS", "systemd-resolved、NetworkManager DNS 后端、国内 DNS 基线", KindSystemTuning, ""), true
	case "git":
		return archDevKitInstall("git", "Git / GitHub CLI", "git、gh、openssh 和基础 Git 配置", KindInstallOnly, "gh"), true
	case "ops-toolkit":
		return archDevKitInstall("ops-toolkit", "Ops Toolkit", "克隆运维脚本仓库并生成稳定命令入口", KindShellIntegration, "ops"), true
	case "runtime":
		return archDevKitInstall("runtime", "Runtime / mise", "mise 管理 Node 24、Python 3.13、Go 1.24 和国内镜像", KindShellIntegration, "mise"), true
	case "nvim":
		return archDevKitInstall("nvim", "Neovim", "Neovim 和个人配置", KindShellIntegration, "nvim"), true
	case "docker":
		return archDevKitInstall("docker", "Docker / Compose", "pacman 安装 Docker/Compose、镜像源、服务和用户组", KindSystemService, "docker"), true
	case "fonts":
		return archDevKitInstall("fonts", "字体环境", "中文字体、Emoji、Nerd Font、Monaco 和 fontconfig", KindInstallOnly, "fc-cache"), true
	case "shell":
		return archDevKitInstall("shell", "Zsh / Oh My Zsh / Starship", "Zsh、Oh My Zsh、Starship 终端样式、插件和默认 shell", KindShellIntegration, "zsh"), true
	case "proxy":
		return archDevKitInstall("proxy", "Proxy 代理环境", "Mihomo 或 sing-box、MetaCubeXD、shell 代理模板", KindSystemService, ""), true
	case "desktop":
		return archDevKitInstall("desktop", "Hyprland 桌面环境", "Hyprland、SDDM、Fcitx5/Rime、浏览器、终端和 hyprdots", KindSystemService, "Hyprland"), true
	case "dev":
		return archDevKitInstall("dev", "开发环境套餐", "base + archlinuxcn + dns + git + ops-toolkit + runtime + nvim + docker + fonts + shell + proxy", KindSystemService, ""), true
	case "workstation":
		return archDevKitInstall("workstation", "完整工作站套餐", "dev + Hyprland 桌面", KindSystemService, ""), true
	default:
		return Module{}, false
	}
}

func macOSCask(subsection, component, label, description, installedCheck string) Module {
	return Module{
		ID:                "macos-" + component,
		Script:            "macos/install.sh",
		Components:        []string{component},
		Label:             label,
		Description:       description,
		Category:          "installation",
		Subsection:        subsection,
		OS:                "darwin",
		RunIndividually:   true,
		Kind:              KindInstallOnly,
		Activates:         caskActivations(component),
		ManualSteps:       caskManualSteps(component),
		InstalledCheck:    installedCheck,
		InstalledBrewCask: component,
		AffectedPaths:     []string{installedCheck},
	}
}

func archDevKitInstall(component, label, description string, kind ModuleKind, installedCmd string) Module {
	m := Module{
		ID:              "archdevkit-" + component,
		Script:          "archdevkit/run.sh",
		Components:      []string{component},
		Label:           label,
		Description:     description,
		Category:        "archdevkit",
		OS:              "linux",
		Families:        []string{"arch"},
		Kind:            kind,
		Privilege:       PrivilegeSystem,
		PrivilegeReason: "ArchDevKit 会通过 pacman、systemd 或用户 shell/桌面配置修改 Arch 系统",
		ManualSteps:     []string{"ArchDevKit 保留独立配置和状态：~/.config/archdevkit/config.env、~/.local/state/archdevkit"},
		InstalledCmd:    installedCmd,
	}

	switch component {
	case "archlinuxcn":
		m.InstalledGrepFile = "/etc/pacman.conf:[archlinuxcn]"
	case "dns":
		m.InstalledCheck = "/etc/systemd/resolved.conf.d/90-archdevkit-dns.conf"
		m.InstalledSystemdServices = []string{"systemd-resolved.service"}
	case "git":
		m.InstalledCommands = [][]string{{"git", "--version"}, {"gh", "--version"}}
	case "runtime":
		m.Activates = []string{ActivationShellProfile}
		m.InstalledCommands = [][]string{{"mise", "--version"}, {"node", "-v"}, {"npm", "-v"}, {"python", "--version"}, {"go", "version"}}
		m.InstalledCheck = "$HOME/.config/archdevkit/mise-china.env"
	case "docker":
		m.Activates = []string{ActivationSystemd, ActivationRelogin}
		m.NeedsRelogin = true
		m.InstalledCommands = [][]string{{"docker", "--version"}, {"docker", "compose", "version"}}
		m.InstalledSystemdServices = []string{"docker.service"}
		m.InstalledUserGroups = []string{"docker"}
	case "shell":
		m.Activates = []string{ActivationZshrc, ActivationRelogin}
		m.NeedsRelogin = true
		m.InstalledCheck = "$HOME/.oh-my-zsh"
	case "proxy":
		m.Activates = []string{ActivationSystemd, ActivationShellProfile}
		m.InstalledAnyCommands = [][]string{{"mihomo", "-v"}, {"sing-box", "version"}}
		m.InstalledAnyChecks = []string{"/etc/mihomo/config.yaml", "$HOME/.config/sing-box/config.json"}
	case "desktop":
		m.Activates = []string{ActivationSystemd, ActivationManual}
		m.ManualSteps = append(m.ManualSteps, "桌面模块会写入 Hyprland、Waybar、Rofi、Dunst、Yazi、GTK 等用户配置")
	case "dev", "workstation":
		m.Activates = []string{ActivationSystemd, ActivationShellProfile, ActivationRelogin}
		m.NeedsRelogin = true
	}

	return m
}

func archDevKitAction(component, label, description string) Module {
	return Module{
		ID:          "archdevkit-" + component,
		Script:      "archdevkit/run.sh",
		Components:  []string{component},
		Label:       label,
		Description: description,
		Category:    "archdevkit",
		OS:          "linux",
		Families:    []string{"arch"},
		Kind:        KindInstallOnly,
	}
}

func macOSFormula(component, label, description, installedCmd string) Module {
	kind := KindInstallOnly
	activates := []string(nil)
	zshBlocks := []string(nil)
	switch component {
	case "mise", "zoxide":
		kind = KindShellIntegration
		activates = []string{ActivationZshrc}
		zshBlocks = []string{component}
	}

	module := Module{
		ID:                   "macos-cli-" + component,
		Script:               "macos/cli.sh",
		Components:           []string{component},
		Label:                label,
		Description:          description,
		Category:             "installation",
		Subsection:           "macOS 命令行",
		OS:                   "darwin",
		RunIndividually:      true,
		Kind:                 kind,
		Activates:            activates,
		InstalledCmd:         installedCmd,
		InstalledBrewFormula: component,
		InstalledZshBlocks:   zshBlocks,
	}
	if component == "mise" {
		module.Activates = []string{ActivationShellProfile}
		module.InstalledCheck = "$HOME/.config/os-init/mise-china.env"
		module.InstalledCommands = [][]string{
			{"mise", "exec", "--", "node", "--version"},
			{"mise", "exec", "--", "python", "--version"},
			{"mise", "exec", "--", "go", "version"},
		}
	}
	return module
}

func caskActivations(component string) []string {
	switch component {
	case "orbstack", "clash-party", "royal-tsx", "seafile-client", "bitwarden", "motrix-next":
		return []string{ActivationManual}
	default:
		return nil
	}
}

func caskManualSteps(component string) []string {
	switch component {
	case "orbstack":
		return []string{"打开 OrbStack 完成首次初始化"}
	case "clash-party":
		return []string{"打开应用后导入自己的代理配置，不由 os-init 接管订阅和系统代理"}
	case "motrix-next":
		return []string{"Motrix Next 未签名；如 macOS 拒绝打开，请先核对上游说明再决定是否移除隔离属性"}
	case "royal-tsx":
		return []string{"打开 Royal TSX 后导入或创建自己的连接配置"}
	case "seafile-client":
		return []string{"打开 Seafile Client 后登录账号并选择同步目录"}
	case "bitwarden":
		return []string{"打开 Bitwarden 后登录账号或导入自己的密码库"}
	default:
		return nil
	}
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

func moduleNeedsPrivilege(m Module, target platform.Target) bool {
	switch m.Privilege {
	case PrivilegeSystem:
		return true
	case PrivilegeLinuxSystem:
		return normalizedGOOS(target) == "linux"
	case PrivilegeMacOSAdmin:
		return normalizedGOOS(target) == "darwin"
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
	}
}

// ScriptGroup represents a single script invocation with merged components.
type ScriptGroup struct {
	Script       string
	Components   []string
	Label        string
	NeedsSudo    bool
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
				NeedsSudo:    m.NeedsSudo,
				Privilege:    m.Privilege,
				ModuleIDs:    []string{m.ID},
				ModuleLabels: []string{m.Label},
			})
			continue
		}
		key := m.Script
		if idx, ok := seen[key]; ok && len(m.Components) > 0 {
			groups[idx].Components = appendUnique(groups[idx].Components, m.Components...)
			groups[idx].NeedsSudo = groups[idx].NeedsSudo || m.NeedsSudo
			groups[idx].Privilege = mergePrivilege(groups[idx].Privilege, m.Privilege)
			groups[idx].ModuleIDs = append(groups[idx].ModuleIDs, m.ID)
			groups[idx].ModuleLabels = append(groups[idx].ModuleLabels, m.Label)
		} else {
			seen[key] = len(groups)
			groups = append(groups, ScriptGroup{
				Script:       m.Script,
				Components:   appendUnique(nil, m.Components...),
				Label:        m.Label,
				NeedsSudo:    m.NeedsSudo,
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

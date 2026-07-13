package tui

import (
	"os"
	"strings"
	"unicode"
)

func langIsEnglish() bool {
	return strings.HasPrefix(strings.ToLower(os.Getenv("OS_INIT_LANG")), "en")
}

func text(zh, en string) string {
	if langIsEnglish() {
		return en
	}
	return zh
}

func moduleSection(label string) string {
	if !langIsEnglish() {
		return label
	}
	switch strings.TrimSpace(label) {
	case "系统优化":
		return "System Optimization"
	case "软件安装":
		return "Software Installation"
	case "Shell 工具":
		return "Shell Tools"
	case "终端体验":
		return "Terminal Experience"
	case "终端工具":
		return "Terminal Tools"
	case "macOS 开发应用":
		return "macOS Development Apps"
	case "macOS 代理网络":
		return "macOS Proxy & Network"
	case "macOS 效率工具":
		return "macOS Productivity"
	case "macOS 输入增强":
		return "macOS Input Enhancements"
	case "macOS 媒体下载":
		return "macOS Media & Download"
	case "macOS AI 笔记":
		return "macOS AI & Notes"
	case "macOS 通讯办公":
		return "macOS Communication & Office"
	case "macOS 字体":
		return "macOS Fonts"
	case "macOS 命令行":
		return "macOS CLI Tools"
	case "网络代理":
		return "Network Proxy"
	case "开发工具":
		return "Development Tools"
	case "Arch Linux 能力":
		return "Arch Linux Capabilities"
	case "Arch Linux 开发":
		return "Arch Linux Development"
	case "Arch Linux 套餐":
		return "Arch Linux Presets"
	default:
		return label
	}
}

func moduleLabel(id, fallback string) string {
	if !langIsEnglish() {
		return fallback
	}
	if value, ok := moduleLabelEN[id]; ok {
		return value
	}
	return fallback
}

func moduleDescription(id, fallback string) string {
	if !langIsEnglish() {
		return fallback
	}
	if value, ok := moduleDescriptionEN[id]; ok {
		return value
	}
	return fallback
}

func modulePrivilegeReason(id, fallback string) string {
	if !langIsEnglish() {
		return fallback
	}
	if value, ok := modulePrivilegeReasonEN[id]; ok {
		return value
	}
	if strings.HasPrefix(id, "arch-") {
		return "applies an Arch Linux capability through pacman, systemd, or target-user configuration"
	}
	return "requires system-level configuration or system-wide component installation"
}

func localizedMetadata(value string) string {
	if !langIsEnglish() {
		return value
	}
	replacer := strings.NewReplacer(
		"Homebrew/pacman 软件包，或 Linux ", "Homebrew/pacman packages, or Linux ",
		"OS Init 所有权状态目录", "OS Init ownership state directory",
		"、", ", ",
		"(仅 PURGE_DATA=1)", "(only with PURGE_DATA=1)",
		"(仅 PURGE_CONFIG=1)", "(only with PURGE_CONFIG=1)",
	)
	return replacer.Replace(value)
}

func containsHan(value string) bool {
	for _, r := range value {
		if unicode.Is(unicode.Han, r) {
			return true
		}
	}
	return false
}

// localizedExecutionLine keeps the English TUI readable even when a bundled or
// third-party installer emits a legacy Chinese diagnostic. The original output
// remains available in the per-run log file for troubleshooting.
func localizedExecutionLine(line string) string {
	if !langIsEnglish() || !containsHan(line) {
		return line
	}

	switch {
	case strings.Contains(line, "[Error]") || strings.Contains(line, "[错误]"):
		return "[Error] The module reported an error; see the run log for details"
	case strings.Contains(line, "[Warning]") || strings.Contains(line, "[警告]"):
		return "[Warning] The module reported a warning; see the run log for details"
	case strings.Contains(line, "[Skip]") || strings.Contains(line, "[跳过]"):
		return "[Skip] The module skipped this step; see the run log for details"
	case strings.Contains(line, "[Update]") || strings.Contains(line, "[更新]"):
		return "[Update] Updating module resources"
	case strings.Contains(line, "[Remove]") || strings.Contains(line, "[删除]"):
		return "[Remove] Removing module-managed resources"
	case strings.Contains(line, "[Install]") || strings.Contains(line, "[安装]"):
		return "[Install] Applying module changes"
	case strings.HasPrefix(strings.TrimSpace(line), "==="):
		return "=== Module operation ==="
	default:
		return "Module output is available in the run log"
	}
}

var modulePrivilegeReasonEN = map[string]string{
	"kernel-sysctl":         "writes /etc/sysctl.d and applies settings with sysctl",
	"kernel-limits":         "writes /etc/security and systemd drop-ins",
	"kernel-scheduler":      "writes /etc/udev/rules.d",
	"kernel-autotune":       "installs a systemd service and a /usr/local/sbin helper",
	"network-ipv4":          "modifies /etc/gai.conf",
	"network-tune":          "installs a systemd service and adjusts network and iptables settings",
	"shell-zsh":             "Linux may install zsh and update /etc/shells",
	"shell-starship":        "Linux installs the binary in a system-wide directory",
	"shell-direnv":          "Linux installs direnv through the system package manager",
	"shell-autosuggestions": "Linux may need to install zsh first",
	"shell-syntax-hl":       "Linux may need to install zsh first",
	"shell-git":             "Linux installs git-lfs through the system package manager",
	"shell-byobu":           "installs byobu and tmux through the system package manager",
	"terminal-ncdu":         "Linux installs ncdu through the system package manager",
	"yazi":                  "Linux installs binaries in /usr/local/bin",
	"mihomo":                "writes /etc/mihomo, a systemd service, and system-wide binaries",
	"docker":                "installs system-wide binaries and configures Docker services and the docker group",
	"arch-mise":             "installs mise through pacman and manages runtimes for the target user",
	"go":                    "Linux installs or updates /usr/local/go",
	"neovim":                "Linux installs binaries in /opt and /usr/local/bin",
}

var moduleLabelEN = map[string]string{
	"kernel-sysctl":         "Kernel - sysctl.d",
	"kernel-limits":         "Kernel - limits.d",
	"kernel-scheduler":      "Kernel - I/O scheduler",
	"kernel-autotune":       "Kernel - auto tuning",
	"network-ipv4":          "Network - prefer IPv4",
	"network-tune":          "Network - queues and MSS",
	"shell-zsh":             "zsh + oh-my-zsh",
	"shell-starship":        "starship prompt",
	"shell-direnv":          "direnv",
	"shell-autosuggestions": "zsh-autosuggestions",
	"shell-syntax-hl":       "zsh-syntax-highlighting",
	"shell-git":             "Git configuration",
	"shell-byobu":           "byobu + tmux",
	"terminal-style":        "Terminal style",
	"terminal-ncdu":         "ncdu",
	"yazi":                  "Yazi",
	"mihomo":                "Mihomo",
	"docker":                "Docker",
	"arch-mise":             "mise + Node.js 24 + Python 3.13 + Go 1.24",
	"arch-base":             "Arch base environment",
	"arch-aur":              "AUR Helper",
	"arch-archlinuxcn":      "archlinuxcn repository",
	"arch-dns":              "Arch system DNS",
	"arch-git":              "Arch Git / GitHub CLI",
	"arch-ops-toolkit":      "Ops Toolkit",
	"arch-fonts":            "Arch font environment",
	"arch-sing-box":         "sing-box",
	"arch-desktop":          "Arch Hyprland desktop",
	"arch-doctor":           "Arch system diagnostics",
	"arch-status":           "Arch detailed status",
	"arch-dev":              "Arch development environment",
	"arch-workstation":      "Arch complete workstation",
	"go":                    "Go",
	"neovim":                "Neovim + Neovide + config-yuan",
	"macos-wechat":          "WeChat",
	"macos-tencent-meeting": "Tencent Meeting",
	"macos-qqlive":          "Tencent Video",
}

var moduleDescriptionEN = map[string]string{
	"kernel-sysctl":                       "BBR/FQ, TCP/UDP, conntrack, and memory tuning",
	"kernel-limits":                       "File descriptors, process limits, and systemd defaults",
	"kernel-scheduler":                    "Use none for SSD/NVMe I/O scheduling",
	"kernel-autotune":                     "Tune conntrack, buffers, and file-max based on memory",
	"network-ipv4":                        "Prefer IPv4 resolver results through gai.conf",
	"network-tune":                        "RPS/RSS distribution, ring buffers, and MSS clamp",
	"shell-zsh":                           "Interactive shell environment",
	"shell-starship":                      "Cross-shell prompt for bash and zsh",
	"shell-direnv":                        "Per-directory environment variables",
	"shell-autosuggestions":               "Command history suggestions",
	"shell-syntax-hl":                     "Command syntax highlighting",
	"shell-git":                           "LFS, SSH-over-HTTPS, and template config",
	"shell-byobu":                         "Terminal multiplexer",
	"terminal-style":                      "Auto-select rich locally, simple over SSH, and plain on TTY",
	"terminal-ncdu":                       "Disk usage analyzer",
	"yazi":                                "Terminal file manager",
	"macos-google-chrome":                 "Browser",
	"macos-codex":                         "OpenAI Codex desktop app",
	"macos-orbstack":                      "Docker Desktop alternative for containers and Linux machines",
	"macos-visual-studio-code":            "Code editor",
	"macos-iterm2":                        "macOS terminal emulator",
	"macos-ghostty":                       "GPU-accelerated terminal emulator",
	"macos-sublime-text":                  "Lightweight code editor",
	"macos-clash-party":                   "Mihomo/Clash proxy GUI",
	"macos-royal-tsx":                     "Remote connection manager",
	"macos-seafile-client":                "File sync client",
	"macos-pixpin":                        "Screenshot and annotation tool",
	"macos-bob":                           "Translation and OCR tool",
	"macos-loop":                          "Window manager",
	"macos-jordanbaird-ice":               "Menu bar manager",
	"macos-stats":                         "Menu bar system monitor",
	"macos-monitorcontrol":                "External display brightness and volume control",
	"macos-mos":                           "Mouse scrolling optimizer",
	"macos-input-source-pro":              "Automatic input source switching",
	"macos-menubarx":                      "Menu bar browser",
	"macos-karabiner-elements":            "Keyboard remapping tool",
	"macos-squirrel-app":                  "Rime input method for Chinese",
	"macos-aldente":                       "Battery charging manager",
	"macos-keka":                          "Archive utility",
	"macos-iina":                          "Video player",
	"macos-downie":                        "Video downloader",
	"macos-motrix-next":                   "Modern download manager",
	"macos-spotify":                       "Music client",
	"macos-steam":                         "Game platform",
	"macos-qqlive":                        "Video client",
	"macos-chatgpt":                       "ChatGPT desktop app",
	"macos-lm-studio":                     "Run and manage local language models",
	"macos-cherry-studio":                 "AI client",
	"macos-siyuan":                        "Local-first notes app",
	"macos-wechat":                        "Instant messaging",
	"macos-telegram":                      "Instant messaging",
	"macos-tencent-meeting":               "Meeting client",
	"macos-wpsoffice":                     "Office suite",
	"macos-bitwarden":                     "Password manager",
	"macos-cleanmymac":                    "System cleanup tool",
	"macos-cc-switch":                     "Menu bar switch tool",
	"macos-font-hack-nerd-font":           "Nerd Font family",
	"macos-font-jetbrains-mono-nerd-font": "Nerd Font family",
	"macos-font-maple-mono-nf":            "Nerd Font family",
	"macos-cli-bat":                       "cat replacement",
	"macos-cli-eza":                       "ls replacement",
	"macos-cli-ripgrep":                   "Fast text search",
	"macos-cli-fd":                        "find replacement",
	"macos-cli-fzf":                       "Command-line fuzzy finder",
	"macos-cli-gh":                        "GitHub command-line tool",
	"macos-cli-htop":                      "Process monitor",
	"macos-cli-iftop":                     "Network bandwidth monitor",
	"macos-cli-jq":                        "JSON processor",
	"macos-cli-mise":                      "Multi-language runtime manager",
	"macos-cli-nmap":                      "Network scanner",
	"macos-cli-nushell":                   "Structured shell",
	"macos-cli-rsync":                     "File synchronization tool",
	"macos-cli-shellcheck":                "Shell static analyzer",
	"macos-cli-tmux":                      "Terminal multiplexer",
	"macos-cli-uv":                        "Python package and project manager",
	"macos-cli-wget":                      "Command-line downloader",
	"macos-cli-zoxide":                    "Smart directory jumper",
	"macos-cli-ffmpeg":                    "Audio/video processing",
	"macos-cli-imagemagick":               "Image processing",
	"macos-cli-gallery-dl":                "Gallery downloader",
	"macos-cli-yt-dlp":                    "Video downloader",
	"macos-cli-stylua":                    "Lua formatter",
	"macos-cli-tree-sitter-cli":           "tree-sitter command-line tool",
	"macos-cli-nload":                     "Network bandwidth monitor",
	"macos-cli-bind":                      "DNS tools",
	"macos-cli-herdr":                     "Command-line tool",
	"macos-cli-llmfit":                    "Command-line tool",
	"mihomo":                              "Proxy core, config validation, and MetaCubeXD dashboard",
	"docker":                              "Static binary, Compose plugin, and daemon config",
	"arch-mise":                           "Arch runtimes, mainland mirrors, and target-user shell activation",
	"arch-base":                           "Base, troubleshooting, modern CLI tools, and tmux configuration",
	"arch-aur":                            "Install paru and yay for a normal user; safely skip in root mode",
	"arch-archlinuxcn":                    "Configure the repository, keyring, and mirrorlist",
	"arch-dns":                            "systemd-resolved, NetworkManager, and a mainland-friendly DNS baseline",
	"arch-git":                            "git, gh, OpenSSH, and base Git settings",
	"arch-ops-toolkit":                    "Clone the operations toolkit and create stable command entrypoints",
	"arch-fonts":                          "Chinese, Emoji, Nerd Font, Monaco, and fontconfig",
	"arch-sing-box":                       "Arch-native sing-box, user service, and shell proxy template",
	"arch-desktop":                        "Hyprland, SDDM, Fcitx5/Rime, browser, hyprdots, and VM integration",
	"arch-doctor":                         "Check Arch capabilities, network, services, and desktop environment",
	"arch-status":                         "Show detailed Arch capability status and suggestions",
	"arch-dev":                            "Base tools, runtimes, containers, shell, fonts, and proxy preset",
	"arch-workstation":                    "Arch development environment plus the Hyprland desktop capability",
	"go":                                  "Go toolchain",
	"neovim":                              "Terminal editor, macOS GUI client, and personal configuration",
}

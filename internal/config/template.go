package config

import (
	"fmt"
	"strings"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

type configEntry struct {
	Key      string
	Value    string
	CommentZ string
	CommentE string
}

type configSection struct {
	TitleZ  string
	TitleE  string
	Entries []configEntry
}

func renderUserConfig(target platform.Target, lang string) []byte {
	english := configLangIsEnglish(lang)
	langValue := strings.TrimSpace(lang)
	if langValue == "" {
		langValue = "zh_CN"
	}

	sections := []configSection{
		commonConfigSection(langValue),
		terminalConfigSection(),
		githubConfigSection(),
	}

	switch configGOOS(target) {
	case "darwin":
		sections = append(sections, macOSConfigSections()...)
	case "linux":
		sections = append(sections, linuxConfigSections()...)
		if target.Family == platform.FamilyArch {
			sections = append(sections, archDevKitConfigSection())
		}
	}

	var b strings.Builder
	writeComment(&b, english,
		"OS Init 启动配置",
		"OS Init startup configuration",
	)
	writeComment(&b, english,
		"首次启动自动生成。这里只放常用配置；完整变量参考 modules/config/config.env.example。",
		"Generated on first startup. This file keeps common settings only; see modules/config/config.env.example for the full variable list.",
	)
	writeComment(&b, english,
		fmt.Sprintf("当前目标：%s", targetSummary(target)),
		fmt.Sprintf("Target: %s", targetSummary(target)),
	)
	writeComment(&b, english,
		"用户配置路径：~/.config/os-init/config.env",
		"User config path: ~/.config/os-init/config.env",
	)
	b.WriteString("\n")

	for _, section := range sections {
		writeSection(&b, section, english)
	}

	return []byte(b.String())
}

func commonConfigSection(lang string) configSection {
	return configSection{
		TitleZ: "基础设置",
		TitleE: "Base Settings",
		Entries: []configEntry{
			{
				Key:      "OS_INIT_LANG",
				Value:    lang,
				CommentZ: "界面和脚本输出语言。中文使用 zh_CN，英文使用 en_US。",
				CommentE: "UI and script output language. Use zh_CN for Chinese or en_US for English.",
			},
			{
				Key:      "OS_INIT_REGION",
				Value:    "cn",
				CommentZ: "默认区域。cn 表示按中国大陆网络环境给出资源提示和默认值。",
				CommentE: "Default region. cn enables mainland-China-oriented resource hints and defaults.",
			},
			{
				Key:      "OS_INIT_CONFIG_PROMPT",
				Value:    "1",
				CommentZ: "启动时是否显示配置提示页：1 显示，0 跳过。",
				CommentE: "Show startup configuration page: 1 shows it, 0 skips it.",
			},
			{
				Key:      "OS_INIT_SCRIPT_TIMEOUT",
				Value:    "45m",
				CommentZ: "单个模块最大执行时间。支持 30m、1h 或纯秒数；0 表示不限制。",
				CommentE: "Maximum time per module. Supports 30m, 1h, or seconds; 0 disables the limit.",
			},
		},
	}
}

func terminalConfigSection() configSection {
	return configSection{
		TitleZ: "终端体验",
		TitleE: "Terminal Experience",
		Entries: []configEntry{
			{
				Key:      "OS_INIT_TERMINAL_STYLE",
				Value:    "auto",
				CommentZ: "终端提示符样式：auto 自动判断；rich 适合本地图形终端；simple 适合 SSH；plain 适合 TTY/救援环境；none 禁用 starship。",
				CommentE: "Terminal prompt style: auto detects the session; rich for local graphical terminals; simple for SSH; plain for TTY/rescue shells; none disables starship.",
			},
			{
				Key:      "OS_INIT_TERMINAL_ENABLE_ALIASES",
				Value:    "1",
				CommentZ: "是否写入终端常用 alias：1 启用 eza/bat 友好别名，0 不启用。",
				CommentE: "Enable terminal aliases: 1 enables eza/bat-friendly aliases, 0 disables them.",
			},
			{
				Key:      "OS_INIT_TERMINAL_BAT_THEME",
				Value:    "\"Catppuccin Mocha\"",
				CommentZ: "bat 默认主题。仅在 bat 已安装时生效。",
				CommentE: "Default bat theme. Only applies when bat is installed.",
			},
		},
	}
}

func githubConfigSection() configSection {
	return configSection{
		TitleZ: "GitHub 资源代理",
		TitleE: "GitHub Resource Proxy",
		Entries: []configEntry{
			{
				Key:      "DOWNLOAD_RETRY",
				Value:    "3",
				CommentZ: "下载失败重试次数。",
				CommentE: "Download retry count.",
			},
			{
				Key:      "DOWNLOAD_TIMEOUT",
				Value:    "30",
				CommentZ: "单次下载超时时间，单位秒。",
				CommentE: "Per-request download timeout in seconds.",
			},
			{
				Key:      "GITHUB_PROXY",
				Value:    "",
				CommentZ: "GitHub 专用代理。只改写 github.com、raw.githubusercontent.com 和 GitHub release 资源；不设置全局 HTTP 代理。",
				CommentE: "GitHub-only proxy. Rewrites github.com, raw.githubusercontent.com, and GitHub release assets; it does not set a global HTTP proxy.",
			},
		},
	}
}

func macOSConfigSections() []configSection {
	return []configSection{
		{
			TitleZ: "macOS / Homebrew",
			TitleE: "macOS / Homebrew",
			Entries: []configEntry{
				{Key: "HOMEBREW_INSTALL_URL", Value: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh", CommentZ: "Homebrew 安装脚本地址。", CommentE: "Homebrew install script URL."},
				{Key: "HOMEBREW_API_DOMAIN", Value: "", CommentZ: "Homebrew 元数据 API 镜像；留空使用官方。", CommentE: "Homebrew metadata API mirror; leave empty for upstream."},
				{Key: "HOMEBREW_BOTTLE_DOMAIN", Value: "", CommentZ: "Homebrew bottle 下载镜像；留空使用官方。", CommentE: "Homebrew bottle mirror; leave empty for upstream."},
				{Key: "HOMEBREW_ARTIFACT_DOMAIN", Value: "", CommentZ: "Homebrew artifact 下载代理前缀；只使用可信来源。", CommentE: "Homebrew artifact proxy prefix; use trusted sources only."},
				{Key: "HOMEBREW_BREW_GIT_REMOTE", Value: "", CommentZ: "Homebrew/brew Git 镜像地址；通常不必设置。", CommentE: "Homebrew/brew Git mirror; usually unnecessary."},
				{Key: "HOMEBREW_CORE_GIT_REMOTE", Value: "", CommentZ: "homebrew-core Git 镜像地址；通常不必设置。", CommentE: "homebrew-core Git mirror; usually unnecessary."},
				{Key: "HOMEBREW_PIP_INDEX_URL", Value: "", CommentZ: "Homebrew 构建 Python 相关 formula 时使用的 PyPI 镜像。", CommentE: "PyPI mirror used by Homebrew when building Python-related formulae."},
			},
		},
		shellResourceSection(),
		developmentResourceSection(false),
	}
}

func linuxConfigSections() []configSection {
	return []configSection{
		shellResourceSection(),
		developmentResourceSection(true),
		dockerConfigSection(),
		mihomoConfigSection(),
	}
}

func shellResourceSection() configSection {
	return configSection{
		TitleZ: "Shell 资源",
		TitleE: "Shell Resources",
		Entries: []configEntry{
			{Key: "OH_MY_ZSH_REPO", Value: "https://github.com/ohmyzsh/ohmyzsh.git", CommentZ: "oh-my-zsh 仓库地址，可替换为镜像或内网仓库。", CommentE: "oh-my-zsh repository URL; can be replaced with a mirror or internal repository."},
			{Key: "STARSHIP_INSTALL_URL", Value: "https://starship.rs/install.sh", CommentZ: "starship 安装脚本地址。", CommentE: "starship install script URL."},
			{Key: "ZSH_AUTOSUGGESTIONS_REPO", Value: "https://github.com/zsh-users/zsh-autosuggestions.git", CommentZ: "zsh-autosuggestions 插件仓库地址。", CommentE: "zsh-autosuggestions plugin repository URL."},
			{Key: "ZSH_SYNTAX_HIGHLIGHTING_REPO", Value: "https://github.com/zsh-users/zsh-syntax-highlighting.git", CommentZ: "zsh-syntax-highlighting 插件仓库地址。", CommentE: "zsh-syntax-highlighting plugin repository URL."},
			{Key: "NVM_VERSION", Value: "", CommentZ: "nvm 版本。留空时从 GitHub 查询最新版本。", CommentE: "nvm version. Empty means query the latest version from GitHub."},
			{Key: "NVM_INSTALL_BASE", Value: "https://raw.githubusercontent.com/nvm-sh/nvm", CommentZ: "nvm 安装脚本基础地址。", CommentE: "Base URL for the nvm install script."},
			{Key: "NVM_INSTALL_URL", Value: "", CommentZ: "nvm 完整安装脚本地址；设置后优先于 NVM_INSTALL_BASE。", CommentE: "Full nvm install script URL; overrides NVM_INSTALL_BASE when set."},
			{Key: "FNM_INSTALL_URL", Value: "https://fnm.vercel.app/install", CommentZ: "fnm 安装脚本地址。", CommentE: "fnm install script URL."},
		},
	}
}

func developmentResourceSection(includeLinuxBinaries bool) configSection {
	entries := []configEntry{
		{Key: "GO_VERSION", Value: "", CommentZ: "Go 版本。留空时从 GO_VERSION_URL 查询最新版本。", CommentE: "Go version. Empty means query the latest version from GO_VERSION_URL."},
		{Key: "GO_VERSION_URL", Value: "https://go.dev/VERSION?m=text", CommentZ: "Go 最新版本查询地址。", CommentE: "URL used to query the latest Go version."},
		{Key: "GO_DOWNLOAD_BASE", Value: "https://go.dev/dl", CommentZ: "Go 安装包下载基础地址。主要用于非 macOS/Arch 的二进制安装路径。", CommentE: "Base URL for Go archive downloads. Mainly used by the non-macOS/non-Arch binary install path."},
		{Key: "GO_DOWNLOAD_URL", Value: "", CommentZ: "Go 完整安装包地址；设置后优先。macOS/Arch 默认优先包管理器。", CommentE: "Full Go archive URL; overrides the base URL when set. macOS/Arch default to package managers."},
		{Key: "LAZYVIM_STARTER_REPO", Value: "https://github.com/LazyVim/starter", CommentZ: "LazyVim starter 仓库地址，可替换为镜像或个人模板仓库。", CommentE: "LazyVim starter repository URL; can be replaced with a mirror or personal template repository."},
	}
	if includeLinuxBinaries {
		entries = append(entries,
			configEntry{Key: "NVIM_DOWNLOAD_BASE", Value: "https://github.com/neovim/neovim/releases/latest/download", CommentZ: "Linux Neovim 二进制下载基础地址。Arch 默认优先 pacman/AUR。", CommentE: "Base URL for Linux Neovim binary downloads. Arch defaults to pacman/AUR."},
			configEntry{Key: "NVIM_DOWNLOAD_URL", Value: "", CommentZ: "Neovim 完整下载地址；设置后优先。Arch 默认优先包管理器。", CommentE: "Full Neovim download URL; overrides the base URL when set. Arch defaults to package managers."},
			configEntry{Key: "LAZYGIT_VERSION", Value: "", CommentZ: "lazygit 版本。留空时从 GitHub 查询最新版本。", CommentE: "lazygit version. Empty means query the latest version from GitHub."},
			configEntry{Key: "LAZYGIT_DOWNLOAD_BASE", Value: "https://github.com/jesseduffield/lazygit/releases/download", CommentZ: "lazygit Linux 二进制下载基础地址。macOS/Arch 默认优先包管理器。", CommentE: "Base URL for lazygit Linux binary downloads. macOS/Arch default to package managers."},
			configEntry{Key: "LAZYGIT_DOWNLOAD_URL", Value: "", CommentZ: "lazygit 完整下载地址；设置后优先。macOS/Arch 默认优先包管理器。", CommentE: "Full lazygit download URL; overrides the base URL when set. macOS/Arch default to package managers."},
			configEntry{Key: "YAZI_DOWNLOAD_BASE", Value: "https://github.com/sxyazi/yazi/releases/latest/download", CommentZ: "Linux Yazi 二进制下载基础地址。Arch 默认优先 pacman/AUR。", CommentE: "Base URL for Linux Yazi binary downloads. Arch defaults to pacman/AUR."},
			configEntry{Key: "YAZI_DOWNLOAD_URL", Value: "", CommentZ: "Yazi 完整下载地址；设置后优先，并可在 Arch 上覆盖包管理器路径。", CommentE: "Full Yazi download URL; overrides the base URL and can override the Arch package-manager path."},
		)
	}
	return configSection{TitleZ: "开发资源", TitleE: "Development Resources", Entries: entries}
}

func dockerConfigSection() configSection {
	return configSection{
		TitleZ: "Docker",
		TitleE: "Docker",
		Entries: []configEntry{
			{Key: "DOCKER_DOWNLOAD_BASE", Value: "https://download.docker.com", CommentZ: "Docker 静态二进制下载基础地址。主要用于 Debian/RedHat 系；Arch 默认使用 pacman/AUR。", CommentE: "Base URL for Docker static binary downloads. Mainly used on Debian/RedHat; Arch defaults to pacman/AUR."},
			{Key: "DOCKER_CHANNEL", Value: "stable", CommentZ: "Docker 静态二进制下载通道：stable、test 或 nightly。", CommentE: "Docker static binary download channel: stable, test, or nightly."},
			{Key: "DOCKER_VERSION", Value: "", CommentZ: "Docker 静态二进制版本。留空时从 DOCKER_DOWNLOAD_BASE 查询最新版本。", CommentE: "Docker static binary version. Empty means query the latest version from DOCKER_DOWNLOAD_BASE."},
			{Key: "DOCKER_TGZ_URL", Value: "", CommentZ: "Docker 静态二进制完整下载地址；设置后优先。Arch 默认不使用。", CommentE: "Full Docker static archive URL; overrides the base URL when set. Arch does not use this by default."},
			{Key: "DOCKER_COMPOSE_VERSION", Value: "", CommentZ: "Docker Compose 二进制版本。留空时从 GitHub 查询最新版本。Arch 默认使用包管理器。", CommentE: "Docker Compose binary version. Empty means query the latest version from GitHub. Arch defaults to package managers."},
			{Key: "DOCKER_COMPOSE_DOWNLOAD_BASE", Value: "https://github.com/docker/compose/releases/download", CommentZ: "Docker Compose 二进制下载基础地址。", CommentE: "Base URL for Docker Compose binary downloads."},
			{Key: "DOCKER_COMPOSE_DOWNLOAD_URL", Value: "", CommentZ: "Docker Compose 二进制完整下载地址；设置后优先。Arch 默认不使用。", CommentE: "Full Docker Compose binary download URL; overrides the base URL when set. Arch does not use this by default."},
			{Key: "DOCKER_REGISTRY_MIRRORS", Value: "", CommentZ: "Docker 镜像加速器，多个用英文逗号分隔。", CommentE: "Docker registry mirrors, comma-separated."},
			{Key: "DOCKER_DATA_ROOT", Value: "", CommentZ: "Docker 数据目录。留空使用 Docker 默认目录。", CommentE: "Docker data root. Empty means use Docker defaults."},
		},
	}
}

func mihomoConfigSection() configSection {
	return configSection{
		TitleZ: "Mihomo",
		TitleE: "Mihomo",
		Entries: []configEntry{
			{Key: "MIHOMO_PACKAGE", Value: "mihomo", CommentZ: "Mihomo 发行版包名；仓库可用时优先尝试包管理器安装。", CommentE: "Mihomo package name; package-manager install is tried first when available."},
			{Key: "MIHOMO_VERSION", Value: "", CommentZ: "Mihomo 版本。留空时从 GitHub 查询最新版本。", CommentE: "Mihomo version. Empty means query the latest version from GitHub."},
			{Key: "MIHOMO_DOWNLOAD_BASE", Value: "", CommentZ: "Mihomo 下载基础地址；留空使用脚本内置规则。", CommentE: "Base URL for Mihomo downloads; empty uses script defaults."},
			{Key: "MIHOMO_DOWNLOAD_URL", Value: "", CommentZ: "Mihomo 完整下载地址；设置后优先。", CommentE: "Full Mihomo download URL; overrides other download settings."},
			{Key: "MIHOMO_CONFIG_SOURCE", Value: "", CommentZ: "Mihomo 配置来源：本地 config.yaml、本地模板或远程 URL。留空使用内置模板。", CommentE: "Mihomo config source: local config.yaml, local template, or remote URL. Empty uses the bundled template."},
			{Key: "MIHOMO_MIXED_PORT", Value: "7890", CommentZ: "Mihomo mixed-port。", CommentE: "Mihomo mixed-port."},
			{Key: "MIHOMO_ALLOW_LAN", Value: "0", CommentZ: "是否允许局域网访问：1 允许，0 只监听本机。", CommentE: "Allow LAN access: 1 enables it, 0 keeps local-only access."},
			{Key: "MIHOMO_BIND_ADDRESS", Value: "127.0.0.1", CommentZ: "Mihomo 代理监听地址。", CommentE: "Mihomo proxy bind address."},
			{Key: "MIHOMO_CONTROLLER_HOST", Value: "127.0.0.1", CommentZ: "Mihomo 控制接口监听地址。", CommentE: "Mihomo controller bind host."},
			{Key: "MIHOMO_CONTROLLER_PORT", Value: "9090", CommentZ: "Mihomo 控制接口端口。", CommentE: "Mihomo controller port."},
			{Key: "MIHOMO_SECRET", Value: "", CommentZ: "控制接口密钥；如果监听 0.0.0.0，强烈建议设置。", CommentE: "Controller secret. Strongly recommended when binding to 0.0.0.0."},
			{Key: "MIHOMO_AUTO_ENABLE_SERVICE", Value: "1", CommentZ: "安装后是否自动启用并启动 mihomo.service。", CommentE: "Enable and start mihomo.service after installation."},
			{Key: "ENABLE_METACUBEXD", Value: "1", CommentZ: "是否安装 MetaCubeXD 面板。", CommentE: "Install the MetaCubeXD dashboard."},
			{Key: "METACUBEXD_SOURCE", Value: "", CommentZ: "MetaCubeXD 本地或远程压缩包来源；留空在线获取。", CommentE: "Local or remote MetaCubeXD archive source; empty means fetch online."},
		},
	}
}

func archDevKitConfigSection() configSection {
	return configSection{
		TitleZ: "ArchDevKit 桥接配置",
		TitleE: "ArchDevKit Bridge Settings",
		Entries: []configEntry{
			{Key: "OS_INIT_ARCHDEVKIT_DEFAULT_PROFILE", Value: "dev", CommentZ: "ArchDevKit 原版菜单默认目标。dev = 完整开发环境，不默认安装桌面。", CommentE: "Default target for the original ArchDevKit menu. dev means a complete development environment without the desktop by default."},
			{Key: "OS_INIT_ARCHDEVKIT_SHELL_PROMPT_ENGINE", Value: "starship", CommentZ: "ArchDevKit shell 提示符引擎：starship、powerlevel10k 或 basic。默认 starship 会复用 os-init 终端样式模板。", CommentE: "ArchDevKit shell prompt engine: starship, powerlevel10k, or basic. The default starship option reuses os-init terminal style templates."},
			{Key: "OS_INIT_ARCHDEVKIT_ENABLE_PROXY", Value: "1", CommentZ: "dev/workstation 中是否安装代理模块。", CommentE: "Install the proxy module in dev/workstation targets."},
			{Key: "OS_INIT_ARCHDEVKIT_PROXY_CORE", Value: "mihomo", CommentZ: "ArchDevKit 代理核心：mihomo 或 sing-box。", CommentE: "ArchDevKit proxy core: mihomo or sing-box."},
			{Key: "OS_INIT_ARCHDEVKIT_PROXY_AUTO_ENABLE_SERVICE", Value: "1", CommentZ: "安装代理后是否自动启用并启动服务。", CommentE: "Enable and start the proxy service after installation."},
			{Key: "OS_INIT_ARCHDEVKIT_ENABLE_METACUBEXD", Value: "1", CommentZ: "使用 mihomo 时是否安装 MetaCubeXD 面板。", CommentE: "Install the MetaCubeXD dashboard when using mihomo."},
			{Key: "OS_INIT_ARCHDEVKIT_ENABLE_DNS", Value: "1", CommentZ: "dev/workstation 中是否配置 systemd-resolved DNS 基线。", CommentE: "Configure the systemd-resolved DNS baseline in dev/workstation targets."},
			{Key: "OS_INIT_ARCHDEVKIT_ENABLE_OPS_TOOLKIT", Value: "1", CommentZ: "dev/workstation 中是否安装 Ops Toolkit。", CommentE: "Install Ops Toolkit in dev/workstation targets."},
			{Key: "OS_INIT_ARCHDEVKIT_GPU_TYPE", Value: "auto", CommentZ: "桌面目标使用的 GPU 类型：auto、intel、amd、nvidia、vmware、virtio、qxl、virtualbox、none。", CommentE: "GPU type for desktop targets: auto, intel, amd, nvidia, vmware, virtio, qxl, virtualbox, none."},
		},
	}
}

func writeSection(b *strings.Builder, section configSection, english bool) {
	b.WriteString("# ------------------------------------------------------------\n")
	writeComment(b, english, section.TitleZ, section.TitleE)
	b.WriteString("# ------------------------------------------------------------\n\n")
	for _, entry := range section.Entries {
		if entry.CommentZ != "" || entry.CommentE != "" {
			writeComment(b, english, entry.CommentZ, entry.CommentE)
		}
		fmt.Fprintf(b, "%s=%s\n\n", entry.Key, entry.Value)
	}
}

func writeComment(b *strings.Builder, english bool, zh, en string) {
	value := zh
	if english {
		value = en
	}
	for _, line := range strings.Split(value, "\n") {
		if line == "" {
			b.WriteString("#\n")
			continue
		}
		b.WriteString("# ")
		b.WriteString(line)
		b.WriteString("\n")
	}
}

func configLangIsEnglish(lang string) bool {
	return strings.HasPrefix(strings.ToLower(strings.TrimSpace(lang)), "en")
}

func configGOOS(target platform.Target) string {
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

func targetSummary(target platform.Target) string {
	goos := configGOOS(target)
	if target.Family != "" && target.Family != platform.FamilyUnknown {
		return fmt.Sprintf("%s/%s", goos, target.Family)
	}
	return goos
}

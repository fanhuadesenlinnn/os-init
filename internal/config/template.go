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
		githubConfigSection(),
	}

	switch configGOOS(target) {
	case "darwin":
		sections = append(sections, macOSConfigSections()...)
	case "linux":
		sections = append(sections, linuxConfigSections(target)...)
		if target.Family == platform.FamilyArch {
			sections = append(sections, archConfigSection())
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
			{Key: "OS_INIT_ALLOW_UNVERIFIED_PROXY", Value: "0", CommentZ: "是否允许经 GitHub 代理获取未经校验的可执行内容；默认拒绝。", CommentE: "Allow unverified executable content through a GitHub proxy; rejected by default."},
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
				{Key: "HOMEBREW_INSTALL_SHA256", Value: "", CommentZ: "经代理下载 Homebrew 安装脚本时要求的 SHA-256。", CommentE: "Expected SHA-256 for a proxied Homebrew installer."},
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

func linuxConfigSections(target platform.Target) []configSection {
	sections := []configSection{
		shellResourceSection(),
		developmentResourceSection(true),
		dockerConfigSection(),
	}
	if target.Family == platform.FamilyArch {
		return append(sections, archMihomoConfigSection())
	}
	return append(sections, mihomoConfigSection())
}

func shellResourceSection() configSection {
	return configSection{
		TitleZ: "Shell 资源",
		TitleE: "Shell Resources",
		Entries: []configEntry{
			{Key: "ZSH_AUTOSUGGESTIONS_REPO", Value: "https://github.com/zsh-users/zsh-autosuggestions.git", CommentZ: "zsh-autosuggestions 插件仓库地址。", CommentE: "zsh-autosuggestions plugin repository URL."},
			{Key: "ZSH_SYNTAX_HIGHLIGHTING_REPO", Value: "https://github.com/zsh-users/zsh-syntax-highlighting.git", CommentZ: "zsh-syntax-highlighting 插件仓库地址。", CommentE: "zsh-syntax-highlighting plugin repository URL."},
		},
	}
}

func developmentResourceSection(includeLinuxBinaries bool) configSection {
	entries := []configEntry{
		{Key: "MISE_VERSION", Value: "", CommentZ: "mise 版本。留空时从 GitHub 查询最新版本；仅 portable Linux 路径使用。", CommentE: "mise version. Empty means query the latest GitHub release; used only by portable Linux installs."},
		{Key: "MISE_INSTALL_PATH", Value: "", CommentZ: "mise portable 二进制路径。留空为目标用户 ~/.local/bin/mise。", CommentE: "Portable mise binary path. Empty defaults to the target user's ~/.local/bin/mise."},
		{Key: "MISE_DOWNLOAD_BASE", Value: "https://github.com/jdx/mise/releases/download", CommentZ: "mise 官方 Release 下载基础地址。", CommentE: "Base URL for official mise release downloads."},
		{Key: "MISE_DOWNLOAD_URL", Value: "", CommentZ: "mise 完整二进制下载地址；设置后优先。", CommentE: "Full mise binary URL; overrides the base URL when set."},
		{Key: "MISE_DOWNLOAD_SHA256", Value: "", CommentZ: "mise 二进制 SHA-256；使用 GitHub 代理时建议配置。", CommentE: "Expected mise binary SHA-256; recommended when using a GitHub proxy."},
		{Key: "MISE_NODE_VERSION", Value: "24", CommentZ: "mise 管理的用户级全局 Node.js 主版本。", CommentE: "Global user-level Node.js major version managed by mise."},
		{Key: "MISE_PYTHON_VERSION", Value: "3.13", CommentZ: "mise 管理的用户级全局 Python 版本系列；不修改系统 Python。", CommentE: "Global user-level Python version series managed by mise; does not modify system Python."},
		{Key: "MISE_GO_VERSION", Value: "1.26", CommentZ: "mise 管理的用户级全局 Go 版本系列。", CommentE: "Global user-level Go version series managed by mise."},
		{Key: "MISE_NODE_MIRROR_URL", Value: "https://npmmirror.com/mirrors/node/", CommentZ: "mise 下载 Node.js 的大陆镜像，失败时自动回退官方源。", CommentE: "Mainland China mirror for mise Node.js downloads; falls back to upstream on failure."},
		{Key: "MISE_GO_DOWNLOAD_MIRROR", Value: "https://dl.google.com/go", CommentZ: "mise 下载 Go SDK 的兼容地址，失败时自动回退官方源。", CommentE: "mise-compatible Go SDK download URL with upstream fallback."},
		{Key: "NPM_CONFIG_REGISTRY", Value: "https://registry.npmmirror.com", CommentZ: "npm 中国大陆镜像。", CommentE: "npm registry mirror for Mainland China."},
		{Key: "PIP_INDEX_URL", Value: "https://pypi.tuna.tsinghua.edu.cn/simple", CommentZ: "pip 中国大陆镜像。", CommentE: "pip index mirror for Mainland China."},
		{Key: "UV_DEFAULT_INDEX", Value: "https://pypi.tuna.tsinghua.edu.cn/simple", CommentZ: "uv 中国大陆镜像。", CommentE: "uv index mirror for Mainland China."},
		{Key: "GOPROXY", Value: "https://goproxy.cn,direct", CommentZ: "Go module 中国大陆代理。", CommentE: "Go module proxy for Mainland China."},
		{Key: "NVIM_CONFIG_REPO", Value: "https://github.com/fanhuadesenlinnn/nvim.git", CommentZ: "config-yuan Neovim 配置仓库地址，可替换为镜像。", CommentE: "config-yuan Neovim configuration repository; can be replaced with a mirror."},
	}
	if includeLinuxBinaries {
		entries = append(entries,
			configEntry{Key: "NVIM_DOWNLOAD_BASE", Value: "https://github.com/neovim/neovim/releases/latest/download", CommentZ: "Linux Neovim 二进制下载基础地址。Arch 默认优先 pacman/AUR。", CommentE: "Base URL for Linux Neovim binary downloads. Arch defaults to pacman/AUR."},
			configEntry{Key: "NVIM_DOWNLOAD_URL", Value: "", CommentZ: "Neovim 完整下载地址；设置后优先。Arch 默认优先包管理器。", CommentE: "Full Neovim download URL; overrides the base URL when set. Arch defaults to package managers."},
			configEntry{Key: "NVIM_DOWNLOAD_SHA256", Value: "", CommentZ: "Neovim 安装包 SHA-256。", CommentE: "Expected SHA-256 for the Neovim archive."},
			configEntry{Key: "LAZYGIT_VERSION", Value: "", CommentZ: "lazygit 版本。留空时从 GitHub 查询最新版本。", CommentE: "lazygit version. Empty means query the latest version from GitHub."},
			configEntry{Key: "LAZYGIT_DOWNLOAD_BASE", Value: "https://github.com/jesseduffield/lazygit/releases/download", CommentZ: "lazygit Linux 二进制下载基础地址。macOS/Arch 默认优先包管理器。", CommentE: "Base URL for lazygit Linux binary downloads. macOS/Arch default to package managers."},
			configEntry{Key: "LAZYGIT_DOWNLOAD_URL", Value: "", CommentZ: "lazygit 完整下载地址；设置后优先。macOS/Arch 默认优先包管理器。", CommentE: "Full lazygit download URL; overrides the base URL when set. macOS/Arch default to package managers."},
			configEntry{Key: "LAZYGIT_DOWNLOAD_SHA256", Value: "", CommentZ: "lazygit 安装包 SHA-256。", CommentE: "Expected SHA-256 for the lazygit archive."},
			configEntry{Key: "YAZI_DOWNLOAD_BASE", Value: "https://github.com/sxyazi/yazi/releases/latest/download", CommentZ: "Linux Yazi 二进制下载基础地址。Arch 默认优先 pacman/AUR。", CommentE: "Base URL for Linux Yazi binary downloads. Arch defaults to pacman/AUR."},
			configEntry{Key: "YAZI_DOWNLOAD_URL", Value: "", CommentZ: "Yazi 完整下载地址；设置后优先，并可在 Arch 上覆盖包管理器路径。", CommentE: "Full Yazi download URL; overrides the base URL and can override the Arch package-manager path."},
			configEntry{Key: "YAZI_DOWNLOAD_SHA256", Value: "", CommentZ: "Yazi 安装包 SHA-256。", CommentE: "Expected SHA-256 for the Yazi archive."},
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
			{Key: "DOCKER_TGZ_SHA256", Value: "", CommentZ: "Docker 静态包 SHA-256。", CommentE: "Expected SHA-256 for the Docker static archive."},
			{Key: "DOCKER_COMPOSE_VERSION", Value: "", CommentZ: "Docker Compose 二进制版本。留空时从 GitHub 查询最新版本。Arch 默认使用包管理器。", CommentE: "Docker Compose binary version. Empty means query the latest version from GitHub. Arch defaults to package managers."},
			{Key: "DOCKER_COMPOSE_DOWNLOAD_BASE", Value: "https://github.com/docker/compose/releases/download", CommentZ: "Docker Compose 二进制下载基础地址。", CommentE: "Base URL for Docker Compose binary downloads."},
			{Key: "DOCKER_COMPOSE_DOWNLOAD_URL", Value: "", CommentZ: "Docker Compose 二进制完整下载地址；设置后优先。Arch 默认不使用。", CommentE: "Full Docker Compose binary download URL; overrides the base URL when set. Arch does not use this by default."},
			{Key: "DOCKER_COMPOSE_SHA256", Value: "", CommentZ: "Docker Compose 二进制 SHA-256。", CommentE: "Expected SHA-256 for Docker Compose."},
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
			{Key: "MIHOMO_DOWNLOAD_SHA256", Value: "", CommentZ: "Mihomo 二进制 SHA-256。", CommentE: "Expected SHA-256 for the Mihomo binary."},
			{Key: "MIHOMO_CONFIG_SOURCE", Value: "", CommentZ: "Mihomo 配置来源：本地 config.yaml、本地模板或远程 URL。留空使用内置模板。", CommentE: "Mihomo config source: local config.yaml, local template, or remote URL. Empty uses the bundled template."},
			{Key: "MIHOMO_MIXED_PORT", Value: "7890", CommentZ: "Mihomo mixed-port。", CommentE: "Mihomo mixed-port."},
			{Key: "MIHOMO_ALLOW_LAN", Value: "0", CommentZ: "是否允许局域网代理访问；具体监听地址由 bind/controller/DNS 配置分别决定。", CommentE: "Allow LAN proxy access; bind, controller, and DNS listen addresses are configured separately."},
			{Key: "MIHOMO_BIND_ADDRESS", Value: "0.0.0.0", CommentZ: "Mihomo 代理监听地址。", CommentE: "Mihomo proxy bind address."},
			{Key: "MIHOMO_CONTROLLER_HOST", Value: "0.0.0.0", CommentZ: "Mihomo 控制接口监听地址。", CommentE: "Mihomo controller bind host."},
			{Key: "MIHOMO_CONTROLLER_PORT", Value: "9090", CommentZ: "Mihomo 控制接口端口。", CommentE: "Mihomo controller port."},
			{Key: "MIHOMO_DNS_LISTEN", Value: "0.0.0.0:1053", CommentZ: "Mihomo DNS 监听地址。", CommentE: "Mihomo DNS listen address."},
			{Key: "MIHOMO_SECRET", Value: "", CommentZ: "控制接口密钥，默认留空，可按需设置。", CommentE: "Controller secret; empty by default and configurable when needed."},
			{Key: "MIHOMO_AUTO_ENABLE_SERVICE", Value: "1", CommentZ: "安装后是否自动启用并启动 mihomo.service。", CommentE: "Enable and start mihomo.service after installation."},
			{Key: "ENABLE_METACUBEXD", Value: "1", CommentZ: "是否安装 MetaCubeXD 面板。", CommentE: "Install the MetaCubeXD dashboard."},
			{Key: "METACUBEXD_SOURCE", Value: "", CommentZ: "MetaCubeXD 本地或远程压缩包来源；留空在线获取。", CommentE: "Local or remote MetaCubeXD archive source; empty means fetch online."},
			{Key: "METACUBEXD_SHA256", Value: "", CommentZ: "远程 MetaCubeXD 压缩包 SHA-256。", CommentE: "Expected SHA-256 for a remote MetaCubeXD archive."},
		},
	}
}

func archConfigSection() configSection {
	return configSection{
		TitleZ: "Arch Linux 能力",
		TitleE: "Arch Linux Capabilities",
		Entries: []configEntry{
			{Key: "ENABLE_DNS", Value: "1", CommentZ: "是否启用 Arch DNS 能力。", CommentE: "Enable the Arch DNS capability."},
			{Key: "ENABLE_OPS_TOOLKIT", Value: "1", CommentZ: "是否启用 Ops Toolkit。", CommentE: "Enable Ops Toolkit."},
			{Key: "GPU_TYPE", Value: "auto", CommentZ: "GPU 类型：auto、intel、amd、nvidia、vmware、virtio、qxl、virtualbox、none。", CommentE: "GPU type: auto, intel, amd, nvidia, vmware, virtio, qxl, virtualbox, or none."},
		},
	}
}

func archMihomoConfigSection() configSection {
	return configSection{
		TitleZ: "Arch Mihomo",
		TitleE: "Arch Mihomo",
		Entries: []configEntry{
			{Key: "MIHOMO_PACKAGE", Value: "mihomo", CommentZ: "archlinuxcn 中的 Mihomo 包名。", CommentE: "Mihomo package name from archlinuxcn."},
			{Key: "MIHOMO_CONFIG_SOURCE", Value: "", CommentZ: "本地 config.yaml、本地模板或远程 URL；留空使用内置完整模板。", CommentE: "Local config.yaml, local template, or remote URL; empty uses the bundled full template."},
			{Key: "MIHOMO_MIXED_PORT", Value: "7890", CommentZ: "Mihomo mixed-port。", CommentE: "Mihomo mixed-port."},
			{Key: "MIHOMO_ALLOW_LAN", Value: "0", CommentZ: "是否允许局域网访问。", CommentE: "Allow LAN access."},
			{Key: "MIHOMO_BIND_ADDRESS", Value: "0.0.0.0", CommentZ: "Mihomo 代理监听地址。", CommentE: "Mihomo proxy bind address."},
			{Key: "MIHOMO_CONTROLLER_HOST", Value: "0.0.0.0", CommentZ: "Mihomo 控制接口监听地址。", CommentE: "Mihomo controller bind host."},
			{Key: "MIHOMO_CONTROLLER_PORT", Value: "9090", CommentZ: "Mihomo 控制接口端口。", CommentE: "Mihomo controller port."},
			{Key: "MIHOMO_DNS_LISTEN", Value: "0.0.0.0:1053", CommentZ: "Mihomo DNS 监听地址。", CommentE: "Mihomo DNS listen address."},
			{Key: "MIHOMO_SECRET", Value: "", CommentZ: "控制接口密钥，默认留空，可按需设置。", CommentE: "Controller secret; empty by default and configurable when needed."},
			{Key: "PROXY_AUTO_ENABLE_SERVICE", Value: "1", CommentZ: "配置预检通过后自动启用 mihomo.service。", CommentE: "Enable mihomo.service after configuration validation passes."},
			{Key: "ENABLE_METACUBEXD", Value: "1", CommentZ: "安装并由 Mihomo 托管 MetaCubeXD。", CommentE: "Install MetaCubeXD and serve it through Mihomo."},
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
	if target.Environment == platform.EnvironmentWSL {
		return fmt.Sprintf("%s/%s/wsl%d", goos, target.Family, target.WSLVersion)
	}
	if target.Family != "" && target.Family != platform.FamilyUnknown {
		return fmt.Sprintf("%s/%s", goos, target.Family)
	}
	return goos
}

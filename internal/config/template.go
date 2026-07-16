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

	sections := []configSection{commonConfigSection(langValue), githubConfigSection()}
	switch configGOOS(target) {
	case "darwin":
		sections = append(sections, macOSConfigSections()...)
	case "linux":
		sections = append(sections, linuxConfigSections(target)...)
	}

	var b strings.Builder
	writeComment(&b, english, "OS Init 启动配置", "OS Init startup configuration")
	writeComment(&b, english,
		"首次启动按当前系统生成。此文件是唯一的用户配置入口，只包含当前系统实际使用的常用选项。",
		"Generated for the current system on first startup. This is the only user configuration entry point and contains only commonly used options for this system.",
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
			{Key: "OS_INIT_LANG", Value: lang, CommentZ: "界面和脚本输出语言：zh_CN 或 en_US。", CommentE: "UI and script output language: zh_CN or en_US."},
			{Key: "OS_INIT_REGION", Value: "cn", CommentZ: "默认区域。cn 使用中国大陆网络相关默认值。", CommentE: "Default region. cn enables mainland-China-oriented defaults."},
			{Key: "OS_INIT_CONFIG_PROMPT", Value: "1", CommentZ: "启动时是否显示配置提示页：1 显示，0 跳过。", CommentE: "Show the startup configuration page: 1 shows it, 0 skips it."},
			{Key: "OS_INIT_SCRIPT_TIMEOUT", Value: "45m", CommentZ: "单个模块最大执行时间；0 表示不限制。", CommentE: "Maximum time per module; 0 disables the limit."},
		},
	}
}

func githubConfigSection() configSection {
	return configSection{
		TitleZ: "GitHub 资源代理",
		TitleE: "GitHub Resource Proxy",
		Entries: []configEntry{
			{Key: "GITHUB_PROXY", Value: "https://hubproxy.babadafafafafa.cn", CommentZ: "GitHub URL 代理；支持前缀、{url} 和 {url_encoded} 模板。留空可关闭。", CommentE: "GitHub URL proxy; supports prefixes, {url}, and {url_encoded} templates. Leave empty to disable."},
		},
	}
}

func macOSConfigSections() []configSection {
	return []configSection{
		{
			TitleZ: "macOS / Homebrew",
			TitleE: "macOS / Homebrew",
			Entries: []configEntry{
				{Key: "HOMEBREW_API_DOMAIN", Value: "", CommentZ: "Homebrew 元数据 API 镜像；留空使用官方。", CommentE: "Homebrew metadata API mirror; leave empty for upstream."},
				{Key: "HOMEBREW_BOTTLE_DOMAIN", Value: "", CommentZ: "Homebrew bottle 下载镜像；留空使用官方。", CommentE: "Homebrew bottle mirror; leave empty for upstream."},
			},
		},
		developmentConfigSection(),
	}
}

func linuxConfigSections(target platform.Target) []configSection {
	sections := []configSection{developmentConfigSection(), dockerConfigSection()}
	if target.Family == platform.FamilyArch {
		return append(sections, archConfigSection(), mihomoConfigSection("Arch Mihomo", "Arch Mihomo"))
	}
	return append(sections, mihomoConfigSection("Mihomo", "Mihomo"))
}

func developmentConfigSection() configSection {
	return configSection{
		TitleZ: "开发环境",
		TitleE: "Development Environment",
		Entries: []configEntry{
			{Key: "OS_INIT_MISE_NODE_VERSION", Value: "24", CommentZ: "mise 管理的用户级全局 Node.js 主版本。", CommentE: "Global user-level Node.js major version managed by mise."},
			{Key: "OS_INIT_MISE_PYTHON_VERSION", Value: "3.13", CommentZ: "mise 管理的用户级全局 Python 版本系列。", CommentE: "Global user-level Python version series managed by mise."},
			{Key: "OS_INIT_MISE_GO_VERSION", Value: "1.26", CommentZ: "mise 管理的用户级全局 Go 版本系列。", CommentE: "Global user-level Go version series managed by mise."},
			{Key: "MISE_NODE_MIRROR_URL", Value: "https://npmmirror.com/mirrors/node/", CommentZ: "mise 下载 Node.js 使用的镜像。", CommentE: "Mirror used by mise to download Node.js."},
			{Key: "MISE_GO_DOWNLOAD_MIRROR", Value: "https://dl.google.com/go", CommentZ: "mise 下载 Go SDK 使用的地址。", CommentE: "URL used by mise to download Go SDKs."},
			{Key: "NPM_CONFIG_REGISTRY", Value: "https://registry.npmmirror.com", CommentZ: "npm 镜像。", CommentE: "npm registry mirror."},
			{Key: "PIP_INDEX_URL", Value: "https://pypi.tuna.tsinghua.edu.cn/simple", CommentZ: "pip 镜像。", CommentE: "pip index mirror."},
			{Key: "UV_DEFAULT_INDEX", Value: "https://pypi.tuna.tsinghua.edu.cn/simple", CommentZ: "uv 镜像。", CommentE: "uv index mirror."},
			{Key: "GOPROXY", Value: "https://goproxy.cn,direct", CommentZ: "Go module 代理。", CommentE: "Go module proxy."},
			{Key: "NVIM_CONFIG_REPO", Value: "https://github.com/fanhuadesenlinnn/nvim.git", CommentZ: "Neovim 配置仓库。", CommentE: "Neovim configuration repository."},
		},
	}
}

func dockerConfigSection() configSection {
	return configSection{
		TitleZ: "Docker",
		TitleE: "Docker",
		Entries: []configEntry{
			{Key: "DOCKER_REGISTRY_MIRRORS", Value: "https://hubproxy.babadafafafafa.cn", CommentZ: "Docker 镜像加速器，多个用逗号分隔；留空可关闭。", CommentE: "Docker registry mirrors, comma-separated; leave empty to disable."},
			{Key: "DOCKER_INSECURE_REGISTRIES", Value: "", CommentZ: "非安全镜像仓库，多个用逗号分隔；通常留空。", CommentE: "Insecure registries, comma-separated; normally leave empty."},
			{Key: "DOCKER_DATA_ROOT", Value: "", CommentZ: "Docker 数据目录；留空使用默认目录。", CommentE: "Docker data root; empty uses the default."},
		},
	}
}

func mihomoConfigSection(titleZ, titleE string) configSection {
	return configSection{
		TitleZ: titleZ,
		TitleE: titleE,
		Entries: []configEntry{
			{Key: "MIHOMO_CONFIG_SOURCE", Value: "", CommentZ: "本地配置、模板或远程 URL；留空使用内置模板。", CommentE: "Local config, template, or remote URL; empty uses the bundled template."},
			{Key: "MIHOMO_MIXED_PORT", Value: "7890", CommentZ: "Mihomo mixed-port。", CommentE: "Mihomo mixed-port."},
			{Key: "MIHOMO_ALLOW_LAN", Value: "0", CommentZ: "是否允许局域网访问。", CommentE: "Allow LAN access."},
			{Key: "MIHOMO_BIND_ADDRESS", Value: "0.0.0.0", CommentZ: "代理监听地址。", CommentE: "Proxy bind address."},
			{Key: "MIHOMO_CONTROLLER_HOST", Value: "0.0.0.0", CommentZ: "控制接口监听地址。", CommentE: "Controller bind host."},
			{Key: "MIHOMO_CONTROLLER_PORT", Value: "9090", CommentZ: "控制接口端口。", CommentE: "Controller port."},
			{Key: "MIHOMO_DNS_LISTEN", Value: "0.0.0.0:1053", CommentZ: "DNS 监听地址。", CommentE: "DNS listen address."},
			{Key: "MIHOMO_SECRET", Value: "", CommentZ: "控制接口密钥。", CommentE: "Controller secret."},
			{Key: "MIHOMO_AUTO_ENABLE_SERVICE", Value: "1", CommentZ: "配置预检通过后自动启用服务。", CommentE: "Enable the service after configuration validation passes."},
			{Key: "ENABLE_METACUBEXD", Value: "1", CommentZ: "是否安装 MetaCubeXD。", CommentE: "Install MetaCubeXD."},
		},
	}
}

func archConfigSection() configSection {
	return configSection{
		TitleZ: "Arch Linux 能力",
		TitleE: "Arch Linux Capabilities",
		Entries: []configEntry{
			{Key: "PACMAN_RETRY_ATTEMPTS", Value: "3", CommentZ: "pacman 网络失败重试次数。", CommentE: "Retry count for pacman network failures."},
			{Key: "ARCHLINUXARM_MIRRORS", Value: "'http://tw.mirror.archlinuxarm.org/$arch/$repo,http://tw2.mirror.archlinuxarm.org/$arch/$repo'", CommentZ: "Arch Linux ARM 优先镜像，逗号分隔。", CommentE: "Preferred Arch Linux ARM mirrors, comma-separated."},
			{Key: "ENABLE_DNS", Value: "1", CommentZ: "是否启用 Arch DNS 能力。", CommentE: "Enable the Arch DNS capability."},
			{Key: "ENABLE_OPS_TOOLKIT", Value: "1", CommentZ: "是否启用 Ops Toolkit。", CommentE: "Enable Ops Toolkit."},
			{Key: "GPU_TYPE", Value: "auto", CommentZ: "GPU 类型：auto、intel、amd、nvidia、vmware、virtio、qxl、virtualbox、none。", CommentE: "GPU type: auto, intel, amd, nvidia, vmware, virtio, qxl, virtualbox, or none."},
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
	if target.Environment == platform.EnvironmentOrbStack {
		return fmt.Sprintf("%s/%s/orbstack", goos, target.Family)
	}
	if target.Family != "" && target.Family != platform.FamilyUnknown {
		return fmt.Sprintf("%s/%s", goos, target.Family)
	}
	return goos
}

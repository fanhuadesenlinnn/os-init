package tui

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

type archDevKitStep int

const (
	archStepTarget archDevKitStep = iota
	archStepCustomTarget
	archStepArchlinuxcn
	archStepDNS
	archStepOpsToolkit
	archStepProxyBundle
	archStepProxyCore
	archStepProxyService
	archStepMetaCubeXD
	archStepGPU
	archStepSDDM
	archStepHyprlandConfig
	archStepFcitx5
	archStepInputEngine
	archStepRimeSchema
	archStepRimeConfig
	archStepBrowserPackage
	archStepBrowserApp
	archStepReview
)

type archQuestionKind int

const (
	archQuestionChoice archQuestionKind = iota
	archQuestionBool
	archQuestionValue
	archQuestionReview
)

type archOption struct {
	key  string
	desc string
}

type archQuestion struct {
	kind    archQuestionKind
	title   string
	current string
	envKey  string
	options []archOption
}

type archDevKitModel struct {
	assets     fs.FS
	step       archDevKitStep
	history    []archDevKitStep
	cursor     int
	values     map[string]string
	overrides  map[string]string
	target     string
	valueInput string
	err        string
	width      int
}

func newArchDevKitModel(assets fs.FS) archDevKitModel {
	values := loadArchDevKitSettings(assets)
	target := normalizeArchTarget(values["ARCHDEVKIT_DEFAULT_PROFILE"])
	if target == "" || target == "custom" {
		target = "workstation"
	}

	m := archDevKitModel{
		assets:    assets,
		values:    values,
		overrides: make(map[string]string),
		target:    target,
	}
	m.prepareStep()
	return m
}

func (m archDevKitModel) Init() tea.Cmd { return nil }

func (m archDevKitModel) Update(msg tea.Msg) (archDevKitModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil

	case tea.KeyMsg:
		m.err = ""
		q := m.question()

		if q.kind == archQuestionValue {
			return m.updateValue(msg)
		}

		switch msg.String() {
		case "esc", "q":
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		case "b", "left":
			if m.back() {
				return m, nil
			}
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		case "up", "k":
			if len(q.options) > 0 {
				m.cursor--
				if m.cursor < 0 {
					m.cursor = len(q.options) - 1
				}
			}
		case "down", "j":
			if len(q.options) > 0 {
				m.cursor++
				if m.cursor >= len(q.options) {
					m.cursor = 0
				}
			}
		case "enter":
			if q.kind == archQuestionReview {
				module, ok := modules.ArchDevKitInstallModule(m.target)
				if !ok {
					m.err = fmt.Sprintf(text("未知 ArchDevKit 目标：%s", "Unknown ArchDevKit target: %s"), m.target)
					return m, nil
				}
				return m, func() tea.Msg {
					return archDevKitSelectedMsg{
						module: module,
						env:    m.executionEnv(),
					}
				}
			}
			if len(q.options) > 0 && m.cursor < len(q.options) {
				m.applyAnswer(q.options[m.cursor].key)
			}
		default:
			if q.kind == archQuestionBool {
				switch strings.ToLower(msg.String()) {
				case "y":
					m.applyAnswer("1")
				case "n":
					m.applyAnswer("0")
				}
				return m, nil
			}
			if idx, ok := numericChoice(msg.String(), len(q.options)); ok {
				m.cursor = idx
				m.applyAnswer(q.options[idx].key)
			}
		}
	}

	return m, nil
}

func (m archDevKitModel) updateValue(msg tea.KeyMsg) (archDevKitModel, tea.Cmd) {
	q := m.question()
	switch msg.String() {
	case "esc":
		return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
	case "b", "left":
		if m.back() {
			return m, nil
		}
		return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
	case "enter":
		value := strings.TrimSpace(m.valueInput)
		if value == "" {
			value = q.current
		}
		m.applyAnswer(value)
	case "backspace":
		if len(m.valueInput) > 0 {
			m.valueInput = m.valueInput[:len(m.valueInput)-1]
		}
	case "ctrl+u":
		m.valueInput = ""
	default:
		if len(msg.String()) == 1 {
			m.valueInput += msg.String()
		}
	}
	return m, nil
}

func numericChoice(key string, total int) (int, bool) {
	if total == 0 {
		return 0, false
	}
	n, err := strconv.Atoi(key)
	if err != nil || n < 1 || n > total {
		return 0, false
	}
	return n - 1, true
}

func (m *archDevKitModel) applyAnswer(value string) {
	q := m.question()
	if q.envKey != "" {
		m.values[q.envKey] = value
		m.overrides[q.envKey] = value
	}

	switch m.step {
	case archStepTarget:
		m.target = value
		if value == "custom" {
			m.goTo(archStepCustomTarget)
			return
		}
		m.goTo(m.firstStepAfterTarget())
	case archStepCustomTarget:
		m.target = value
		m.goTo(m.firstStepAfterTarget())
	case archStepArchlinuxcn:
		m.goTo(archStepDNS)
	case archStepDNS:
		m.goTo(archStepOpsToolkit)
	case archStepOpsToolkit:
		m.goTo(archStepProxyBundle)
	case archStepProxyBundle:
		m.goTo(m.firstStepAfterProxyBundle())
	case archStepProxyCore:
		m.goTo(archStepProxyService)
	case archStepProxyService:
		if m.values["PROXY_CORE"] == "mihomo" {
			m.goTo(archStepMetaCubeXD)
			return
		}
		m.goTo(m.firstStepAfterProxy())
	case archStepMetaCubeXD:
		m.goTo(m.firstStepAfterProxy())
	case archStepGPU:
		m.goTo(archStepSDDM)
	case archStepSDDM:
		m.goTo(archStepHyprlandConfig)
	case archStepHyprlandConfig:
		m.goTo(archStepFcitx5)
	case archStepFcitx5:
		if m.values["ENABLE_FCITX5"] == "1" {
			m.goTo(archStepInputEngine)
			return
		}
		m.goTo(archStepBrowserPackage)
	case archStepInputEngine:
		if m.values["INPUT_METHOD_ENGINE"] == "rime" {
			m.goTo(archStepRimeSchema)
			return
		}
		m.goTo(archStepBrowserPackage)
	case archStepRimeSchema:
		m.goTo(archStepRimeConfig)
	case archStepRimeConfig:
		m.goTo(archStepBrowserPackage)
	case archStepBrowserPackage:
		m.goTo(archStepBrowserApp)
	case archStepBrowserApp:
		m.goTo(archStepReview)
	}
}

func (m archDevKitModel) firstStepAfterTarget() archDevKitStep {
	if m.target == "dev" || m.target == "workstation" {
		return archStepArchlinuxcn
	}
	if m.targetNeedsProxy() {
		return archStepProxyCore
	}
	if m.targetNeedsDesktop() {
		return archStepGPU
	}
	return archStepReview
}

func (m archDevKitModel) firstStepAfterProxyBundle() archDevKitStep {
	if m.targetNeedsProxy() {
		return archStepProxyCore
	}
	if m.targetNeedsDesktop() {
		return archStepGPU
	}
	return archStepReview
}

func (m archDevKitModel) firstStepAfterProxy() archDevKitStep {
	if m.targetNeedsDesktop() {
		return archStepGPU
	}
	return archStepReview
}

func (m archDevKitModel) targetNeedsProxy() bool {
	return m.target == "proxy" || ((m.target == "dev" || m.target == "workstation") && m.values["ENABLE_PROXY"] == "1")
}

func (m archDevKitModel) targetNeedsDesktop() bool {
	return m.target == "desktop" || m.target == "workstation"
}

func (m *archDevKitModel) goTo(step archDevKitStep) {
	m.history = append(m.history, m.step)
	m.step = step
	m.prepareStep()
}

func (m *archDevKitModel) back() bool {
	if len(m.history) == 0 {
		return false
	}
	last := len(m.history) - 1
	m.step = m.history[last]
	m.history = m.history[:last]
	m.prepareStep()
	return true
}

func (m *archDevKitModel) prepareStep() {
	q := m.question()
	m.cursor = 0
	for i, opt := range q.options {
		if opt.key == q.current {
			m.cursor = i
			break
		}
	}
	if q.kind == archQuestionValue {
		m.valueInput = q.current
	}
	if q.kind == archQuestionBool && q.current == "0" && len(q.options) > 1 {
		m.cursor = 1
	}
}

func (m archDevKitModel) question() archQuestion {
	switch m.step {
	case archStepTarget:
		current := normalizeArchTarget(m.target)
		if current == "" {
			current = "workstation"
		}
		return archQuestion{kind: archQuestionChoice, title: text("安装目标", "Install Target"), current: current, options: archTargetOptions(true)}
	case archStepCustomTarget:
		current := normalizeArchTarget(m.target)
		if current == "" || current == "custom" {
			current = "workstation"
		}
		return archQuestion{kind: archQuestionChoice, title: text("自定义起点", "Custom Starting Point"), current: current, options: archTargetOptions(false)}
	case archStepArchlinuxcn:
		return archBoolQuestion(text("启用 archlinuxcn 源", "Enable archlinuxcn repository"), "INSTALL_ARCHLINUXCN", m.valueOr("INSTALL_ARCHLINUXCN", "1"))
	case archStepDNS:
		return archBoolQuestion(text("配置系统 DNS", "Configure system DNS"), "ENABLE_DNS", m.valueOr("ENABLE_DNS", "1"))
	case archStepOpsToolkit:
		return archBoolQuestion(text("安装 Ops Toolkit", "Install Ops Toolkit"), "ENABLE_OPS_TOOLKIT", m.valueOr("ENABLE_OPS_TOOLKIT", "1"))
	case archStepProxyBundle:
		return archBoolQuestion(text("安装 Proxy 模块", "Install Proxy module"), "ENABLE_PROXY", m.valueOr("ENABLE_PROXY", "1"))
	case archStepProxyCore:
		return archQuestion{
			kind:    archQuestionChoice,
			title:   text("代理核心", "Proxy Core"),
			current: m.valueOr("PROXY_CORE", "mihomo"),
			envKey:  "PROXY_CORE",
			options: []archOption{
				{"mihomo", text("Mihomo/Clash.Meta 兼容核心，适合规则分流和 MetaCubeXD", "Mihomo/Clash.Meta compatible core for rule routing and MetaCubeXD")},
				{"sing-box", text("sing-box 用户服务，配置更轻量", "sing-box user service with lighter configuration")},
			},
		}
	case archStepProxyService:
		return archBoolQuestion(text("安装后自动启用代理服务", "Enable proxy service after install"), "PROXY_AUTO_ENABLE_SERVICE", m.valueOr("PROXY_AUTO_ENABLE_SERVICE", "1"))
	case archStepMetaCubeXD:
		return archBoolQuestion(text("安装 MetaCubeXD 面板", "Install MetaCubeXD dashboard"), "ENABLE_METACUBEXD", m.valueOr("ENABLE_METACUBEXD", "1"))
	case archStepGPU:
		return archQuestion{
			kind:    archQuestionChoice,
			title:   text("GPU 类型", "GPU Type"),
			current: m.valueOr("GPU_TYPE", "auto"),
			envKey:  "GPU_TYPE",
			options: archGPUOptions(),
		}
	case archStepSDDM:
		return archBoolQuestion(text("启用 SDDM 登录管理器", "Enable SDDM display manager"), "ENABLE_SDDM", m.valueOr("ENABLE_SDDM", "1"))
	case archStepHyprlandConfig:
		return archQuestion{
			kind:    archQuestionChoice,
			title:   text("Hyprland 配置模式", "Hyprland Config Mode"),
			current: m.valueOr("HYPRLAND_CONFIG_MODE", "hyprdots"),
			envKey:  "HYPRLAND_CONFIG_MODE",
			options: []archOption{
				{"hyprdots", text("安装项目内置 hyprdots 配置", "Install bundled hyprdots configuration")},
				{"template", text("安装轻量默认模板", "Install lightweight default template")},
				{"skip", text("只安装软件包，不写入桌面配置", "Install packages only; do not write desktop config")},
			},
		}
	case archStepFcitx5:
		return archBoolQuestion(text("启用 Fcitx5 输入法", "Enable Fcitx5 input method"), "ENABLE_FCITX5", m.valueOr("ENABLE_FCITX5", "1"))
	case archStepInputEngine:
		return archQuestion{
			kind:    archQuestionChoice,
			title:   text("输入法引擎", "Input Method Engine"),
			current: m.valueOr("INPUT_METHOD_ENGINE", "rime"),
			envKey:  "INPUT_METHOD_ENGINE",
			options: []archOption{
				{"rime", text("Fcitx5 + Rime，适合个人方案和可同步配置", "Fcitx5 + Rime for personal schemes and syncable config")},
				{"pinyin", text("Fcitx5 拼音，少配置、轻量使用", "Fcitx5 Pinyin with minimal setup")},
			},
		}
	case archStepRimeSchema:
		return archQuestion{kind: archQuestionValue, title: text("Rime 默认方案", "Default Rime Schema"), current: m.valueOr("RIME_SCHEMA", "luna_pinyin_simp"), envKey: "RIME_SCHEMA"}
	case archStepRimeConfig:
		return archBoolQuestion(text("安装 Rime 配置仓库", "Install Rime config repository"), "INSTALL_RIME_CONFIG", m.valueOr("INSTALL_RIME_CONFIG", "1"))
	case archStepBrowserPackage:
		return archQuestion{kind: archQuestionValue, title: text("浏览器安装包", "Browser Package"), current: m.valueOr("BROWSER_PACKAGE", "google-chrome"), envKey: "BROWSER_PACKAGE"}
	case archStepBrowserApp:
		return archQuestion{kind: archQuestionValue, title: text("浏览器启动命令", "Browser Launch Command"), current: m.valueOr("BROWSER_APP", "google-chrome-stable"), envKey: "BROWSER_APP"}
	case archStepReview:
		return archQuestion{kind: archQuestionReview, title: text("确认 ArchDevKit 选择", "Review ArchDevKit Selection")}
	default:
		return archQuestion{kind: archQuestionReview, title: text("确认 ArchDevKit 选择", "Review ArchDevKit Selection")}
	}
}

func archBoolQuestion(title, envKey, current string) archQuestion {
	current = normalizeArchBool(current, "1")
	return archQuestion{
		kind:    archQuestionBool,
		title:   title,
		current: current,
		envKey:  envKey,
		options: []archOption{
			{"1", text("是", "Yes")},
			{"0", text("否", "No")},
		},
	}
}

func (m archDevKitModel) valueOr(key, fallback string) string {
	if value := strings.TrimSpace(m.values[key]); value != "" {
		return normalizeArchValue(key, value, fallback)
	}
	return fallback
}

func normalizeArchValue(key, value, fallback string) string {
	switch key {
	case "INSTALL_ARCHLINUXCN", "ENABLE_DNS", "ENABLE_OPS_TOOLKIT", "ENABLE_PROXY", "PROXY_AUTO_ENABLE_SERVICE", "ENABLE_METACUBEXD", "ENABLE_SDDM", "ENABLE_FCITX5", "INSTALL_RIME_CONFIG":
		return normalizeArchBool(value, fallback)
	case "PROXY_CORE":
		if value == "mihomo" || value == "sing-box" {
			return value
		}
	case "GPU_TYPE":
		if archOptionHas(archGPUOptions(), value) {
			return value
		}
	case "HYPRLAND_CONFIG_MODE":
		if value == "hyprdots" || value == "template" || value == "skip" {
			return value
		}
	case "INPUT_METHOD_ENGINE":
		if value == "rime" || value == "pinyin" {
			return value
		}
	default:
		if value != "" {
			return value
		}
	}
	return fallback
}

func archOptionHas(options []archOption, key string) bool {
	for _, opt := range options {
		if opt.key == key {
			return true
		}
	}
	return false
}

func archGPUOptions() []archOption {
	return []archOption{
		{"auto", text("自动检测", "Auto detect")},
		{"intel", text("Intel 核显", "Intel integrated graphics")},
		{"amd", text("AMD 显卡", "AMD graphics")},
		{"nvidia", text("NVIDIA 显卡", "NVIDIA graphics")},
		{"vmware", text("VMware 虚拟机", "VMware virtual machine")},
		{"virtio", text("QEMU/KVM virtio", "QEMU/KVM virtio")},
		{"qxl", text("QEMU/KVM QXL", "QEMU/KVM QXL")},
		{"virtualbox", text("VirtualBox 虚拟机", "VirtualBox virtual machine")},
		{"none", text("不安装专用显卡/虚拟机包", "Do not install dedicated graphics or VM packages")},
	}
}

func normalizeArchBool(value, fallback string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "y", "on", "enable", "enabled":
		return "1"
	case "0", "false", "no", "n", "off", "disable", "disabled":
		return "0"
	default:
		return fallback
	}
}

func archTargetOptions(includeCustom bool) []archOption {
	options := []archOption{
		{"base", text("基础环境：基础命令行工具、同步/排障工具和 paru/yay", "Base command-line, sync/troubleshooting tools, and paru/yay")},
		{"dev", text("开发环境：base + archlinuxcn + dns + git + runtime + nvim + docker + fonts + shell + proxy", "Development profile: base + archlinuxcn + dns + git + runtime + nvim + docker + fonts + shell + proxy")},
		{"workstation", text("完整工作站：dev + Hyprland 桌面", "Full workstation: dev + Hyprland desktop")},
	}
	if includeCustom {
		options = append(options, archOption{"custom", text("自定义入口：先选起点，再按后续问题微调", "Custom entry: choose a starting point, then adjust follow-up options")})
	}
	options = append(options,
		archOption{"dns", text("系统 DNS：systemd-resolved、NetworkManager DNS 后端和 fallback DNS", "System DNS: systemd-resolved, NetworkManager DNS backend, and fallback DNS")},
		archOption{"archlinuxcn", text("软件源：archlinuxcn 源、keyring 和可选 mirrorlist", "Repository: archlinuxcn repository, keyring, and optional mirrorlist")},
		archOption{"git", text("Git 环境：git、gh、openssh 和基础 Git 配置", "Git environment: git, gh, OpenSSH, and basic Git config")},
		archOption{"ops-toolkit", text("运维脚本：ops-toolkit 仓库和稳定命令入口", "Ops scripts: ops-toolkit repository and stable command entrypoint")},
		archOption{"runtime", text("开发运行时：nodejs、npm、python、go、mise 和国内镜像", "Development runtime: nodejs, npm, python, go, mise, and China mirrors")},
		archOption{"nvim", text("Neovim：安装 Neovim、个人配置和可选插件同步", "Neovim: install Neovim, personal config, and optional plugin sync")},
		archOption{"docker", text("Docker：docker/compose、镜像源、服务和用户组", "Docker: docker/compose, mirrors, service, and user group")},
		archOption{"fonts", text("字体：中文字体、Emoji、Nerd Font、Monaco 和 fontconfig", "Fonts: Chinese fonts, Emoji, Nerd Font, Monaco, and fontconfig")},
		archOption{"shell", text("Shell：Zsh、Oh My Zsh、Powerlevel10k、插件和默认 shell", "Shell: Zsh, Oh My Zsh, Powerlevel10k, plugins, and default shell")},
		archOption{"desktop", text("桌面：Hyprland、SDDM、Fcitx5/Rime、浏览器、终端和 hyprdots", "Desktop: Hyprland, SDDM, Fcitx5/Rime, browser, terminal, and hyprdots")},
		archOption{"proxy", text("代理：Mihomo 或 sing-box、MetaCubeXD 和 shell 代理环境模板", "Proxy: Mihomo or sing-box, MetaCubeXD, and shell proxy templates")},
	)
	return options
}

func normalizeArchTarget(value string) string {
	value = strings.TrimSpace(value)
	for _, opt := range archTargetOptions(true) {
		if opt.key == value {
			return value
		}
	}
	return ""
}

func (m archDevKitModel) executionEnv() map[string]string {
	keys := m.relevantOverrideOrder()
	env := make(map[string]string, len(keys))
	for _, key := range keys {
		value, ok := m.overrides[key]
		if !ok {
			continue
		}
		env["OS_INIT_ARCHDEVKIT_"+key] = value
	}
	return env
}

func (m archDevKitModel) View() string {
	var b strings.Builder
	w := m.width
	if w <= 0 {
		w = 80
	}

	titleText := HeaderTitleStyle.Render("ArchDevKit")
	byText := HeaderByLineStyle.Render(text(" 原版交互菜单", " Original Flow"))
	headerLeft := lipgloss.JoinHorizontal(lipgloss.Center, titleText, byText)
	b.WriteString(HeaderBorderStyle.Width(w-4).Render(headerLeft) + "\n")

	q := m.question()
	help := []helpAction{
		{key: "↑/↓", desc: text("移动", "move")},
		{key: "Enter", desc: text("确认", "confirm"), tone: helpPrimary},
		{key: "B", desc: text("返回", "back")},
		{key: "Esc", desc: text("主菜单", "main menu")},
	}
	if q.kind == archQuestionValue {
		help = []helpAction{
			{key: "Enter", desc: text("确认", "confirm"), tone: helpPrimary},
			{key: "Ctrl+U", desc: text("清空", "clear")},
			{key: "B", desc: text("返回", "back")},
			{key: "Esc", desc: text("主菜单", "main menu")},
		}
	}
	b.WriteString(renderHelpLine(help...) + "\n\n")

	b.WriteString(MutedStyle.Render(text("  直接回车使用默认值；配置默认值来自 ArchDevKit install_vars 和用户 config.env。", "  Press Enter to use defaults from ArchDevKit install_vars and user config.env.")) + "\n\n")
	b.WriteString(sectionStyle.Render(fmt.Sprintf("  [%s]", q.title)) + "\n\n")

	if m.err != "" {
		b.WriteString("  " + ErrorStyle.Render(m.err) + "\n\n")
	}

	switch q.kind {
	case archQuestionChoice, archQuestionBool:
		for i, opt := range q.options {
			cursor := "  "
			if i == m.cursor {
				cursor = lipgloss.NewStyle().Foreground(ColorAccent).Render("▸ ")
			}
			index := lipgloss.NewStyle().Foreground(ColorAccent2).Render(fmt.Sprintf("%2d.", i+1))
			key := lipgloss.NewStyle().Bold(true).Render(opt.key)
			if q.kind == archQuestionBool {
				key = lipgloss.NewStyle().Bold(true).Render(opt.desc)
			}
			line := fmt.Sprintf("%s%s %-14s", cursor, index, key)
			if q.kind != archQuestionBool {
				line += MutedStyle.Render(opt.desc)
			}
			b.WriteString(line + "\n")
		}
		b.WriteString("\n")
		defaultText := q.current
		if q.kind == archQuestionBool {
			defaultText = boolText(q.current)
		}
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  默认：%s", "  Default: %s"), defaultText)) + "\n")
	case archQuestionValue:
		b.WriteString("  " + lipgloss.NewStyle().Foreground(ColorAccent2).Render("> ") + m.valueInput + "\n\n")
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  默认：%s", "  Default: %s"), q.current)) + "\n")
	case archQuestionReview:
		b.WriteString("  " + lipgloss.NewStyle().Bold(true).Render(text("目标：", "Target: ")) + m.target + "\n\n")
		lines := m.overrideSummary()
		if len(lines) == 0 {
			b.WriteString(MutedStyle.Render(text("  本次没有额外覆盖配置，会使用 ArchDevKit 默认值和用户配置。", "  No extra overrides; ArchDevKit defaults and user config will be used.")) + "\n")
		} else {
			b.WriteString(MutedStyle.Render(text("  本次菜单覆盖：", "  Menu overrides:")) + "\n")
			for _, line := range lines {
				b.WriteString("  " + line + "\n")
			}
		}
		b.WriteString("\n" + OKStyle.Render(text("  按 Enter 进入 os-init 确认页", "  Press Enter to continue to os-init confirmation")) + "\n")
	}

	return b.String()
}

func boolText(value string) string {
	if value == "1" {
		return text("是", "Yes")
	}
	return text("否", "No")
}

func (m archDevKitModel) overrideSummary() []string {
	order := m.relevantOverrideOrder()
	labels := map[string]string{
		"INSTALL_ARCHLINUXCN":       text("archlinuxcn 源", "archlinuxcn repository"),
		"ENABLE_DNS":                text("系统 DNS", "System DNS"),
		"ENABLE_OPS_TOOLKIT":        text("Ops Toolkit", "Ops Toolkit"),
		"ENABLE_PROXY":              text("Proxy 模块", "Proxy module"),
		"PROXY_CORE":                text("代理核心", "Proxy core"),
		"PROXY_AUTO_ENABLE_SERVICE": text("自动启用代理服务", "Auto-enable proxy service"),
		"ENABLE_METACUBEXD":         text("MetaCubeXD 面板", "MetaCubeXD dashboard"),
		"GPU_TYPE":                  text("GPU 类型", "GPU type"),
		"ENABLE_SDDM":               text("SDDM 登录管理器", "SDDM display manager"),
		"HYPRLAND_CONFIG_MODE":      text("Hyprland 配置模式", "Hyprland config mode"),
		"ENABLE_FCITX5":             text("Fcitx5 输入法", "Fcitx5 input method"),
		"INPUT_METHOD_ENGINE":       text("输入法引擎", "Input method engine"),
		"RIME_SCHEMA":               text("Rime 默认方案", "Default Rime schema"),
		"INSTALL_RIME_CONFIG":       text("Rime 配置仓库", "Rime config repository"),
		"BROWSER_PACKAGE":           text("浏览器安装包", "Browser package"),
		"BROWSER_APP":               text("浏览器启动命令", "Browser launch command"),
	}

	var lines []string
	for _, key := range order {
		value, ok := m.overrides[key]
		if !ok {
			continue
		}
		if isArchBoolKey(key) {
			value = boolText(value)
		}
		lines = append(lines, fmt.Sprintf("%s = %s", labels[key], value))
	}
	return lines
}

func (m archDevKitModel) relevantOverrideOrder() []string {
	var order []string
	if m.target == "dev" || m.target == "workstation" {
		order = append(order,
			"INSTALL_ARCHLINUXCN",
			"ENABLE_DNS",
			"ENABLE_OPS_TOOLKIT",
			"ENABLE_PROXY",
		)
	}
	if m.targetNeedsProxy() {
		order = append(order,
			"PROXY_CORE",
			"PROXY_AUTO_ENABLE_SERVICE",
		)
		if m.valueOr("PROXY_CORE", "mihomo") == "mihomo" {
			order = append(order, "ENABLE_METACUBEXD")
		}
	}
	if m.targetNeedsDesktop() {
		order = append(order,
			"GPU_TYPE",
			"ENABLE_SDDM",
			"HYPRLAND_CONFIG_MODE",
			"ENABLE_FCITX5",
		)
		if m.valueOr("ENABLE_FCITX5", "1") == "1" {
			order = append(order, "INPUT_METHOD_ENGINE")
			if m.valueOr("INPUT_METHOD_ENGINE", "rime") == "rime" {
				order = append(order,
					"RIME_SCHEMA",
					"INSTALL_RIME_CONFIG",
				)
			}
		}
		order = append(order,
			"BROWSER_PACKAGE",
			"BROWSER_APP",
		)
	}
	return order
}

func isArchBoolKey(key string) bool {
	switch key {
	case "INSTALL_ARCHLINUXCN", "ENABLE_DNS", "ENABLE_OPS_TOOLKIT", "ENABLE_PROXY", "PROXY_AUTO_ENABLE_SERVICE", "ENABLE_METACUBEXD", "ENABLE_SDDM", "ENABLE_FCITX5", "INSTALL_RIME_CONFIG":
		return true
	default:
		return false
	}
}

func loadArchDevKitSettings(assets fs.FS) map[string]string {
	values := map[string]string{
		"ARCHDEVKIT_DEFAULT_PROFILE": "workstation",
		"INSTALL_ARCHLINUXCN":        "1",
		"ENABLE_DNS":                 "1",
		"ENABLE_OPS_TOOLKIT":         "1",
		"ENABLE_PROXY":               "1",
		"PROXY_CORE":                 "mihomo",
		"PROXY_AUTO_ENABLE_SERVICE":  "1",
		"ENABLE_METACUBEXD":          "1",
		"GPU_TYPE":                   "auto",
		"ENABLE_SDDM":                "1",
		"HYPRLAND_CONFIG_MODE":       "hyprdots",
		"ENABLE_FCITX5":              "1",
		"INPUT_METHOD_ENGINE":        "rime",
		"RIME_SCHEMA":                "luna_pinyin_simp",
		"INSTALL_RIME_CONFIG":        "1",
		"BROWSER_PACKAGE":            "google-chrome",
		"BROWSER_APP":                "google-chrome-stable",
	}

	if assets != nil {
		if data, err := fs.ReadFile(assets, "modules/archdevkit/vendor/install_vars"); err == nil {
			mergeArchAssignments(values, string(data))
		}
	}
	if shouldLoadArchUserConfig() {
		if data, err := os.ReadFile(archUserConfigPath()); err == nil {
			mergeArchAssignments(values, string(data))
		}
	}
	return values
}

func shouldLoadArchUserConfig() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("ARCHDEVKIT_LOAD_CONFIG_FILE"))) {
	case "0", "false", "no", "n", "off", "disable", "disabled":
		return false
	default:
		return true
	}
}

func archUserConfigPath() string {
	if value := strings.TrimSpace(os.Getenv("ARCHDEVKIT_CONFIG_FILE")); value != "" {
		return value
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(".config", "archdevkit", "config.env")
	}
	return filepath.Join(home, ".config", "archdevkit", "config.env")
}

func mergeArchAssignments(values map[string]string, data string) {
	scanner := bufio.NewScanner(strings.NewReader(data))
	for scanner.Scan() {
		key, value, ok := parseArchAssignment(scanner.Text())
		if !ok || !archWizardKey(key) {
			continue
		}
		values[key] = value
	}
}

func parseArchAssignment(line string) (string, string, bool) {
	line = strings.TrimSpace(line)
	line = strings.TrimPrefix(line, "export ")
	if line == "" || strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
		return "", "", false
	}
	key, raw, _ := strings.Cut(line, "=")
	key = strings.TrimSpace(key)
	if key == "" {
		return "", "", false
	}
	value := stripArchInlineComment(strings.TrimSpace(raw))
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		if (value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'') {
			value = value[1 : len(value)-1]
		}
	}
	value = strings.ReplaceAll(value, `\"`, `"`)
	value = strings.ReplaceAll(value, `\\`, `\`)
	return key, value, true
}

func stripArchInlineComment(value string) string {
	inSingle := false
	inDouble := false
	escaped := false
	for i, r := range value {
		if escaped {
			escaped = false
			continue
		}
		if r == '\\' && inDouble {
			escaped = true
			continue
		}
		switch r {
		case '\'':
			if !inDouble {
				inSingle = !inSingle
			}
		case '"':
			if !inSingle {
				inDouble = !inDouble
			}
		case '#':
			if !inSingle && !inDouble {
				return strings.TrimSpace(value[:i])
			}
		}
	}
	return value
}

func archWizardKey(key string) bool {
	switch key {
	case "ARCHDEVKIT_DEFAULT_PROFILE",
		"INSTALL_ARCHLINUXCN",
		"ENABLE_DNS",
		"ENABLE_OPS_TOOLKIT",
		"ENABLE_PROXY",
		"PROXY_CORE",
		"PROXY_AUTO_ENABLE_SERVICE",
		"ENABLE_METACUBEXD",
		"GPU_TYPE",
		"ENABLE_SDDM",
		"HYPRLAND_CONFIG_MODE",
		"ENABLE_FCITX5",
		"INPUT_METHOD_ENGINE",
		"RIME_SCHEMA",
		"INSTALL_RIME_CONFIG",
		"BROWSER_PACKAGE",
		"BROWSER_APP":
		return true
	default:
		return false
	}
}

package tui

import (
	"fmt"
	"io/fs"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	appconfig "github.com/fanhuadesenlinnn/os-init/internal/config"
)

type configStartupModel struct {
	assets  fs.FS
	info    appconfig.Discovery
	summary []appconfig.SummaryItem
	err     string
}

func newConfigStartupModel(assets fs.FS) configStartupModel {
	return configStartupModel{
		assets:  assets,
		info:    appconfig.Discover(),
		summary: appconfig.StartupSummary(),
	}
}

func (m configStartupModel) Init() tea.Cmd { return nil }

func (m configStartupModel) Update(msg tea.Msg) (configStartupModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter", "c":
			if !m.info.HasConfig() {
				if _, err := appconfig.CreateUserConfig(m.assets); err != nil {
					m.err = err.Error()
					return m, nil
				}
				appconfig.Apply(m.assets)
				m.info = appconfig.Discover()
				m.summary = appconfig.StartupSummary()
			}
			return m, func() tea.Msg { return configReadyMsg{} }
		case "s":
			if !m.info.HasConfig() {
				return m, func() tea.Msg { return configReadyMsg{} }
			}
		case "q", "esc":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m configStartupModel) View() string {
	var b strings.Builder
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)

	if m.info.HasConfig() {
		b.WriteString(titleStyle.Render(text("  已加载启动配置", "  Startup Configuration Loaded")) + "\n")
		b.WriteString(MutedStyle.Render(text("  enter 继续 | q 退出", "  enter continue | q quit")) + "\n\n")
		b.WriteString(text("  配置文件\n", "  Configuration files\n"))
		b.WriteString(configPathLine(text("系统配置", "System"), m.info.SystemPath, m.info.SystemExists) + "\n")
		b.WriteString(configPathLine(text("用户配置", "User"), m.info.UserPath, m.info.UserExists) + "\n")
	} else {
		b.WriteString(titleStyle.Render(text("  未发现用户启动配置", "  No Startup Configuration Found")) + "\n")
		b.WriteString(MutedStyle.Render(text("  enter 创建默认配置并继续 | s 跳过 | q 退出", "  enter create default config | s skip | q quit")) + "\n\n")
		b.WriteString(text("  当前将使用程序内置默认配置启动。\n", "  The program will start with the built-in defaults.\n"))
		b.WriteString(text("  建议创建配置文件，用于设置代理、GitHub 代理、下载地址和离线包目录。\n\n", "  Creating a config file is recommended for proxy, GitHub proxy, download URLs, and offline package paths.\n\n"))
		b.WriteString(text("  创建位置\n", "  Create at\n"))
		if m.info.UserPath != "" {
			b.WriteString(HelpKeyStyle.Render("  "+m.info.UserPath) + "\n")
		} else {
			b.WriteString(ErrorStyle.Render(text("  无法确定当前用户配置路径", "  Unable to determine the current user config path")) + "\n")
		}
	}

	if m.err != "" {
		b.WriteString("\n" + ErrorStyle.Render(text("  创建配置失败: ", "  Failed to create config: ")+m.err) + "\n")
	}

	b.WriteString("\n")
	b.WriteString(text("  当前关键配置\n", "  Current key settings\n"))
	for _, item := range m.summary {
		value := item.Value
		if value == "未设置" {
			value = text("未设置", "not set")
		}
		style := MutedStyle
		if value != "" && value != text("未设置", "not set") {
			style = lipgloss.NewStyle().Foreground(ColorAccent2)
		}
		b.WriteString(fmt.Sprintf("  %-20s %s\n", item.Key, style.Render(value)))
	}

	return b.String()
}

func configPathLine(label, path string, exists bool) string {
	if path == "" {
		return fmt.Sprintf("  %-8s %s", label, ErrorStyle.Render(text("无法确定", "unknown")))
	}
	if exists {
		return fmt.Sprintf("  %-8s %s", label, OKStyle.Render(path))
	}
	return fmt.Sprintf("  %-8s %s", label, MutedStyle.Render(path+text(" 未发现", " not found")))
}

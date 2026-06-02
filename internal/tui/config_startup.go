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
		b.WriteString(titleStyle.Render("  已加载启动配置") + "\n")
		b.WriteString(MutedStyle.Render("  enter 继续 | q 退出") + "\n\n")
		b.WriteString("  配置文件\n")
		b.WriteString(configPathLine("系统配置", m.info.SystemPath, m.info.SystemExists) + "\n")
		b.WriteString(configPathLine("用户配置", m.info.UserPath, m.info.UserExists) + "\n")
	} else {
		b.WriteString(titleStyle.Render("  未发现用户启动配置") + "\n")
		b.WriteString(MutedStyle.Render("  enter 创建默认配置并继续 | s 跳过 | q 退出") + "\n\n")
		b.WriteString("  当前将使用程序内置默认配置启动。\n")
		b.WriteString("  建议创建配置文件，用于设置代理、GitHub 代理、下载地址和离线包目录。\n\n")
		b.WriteString("  创建位置\n")
		if m.info.UserPath != "" {
			b.WriteString(HelpKeyStyle.Render("  "+m.info.UserPath) + "\n")
		} else {
			b.WriteString(ErrorStyle.Render("  无法确定当前用户配置路径") + "\n")
		}
	}

	if m.err != "" {
		b.WriteString("\n" + ErrorStyle.Render("  创建配置失败: "+m.err) + "\n")
	}

	b.WriteString("\n")
	b.WriteString("  当前关键配置\n")
	for _, item := range m.summary {
		value := item.Value
		style := MutedStyle
		if value != "" && value != "未设置" {
			style = lipgloss.NewStyle().Foreground(ColorAccent2)
		}
		b.WriteString(fmt.Sprintf("  %-20s %s\n", item.Key, style.Render(value)))
	}

	return b.String()
}

func configPathLine(label, path string, exists bool) string {
	if path == "" {
		return fmt.Sprintf("  %-8s %s", label, ErrorStyle.Render("无法确定"))
	}
	if exists {
		return fmt.Sprintf("  %-8s %s", label, OKStyle.Render(path))
	}
	return fmt.Sprintf("  %-8s %s", label, MutedStyle.Render(path+" 未发现"))
}

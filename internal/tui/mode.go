package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type modeOption struct {
	mode  mode
	label string
	desc  string
}

func modeOptions() []modeOption {
	return []modeOption{
		{modeInstall, text("安装", "Install"), text("全新安装选中的模块", "Install the selected modules")},
		{modeUpdate, text("更新", "Update"), text("更新已经安装的模块", "Update already installed modules")},
		{modeUninstall, text("卸载", "Uninstall"), text("移除选中的模块", "Remove the selected modules")},
	}
}

type modeModel struct {
	cursor int
}

func newModeModel() modeModel { return modeModel{} }

func (m modeModel) Init() tea.Cmd { return nil }

func (m modeModel) Update(msg tea.Msg) (modeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(modeOptions())-1 {
				m.cursor++
			}
		case "enter":
			selected := modeOptions()[m.cursor].mode
			return m, func() tea.Msg { return selectedModeMsg{mode: selected} }
		case "esc":
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		}
	}
	return m, nil
}

func (m modeModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render(text("  选择执行模式", "  Choose an Action")) + "\n")
	b.WriteString(renderHelpLine(
		helpAction{key: "↑/↓", desc: text("移动", "move")},
		helpAction{key: "J/K", desc: text("移动", "move")},
		helpAction{key: "Enter", desc: text("确认", "confirm"), tone: helpPrimary},
		helpAction{key: "Esc", desc: text("返回", "back")},
	) + "\n\n")

	for i, opt := range modeOptions() {
		cursor := "  "
		if i == m.cursor {
			cursor = lipgloss.NewStyle().Foreground(ColorAccent).Render("▸ ")
		}

		label := opt.label
		if i == m.cursor {
			label = lipgloss.NewStyle().Bold(true).Render(label)
		}

		line := fmt.Sprintf("%s%s", cursor, label)
		if opt.desc != "" {
			line += MutedStyle.Render(" — " + opt.desc)
		}
		b.WriteString(line + "\n")
	}

	return b.String()
}

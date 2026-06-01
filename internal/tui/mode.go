package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var modeOptions = []struct {
	mode  mode
	label string
	desc  string
}{
	{modeInstall, "安装", "全新安装选中的模块"},
	{modeUpdate, "更新", "更新已经安装的模块"},
	{modeUninstall, "卸载", "移除选中的模块"},
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
			if m.cursor < len(modeOptions)-1 {
				m.cursor++
			}
		case "enter":
			selected := modeOptions[m.cursor].mode
			return m, tea.Batch(
				func() tea.Msg { return selectedModeMsg{mode: selected} },
				func() tea.Msg {
					if selected == modeUninstall {
						return switchScreenMsg{to: screenConfirm}
					}
					return switchScreenMsg{to: screenGitInfo}
				},
			)
		case "esc":
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		}
	}
	return m, nil
}

func (m modeModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render("  选择执行模式") + "\n")
	b.WriteString(MutedStyle.Render("  ↑/↓ 移动 • enter 确认 • esc 返回") + "\n\n")

	for i, opt := range modeOptions {
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

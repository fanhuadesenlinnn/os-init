package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type confirmModel struct {
	count int
	mode  mode
	err   string
}

func newConfirmModel(count int, m mode) confirmModel {
	return confirmModel{count: count, mode: m}
}

func (m confirmModel) Init() tea.Cmd { return nil }

func (m confirmModel) Update(msg tea.Msg) (confirmModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "y", "Y", "enter":
			return m, func() tea.Msg { return confirmMsg{confirmed: true} }
		case "n", "N", "esc":
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		}
	}
	return m, nil
}

func (m confirmModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render(text("  确认执行", "  Confirm Run")) + "\n\n")

	warnStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorWarn)
	msg := fmt.Sprintf("  将以%s模式执行 %d 个模块，是否继续？", m.mode.String(), m.count)
	if langIsEnglish() {
		msg = fmt.Sprintf("  Run %d modules in %s mode?", m.count, m.mode.String())
	}
	b.WriteString(warnStyle.Render(msg) + "\n\n")

	if m.err != "" {
		b.WriteString(ErrorStyle.Render("  "+m.err) + "\n\n")
	}

	b.WriteString(MutedStyle.Render(text("  y/enter 确认 • n/esc 取消", "  y/enter confirm • n/esc cancel")))

	return b.String()
}

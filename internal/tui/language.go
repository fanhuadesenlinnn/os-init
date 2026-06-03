package tui

import (
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type languageOption struct {
	code        string
	label       string
	description string
}

type languageModel struct {
	cursor  int
	options []languageOption
}

func newLanguageModel() languageModel {
	options := []languageOption{
		{code: "zh_CN", label: "中文", description: "界面、提示和脚本日志优先使用中文"},
		{code: "en_US", label: "English", description: "Use English for interface, prompts, and script logs"},
	}
	cursor := 0
	lang := strings.ToLower(os.Getenv("OS_INIT_LANG"))
	if strings.HasPrefix(lang, "en") {
		cursor = 1
	}
	return languageModel{cursor: cursor, options: options}
}

func (m languageModel) Init() tea.Cmd { return nil }

func (m languageModel) Update(msg tea.Msg) (languageModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.options)-1 {
				m.cursor++
			}
		case "enter", " ":
			code := m.options[m.cursor].code
			return m, func() tea.Msg { return languageSelectedMsg{code: code} }
		case "q", "esc":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m languageModel) View() string {
	var b strings.Builder
	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)

	b.WriteString(titleStyle.Render("  选择语言 / Choose Language") + "\n")
	b.WriteString(MutedStyle.Render("  ↑/↓ 或 j/k 移动 | enter 确认 | q 退出") + "\n\n")

	for i, option := range m.options {
		cursor := "  "
		style := lipgloss.NewStyle()
		if i == m.cursor {
			cursor = HelpKeyStyle.Render("› ")
			style = lipgloss.NewStyle().Bold(true).Foreground(ColorAccent2)
		}
		b.WriteString(cursor + style.Render(option.label) + "\n")
		b.WriteString("    " + MutedStyle.Render(option.description) + "\n")
	}

	b.WriteString("\n")
	b.WriteString(MutedStyle.Render("  The selected language applies before loading the startup configuration."))
	return b.String()
}

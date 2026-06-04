package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type helpTone int

const (
	helpNeutral helpTone = iota
	helpPrimary
	helpWarn
	helpDanger
)

type helpAction struct {
	key  string
	desc string
	tone helpTone
}

func renderHelpLine(actions ...helpAction) string {
	return "  " + renderHelpActions(actions...)
}

func renderHelpActions(actions ...helpAction) string {
	segments := make([]string, 0, len(actions))
	for _, action := range actions {
		if action.key == "" {
			continue
		}
		segments = append(segments, renderHelpAction(action))
	}
	return strings.Join(segments, HelpSepStyle.Render("   "))
}

func renderHelpAction(action helpAction) string {
	keyStyle := HelpKeyStyle
	descStyle := HelpDescStyle
	switch action.tone {
	case helpPrimary:
		keyStyle = HelpPrimaryKeyStyle
		descStyle = lipgloss.NewStyle().Foreground(ColorBarFg)
	case helpWarn:
		keyStyle = HelpWarnKeyStyle
		descStyle = lipgloss.NewStyle().Foreground(ColorBarFg)
	case helpDanger:
		keyStyle = HelpDangerKeyStyle
		descStyle = lipgloss.NewStyle().Foreground(ColorBarFg)
	}

	if action.desc == "" {
		return keyStyle.Render("[" + action.key + "]")
	}
	return keyStyle.Render("["+action.key+"]") + " " + descStyle.Render(action.desc)
}

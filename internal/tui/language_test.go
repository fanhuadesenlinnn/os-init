package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestLanguageModel_DefaultsToChinese(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "")

	model := newLanguageModel()
	if got := model.options[model.cursor].code; got != "zh_CN" {
		t.Fatalf("default language = %q, want zh_CN", got)
	}
}

func TestLanguageModel_UsesEnglishEnvAsDefault(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	model := newLanguageModel()
	if got := model.options[model.cursor].code; got != "en_US" {
		t.Fatalf("default language = %q, want en_US", got)
	}
}

func TestLanguageModel_EnterSelectsLanguage(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "")

	model := newLanguageModel()
	_, cmd := model.Update(tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil {
		t.Fatal("expected language selection command")
	}
	msg := cmd()
	selected, ok := msg.(languageSelectedMsg)
	if !ok {
		t.Fatalf("unexpected message type %T", msg)
	}
	if selected.code != "zh_CN" {
		t.Fatalf("selected language = %q, want zh_CN", selected.code)
	}
}

func TestNewModel_StartsWithLanguageSelection(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "")

	model := New(Config{})
	if model.screen != screenLanguage {
		t.Fatalf("initial screen = %v, want screenLanguage", model.screen)
	}
	if view := model.View(); !strings.Contains(view, "选择语言 / Choose Language") {
		t.Fatalf("initial view should ask for language, got %q", view)
	}
}

func TestText_UsesEnglishWhenSelected(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	if got := text("中文", "English"); got != "English" {
		t.Fatalf("text() = %q, want English", got)
	}
	if got := moduleSection("软件安装"); got != "Software Installation" {
		t.Fatalf("moduleSection() = %q, want Software Installation", got)
	}
}

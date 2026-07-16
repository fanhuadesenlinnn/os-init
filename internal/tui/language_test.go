package tui

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	appconfig "github.com/fanhuadesenlinnn/os-init/internal/config"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/runtimecontext"
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

func TestModelPassesSelectedLanguageToConfigCreation(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")
	t.Cleanup(func() { appconfig.SetRuntimeOverride("OS_INIT_LANG", "zh_CN") })
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}
	model := New(Config{Runtime: runtimecontext.Context{Target: target}})

	next, _ := model.Update(languageSelectedMsg{code: "en_US"})
	got := next.(Model)
	if got.configStartup.lang != "en_US" {
		t.Fatalf("config language = %q, want en_US", got.configStartup.lang)
	}
	if !reflect.DeepEqual(got.configStartup.target, target) {
		t.Fatalf("config target = %#v, want %#v", got.configStartup.target, target)
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

func TestEnglishModuleTranslationsCoverRegistry(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	for _, mod := range modules.AllModules() {
		if containsHan(moduleLabel(mod.ID, mod.Label)) {
			t.Errorf("module %s has an untranslated label: %q", mod.ID, moduleLabel(mod.ID, mod.Label))
		}
		if containsHan(moduleDescription(mod.ID, mod.Description)) {
			t.Errorf("module %s has an untranslated description: %q", mod.ID, moduleDescription(mod.ID, mod.Description))
		}
	}
}

func TestModel_SudoFailureReturnsToConfirm(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	model := New(Config{})
	model.screen = screenConfirm
	model.confirm = newConfirmModel(2, modeInstall)

	next, _ := model.Update(sudoDoneMsg{err: errors.New("exit status 1")})
	got := next.(Model)
	if got.screen != screenConfirm {
		t.Fatalf("screen = %v, want screenConfirm", got.screen)
	}
	if !strings.Contains(got.confirm.err, "sudo 验证失败") {
		t.Fatalf("confirm error = %q, want sudo failure", got.confirm.err)
	}
}

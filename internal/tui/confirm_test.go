package tui

import (
	"strings"
	"testing"
)

func TestConfirmView_RendersActionKeys(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	view := newConfirmModel(3, modeInstall).View()
	for _, want := range []string{"[Y]", "[Enter]", "确认执行", "[N]", "[Esc]"} {
		if !strings.Contains(view, want) {
			t.Fatalf("confirm view should contain %q, got %q", want, view)
		}
	}
}

func TestConfirmView_UninstallUsesSpecificActionText(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	view := newConfirmModel(1, modeUninstall).View()
	if !strings.Contains(view, "确认卸载") {
		t.Fatalf("uninstall confirm view should use uninstall wording, got %q", view)
	}
}

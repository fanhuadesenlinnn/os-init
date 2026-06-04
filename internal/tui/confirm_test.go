package tui

import (
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
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

func TestConfirmView_ShowsPrivilegeReasons(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	mod := modules.Module{
		ID:              "docker",
		Label:           "Docker",
		Privilege:       modules.PrivilegeSystem,
		PrivilegeReason: "写入 systemd 服务",
		OS:              "linux",
	}
	model := newConfirmModelForSelection(
		[]modules.Module{mod},
		modeInstall,
		platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"},
	)
	view := model.View()
	if !strings.Contains(view, "需要 sudo 的模块") || !strings.Contains(view, "写入 systemd 服务") {
		t.Fatalf("confirm view should show privilege reason, got %q", view)
	}
}

func TestSelectionNeedsSudoPrime_IsPlatformAware(t *testing.T) {
	mods := modules.AllModules()
	byID := map[string]modules.Module{}
	for _, m := range mods {
		byID[m.ID] = m
	}

	darwin := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}
	linux := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}

	if selectionNeedsSudoPrime([]modules.Module{byID["yazi"]}, darwin) {
		t.Fatal("macOS Yazi should not trigger sudo prime")
	}
	if !selectionNeedsSudoPrime([]modules.Module{byID["yazi"]}, linux) {
		t.Fatal("Linux Yazi should trigger sudo prime")
	}
}

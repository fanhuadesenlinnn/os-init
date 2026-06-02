package modules_test

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestAllModules_ReturnsNonEmpty(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	if len(mods) == 0 {
		t.Fatal("expected non-empty module list")
	}
}

func TestAllModules_HasOptimizationsAndInstallations(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	hasOpt := false
	hasInst := false
	for _, m := range mods {
		if m.Category == "optimization" {
			hasOpt = true
		}
		if m.Category == "installation" {
			hasInst = true
		}
	}
	if !hasOpt {
		t.Error("expected at least one optimization module")
	}
	if !hasInst {
		t.Error("expected at least one installation module")
	}
}

func TestForOS_ReturnsNoModulesForNonLinux(t *testing.T) {
	t.Parallel()

	mods := modules.ForOS("darwin")
	if len(mods) != 0 {
		t.Fatalf("expected no modules on non-Linux targets, got %d", len(mods))
	}
}

func TestForOS_IncludesLinuxModulesOnLinux(t *testing.T) {
	t.Parallel()

	mods := modules.ForOS("linux")
	hasLinux := false
	for _, m := range mods {
		if m.OS == "linux" {
			hasLinux = true
		}
	}
	if !hasLinux {
		t.Error("expected linux-specific modules on linux")
	}
}

func TestNeedsSudo_AllowedModulesOnly(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	for _, m := range mods {
		if m.NeedsSudo {
			t.Errorf("module %q should not require sudo in the registry", m.ID)
		}
	}
}

func TestAllModules_RegisteredScriptsExist(t *testing.T) {
	t.Parallel()

	for _, m := range modules.AllModules() {
		scriptPath := filepath.Join("..", "..", "modules", filepath.FromSlash(m.Script))
		if _, err := os.Stat(scriptPath); err != nil {
			t.Errorf("registered script for module %q does not exist: %s", m.ID, m.Script)
		}
	}
}

func TestAllModules_DoesNotRegisterSSHD(t *testing.T) {
	t.Parallel()

	for _, m := range modules.AllModules() {
		if m.ID == "sshd" {
			t.Fatal("sshd hardening module should not be registered")
		}
	}
}

func TestGroupByScript_MergesComponents(t *testing.T) {
	t.Parallel()
	selected := []modules.Module{
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}},
		{ID: "shell-fzf", Script: "shell/install.sh", Components: []string{"fzf"}},
		{ID: "docker", Script: "docker/install.sh"},
	}
	groups := modules.GroupByScript(selected)
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	if len(groups[0].Components) != 2 {
		t.Errorf("expected 2 components for shell, got %d", len(groups[0].Components))
	}
	if groups[0].Components[0] != "zsh" || groups[0].Components[1] != "fzf" {
		t.Errorf("wrong components: %v", groups[0].Components)
	}
	if len(groups[1].Components) != 0 {
		t.Errorf("docker should have no components, got %v", groups[1].Components)
	}
}

func TestNeedsUserInfo_ShellGitOnly(t *testing.T) {
	t.Parallel()
	if modules.NeedsUserInfo([]modules.Module{{ID: "docker"}}) {
		t.Error("docker should not need user info")
	}
	if !modules.NeedsUserInfo([]modules.Module{{ID: "shell-git"}}) {
		t.Error("shell-git should need user info")
	}
}

func TestNeedsWebhook_ReturnsFalseWithoutWebhookModules(t *testing.T) {
	t.Parallel()
	for _, m := range modules.AllModules() {
		if modules.NeedsWebhook([]modules.Module{m}) {
			t.Errorf("module %q should not need webhook", m.ID)
		}
	}
}

func TestInstallSubsections_ReturnsCurrentGroups(t *testing.T) {
	t.Parallel()

	want := []string{"Shell 工具", "终端工具", "网络代理", "开发工具"}
	if got := modules.InstallSubsections(); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected install subsections: got %v, want %v", got, want)
	}
}

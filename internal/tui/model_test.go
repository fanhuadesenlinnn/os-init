package tui

import (
	"errors"
	"io/fs"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

type failingFS struct{}

func (failingFS) Open(string) (fs.File, error) {
	return nil, errors.New("broken assets")
}

func TestStartExecutionReportsAssetExtractionFailure(t *testing.T) {
	m := Model{config: Config{Assets: failingFS{}}, selectedModules: []modules.Module{{ID: "test", Label: "Test"}}}
	defer func() {
		if recovered := recover(); recovered != nil {
			t.Fatalf("startExecution panicked instead of reporting extraction failure: %v", recovered)
		}
	}()
	next, _ := m.startExecution()
	if next.screen != screenSummary || len(next.summary.results) != 1 || next.summary.results[0].ExitCode == 0 {
		t.Fatalf("extraction failure summary = %+v", next.summary)
	}
}

func TestResolveForContextSharesArchMiseAndHidesStandaloneGo(t *testing.T) {
	mods := []modules.Module{
		{ID: "shell-zsh", Category: "installation"},
		{ID: "arch-base", Category: "installation"},
		{ID: "kernel-sysctl", Category: "optimization"},
		{ID: "arch-mise", Category: "installation"},
		{ID: "go", Category: "installation"},
	}

	rootMods := modules.ResolveForContext(mods, true)
	if len(rootMods) != 4 || rootMods[1].ID != "arch-base" || rootMods[3].ID != "arch-mise" {
		t.Fatalf("root modules = %#v", rootMods)
	}

	normalMods := modules.ResolveForContext(mods, false)
	if len(normalMods) != 4 || normalMods[1].ID != "arch-base" || normalMods[3].ID != "arch-mise" {
		t.Fatalf("normal user modules were unexpectedly filtered: %#v", normalMods)
	}
}

func TestResolveForContextRemovesDockerReloginForRoot(t *testing.T) {
	mods := []modules.Module{{
		ID:           "docker",
		Category:     "installation",
		NeedsRelogin: true,
		Activates:    []string{modules.ActivationSystemd, modules.ActivationRelogin},
		Verify:       modules.UserGroup("docker"),
	}}
	rootMods := modules.ResolveForContext(mods, true)
	if len(rootMods) != 1 || rootMods[0].NeedsRelogin || !rootMods[0].Verify.Empty() {
		t.Fatalf("root Docker module = %#v", rootMods)
	}
	if len(rootMods[0].Activates) != 1 || rootMods[0].Activates[0] != modules.ActivationSystemd {
		t.Fatalf("root Docker activations = %#v", rootMods[0].Activates)
	}
	if !mods[0].NeedsRelogin || len(mods[0].Activates) != 2 || mods[0].Verify.Kind != modules.CheckUserGroup {
		t.Fatal("filter mutated the source module")
	}
}

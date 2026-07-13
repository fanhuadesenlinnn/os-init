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

func TestFilterModulesForExecutionUserRemovesArchDevKitForRoot(t *testing.T) {
	mods := []modules.Module{
		{ID: "shell-zsh", Category: "installation"},
		{ID: "archdevkit-menu", Category: "archdevkit"},
		{ID: "kernel-sysctl", Category: "optimization"},
	}

	rootMods := filterModulesForExecutionUser(mods, true)
	if len(rootMods) != 2 || rootMods[0].ID != "shell-zsh" || rootMods[1].ID != "kernel-sysctl" {
		t.Fatalf("root modules = %#v", rootMods)
	}

	normalMods := filterModulesForExecutionUser(mods, false)
	if len(normalMods) != len(mods) {
		t.Fatalf("normal user modules were unexpectedly filtered: %#v", normalMods)
	}
}

func TestFilterModulesForExecutionUserRemovesDockerReloginForRoot(t *testing.T) {
	mods := []modules.Module{{
		ID:                  "docker",
		Category:            "installation",
		NeedsRelogin:        true,
		Activates:           []string{modules.ActivationSystemd, modules.ActivationRelogin},
		InstalledUserGroups: []string{"docker"},
	}}
	rootMods := filterModulesForExecutionUser(mods, true)
	if len(rootMods) != 1 || rootMods[0].NeedsRelogin || len(rootMods[0].InstalledUserGroups) != 0 {
		t.Fatalf("root Docker module = %#v", rootMods)
	}
	if len(rootMods[0].Activates) != 1 || rootMods[0].Activates[0] != modules.ActivationSystemd {
		t.Fatalf("root Docker activations = %#v", rootMods[0].Activates)
	}
	if !mods[0].NeedsRelogin || len(mods[0].Activates) != 2 || len(mods[0].InstalledUserGroups) != 1 {
		t.Fatal("filter mutated the source module")
	}
}

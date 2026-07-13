package planner_test

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestBuild_AddsStrongDependenciesForInstall(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["shell-autosuggestions"]},
		target,
		planner.Options{Mode: planner.ModeInstall},
	)

	if !hasModule(plan.Modules, "shell-zsh") {
		t.Fatalf("plan should add shell-zsh dependency, got %v", ids(plan.Modules))
	}
	if got, want := ids(plan.Modules), []string{"shell-zsh", "shell-autosuggestions"}; !sameOrderPrefix(got, want) {
		t.Fatalf("plan order = %v, want prefix %v", got, want)
	}
	if len(plan.AddedDependencies) != 1 {
		t.Fatalf("added dependencies = %v, want 1", plan.AddedDependencies)
	}
	if plan.AddedDependencies[0].ModuleID != "shell-zsh" {
		t.Fatalf("added dependency = %q, want shell-zsh", plan.AddedDependencies[0].ModuleID)
	}
}

func TestBuild_AddsStarshipForTerminalStyleWithoutForcingZsh(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["terminal-style"]},
		target,
		planner.Options{Mode: planner.ModeInstall},
	)

	if !hasModule(plan.Modules, "shell-starship") {
		t.Fatalf("plan should add shell-starship dependency, got %v", ids(plan.Modules))
	}
	if hasModule(plan.Modules, "shell-zsh") {
		t.Fatalf("terminal style should not force shell-zsh, got %v", ids(plan.Modules))
	}
	if got, want := ids(plan.Modules), []string{"shell-starship", "terminal-style"}; !sameOrderPrefix(got, want) {
		t.Fatalf("plan order = %v, want prefix %v", got, want)
	}
}

func TestBuild_DoesNotAddStrongDependenciesForUninstall(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["shell-autosuggestions"]},
		target,
		planner.Options{Mode: planner.ModeUninstall},
	)

	if hasModule(plan.Modules, "shell-zsh") {
		t.Fatalf("uninstall plan should not add shell-zsh, got %v", ids(plan.Modules))
	}
	if len(plan.AddedDependencies) != 0 {
		t.Fatalf("uninstall plan should not add dependencies, got %v", plan.AddedDependencies)
	}
}

func TestBuild_ExpandsArchWorkstationPreset(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["arch-workstation"]},
		target,
		planner.Options{Mode: planner.ModeInstall},
	)

	if _, ok := plan.BlockingIssue(); ok {
		t.Fatalf("Arch preset should compose with normal modules: %#v", plan.Issues)
	}
	for _, id := range []string{"arch-dev", "arch-desktop", "arch-mise", "docker", "neovim"} {
		if !hasModule(plan.Modules, id) {
			t.Fatalf("expanded preset missing %s: %v", id, ids(plan.Modules))
		}
	}
}

func TestBuild_SuggestsSoftAssociationForDocker(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["docker"]},
		target,
		planner.Options{Mode: planner.ModeInstall},
	)

	if len(plan.SoftAssociations) != 1 {
		t.Fatalf("soft associations = %v, want 1", plan.SoftAssociations)
	}
	if plan.SoftAssociations[0].SuggestedID != "network-tune" {
		t.Fatalf("suggested module = %q, want network-tune", plan.SoftAssociations[0].SuggestedID)
	}
}

func TestBuild_DoesNotSuggestAlreadySelectedAssociation(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["docker"], byID["network-tune"]},
		target,
		planner.Options{Mode: planner.ModeInstall},
	)

	if len(plan.SoftAssociations) != 0 {
		t.Fatalf("soft associations should be empty when suggestion is selected, got %v", plan.SoftAssociations)
	}
}

func modulesByID(mods []modules.Module) map[string]modules.Module {
	out := map[string]modules.Module{}
	for _, m := range mods {
		out[m.ID] = m
	}
	return out
}

func hasModule(mods []modules.Module, id string) bool {
	for _, m := range mods {
		if m.ID == id {
			return true
		}
	}
	return false
}

func ids(mods []modules.Module) []string {
	out := make([]string, 0, len(mods))
	for _, m := range mods {
		out = append(out, m.ID)
	}
	return out
}

func sameOrderPrefix(got, want []string) bool {
	if len(got) < len(want) {
		return false
	}
	for i := range want {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

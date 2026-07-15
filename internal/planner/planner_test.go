package planner_test

import (
	"reflect"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestBuild_AddsStrongDependenciesForInstall(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["arch-ops-toolkit"]},
		target,
		planner.Options{Operation: modules.OperationInstall},
	)

	if !hasModule(plan.Modules, "arch-git") {
		t.Fatalf("plan should add arch-git dependency, got %v", ids(plan.Modules))
	}
	if got, want := ids(plan.Modules), []string{"arch-git", "arch-ops-toolkit"}; !sameOrderPrefix(got, want) {
		t.Fatalf("plan order = %v, want prefix %v", got, want)
	}
	if len(plan.AddedDependencies) != 1 {
		t.Fatalf("added dependencies = %v, want 1", plan.AddedDependencies)
	}
	if plan.AddedDependencies[0].ModuleID != "arch-git" {
		t.Fatalf("added dependency = %q, want arch-git", plan.AddedDependencies[0].ModuleID)
	}
}

func TestBuild_DoesNotAddStrongDependenciesForUninstall(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["arch-ops-toolkit"]},
		target,
		planner.Options{Operation: modules.OperationUninstall},
	)

	if hasModule(plan.Modules, "arch-git") {
		t.Fatalf("uninstall plan should not add arch-git, got %v", ids(plan.Modules))
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
		planner.Options{Operation: modules.OperationInstall},
	)

	if _, ok := plan.BlockingIssue(); ok {
		t.Fatalf("Arch preset should compose with normal modules: %#v", plan.Issues)
	}
	for _, id := range []string{"arch-desktop", "mise", "mise-go", "mise-python", "mise-node", "docker", "neovim", "arch-mihomo"} {
		if !hasModule(plan.Modules, id) {
			t.Fatalf("expanded preset missing %s: %v", id, ids(plan.Modules))
		}
	}
	if hasModule(plan.Modules, "arch-dev") || hasModule(plan.Modules, "arch-workstation") {
		t.Fatalf("dependency-only presets must not reach execution: %v", ids(plan.Modules))
	}
}

func TestBuild_ExpandsDependenciesForStandaloneArchMihomo(t *testing.T) {
	t.Parallel()
	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))
	plan := planner.Build([]modules.Module{byID["arch-mihomo"]}, target, planner.Options{Operation: modules.OperationInstall})
	if _, ok := plan.BlockingIssue(); ok {
		t.Fatalf("Arch Mihomo plan should be valid: %#v", plan.Issues)
	}
	for _, id := range []string{"arch-archlinuxcn", "arch-aur", "arch-mihomo"} {
		if !hasModule(plan.Modules, id) {
			t.Fatalf("standalone Arch Mihomo missing %s: %v", id, ids(plan.Modules))
		}
	}
}

func TestBuild_BlocksUnsupportedArchUninstall(t *testing.T) {
	t.Parallel()
	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))
	plan := planner.Build([]modules.Module{byID["arch-base"]}, target, planner.Options{Operation: modules.OperationUninstall})
	if issue, ok := plan.BlockingIssue(); !ok || len(issue.ModuleIDs) != 1 || issue.ModuleIDs[0] != "arch-base" {
		t.Fatalf("unsupported uninstall should be blocked before execution: %#v", plan.Issues)
	}
}

func TestBuild_BlocksMixedActionsAndModules(t *testing.T) {
	t.Parallel()
	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))
	plan := planner.Build(
		[]modules.Module{byID["arch-doctor"], byID["arch-base"]},
		target,
		planner.Options{Operation: modules.OperationInstall},
	)
	if _, ok := plan.BlockingIssue(); !ok {
		t.Fatalf("actions and lifecycle modules must not share a batch: %#v", plan)
	}
}

func TestOrderUsesPhaseInsteadOfLocalizedSubsection(t *testing.T) {
	t.Parallel()
	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	late := modules.Module{ID: "late", Label: "late", Category: "installation", Subsection: "任意文案", OS: "linux", Phase: modules.PhaseApplication, SupportedOperations: []modules.Operation{modules.OperationInstall}}
	early := modules.Module{ID: "early", Label: "early", Category: "installation", Subsection: "Another label", OS: "linux", Phase: modules.PhaseBootstrap, SupportedOperations: []modules.Operation{modules.OperationInstall}}
	plan := planner.Build([]modules.Module{late, early}, target, planner.Options{Operation: modules.OperationInstall})
	if got := ids(plan.Modules); !reflect.DeepEqual(got, []string{"early", "late"}) {
		t.Fatalf("phase order = %v", got)
	}
}

func TestBuild_SuggestsSoftAssociationForDocker(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	byID := modulesByID(modules.ForTarget(target))

	plan := planner.Build(
		[]modules.Module{byID["docker"]},
		target,
		planner.Options{Operation: modules.OperationInstall},
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
		planner.Options{Operation: modules.OperationInstall},
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

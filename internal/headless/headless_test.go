package headless

import (
	"bytes"
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestBuildPlanResolvesAvailableModule(t *testing.T) {
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	plan, mods, err := BuildPlan(target, []string{"terminal-ncdu"}, false, modules.OperationInstall)
	if err != nil {
		t.Fatal(err)
	}
	if len(mods) != 1 || mods[0].ID != "terminal-ncdu" {
		t.Fatalf("unexpected plan: %+v", plan)
	}
	if len(plan.Requested) != 1 || plan.Requested[0] != "terminal-ncdu" {
		t.Fatalf("requested = %#v", plan.Requested)
	}
}

func TestBuildPlanRejectsUnavailableModule(t *testing.T) {
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	if _, _, err := BuildPlan(target, []string{"docker"}, false, modules.OperationInstall); err == nil {
		t.Fatal("expected unavailable module error")
	}
}

func TestBuildPlanAcceptsLegacyModuleAliases(t *testing.T) {
	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd", Environment: platform.EnvironmentNative}
	plan, mods, err := BuildPlan(target, []string{"arch-git", "arch-mihomo"}, false, modules.OperationInstall)
	if err != nil {
		t.Fatal(err)
	}
	if !containsModuleID(mods, "git") || !containsModuleID(mods, "mihomo") {
		t.Fatalf("legacy aliases were not canonicalized: plan=%+v modules=%v", plan, mods)
	}
	if containsModuleID(mods, "arch-git") || containsModuleID(mods, "arch-mihomo") {
		t.Fatalf("legacy IDs must not reach execution: %v", mods)
	}
}

func containsModuleID(items []modules.Module, id string) bool {
	for _, item := range items {
		if item.ID == id {
			return true
		}
	}
	return false
}

func TestExecuteUsesEmbeddedProviderAndReportsResult(t *testing.T) {
	assets := fstest.MapFS{
		"modules/provider.sh": &fstest.MapFile{Data: []byte("#!/usr/bin/env bash\n[[ -n \"${OS_INIT_PACKAGE_METADATA_STAMP:-}\" ]]\n"), Mode: fs.FileMode(0o755)},
	}
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	report, err := Execute(context.Background(), Options{
		Assets: assets, Target: target, ModuleIDs: []string{"terminal-ncdu"},
		Operation: modules.OperationInstall, Verify: false, Quiet: true,
		LogDir: t.TempDir(), Timeout: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !report.Success || len(report.Results) != 1 || report.Results[0].Status != "passed" {
		t.Fatalf("report = %+v", report)
	}
}

func TestExecutePropagatesProviderFailure(t *testing.T) {
	assets := fstest.MapFS{
		"modules/provider.sh": &fstest.MapFile{Data: []byte("#!/usr/bin/env bash\nexit 42\n"), Mode: fs.FileMode(0o755)},
	}
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	report, err := Execute(context.Background(), Options{
		Assets: assets, Target: target, ModuleIDs: []string{"terminal-ncdu"},
		Operation: modules.OperationInstall, Verify: false, Quiet: true,
		LogDir: t.TempDir(), Timeout: time.Second,
	})
	if err == nil {
		t.Fatal("expected provider failure")
	}
	if report.Success || len(report.Results) != 1 {
		t.Fatalf("report = %+v", report)
	}
	if got := report.Results[0]; got.Status != "failed" || got.ExitCode != 42 {
		t.Fatalf("result = %+v", got)
	}
}

func TestWriteJUnitIncludesFailure(t *testing.T) {
	report := Report{
		StartedAt: time.Unix(1, 0), FinishedAt: time.Unix(2, 0),
		Results: []StepResult{{ModuleID: "docker", Operation: "install", Status: "failed", Error: "boom"}},
	}
	var output bytes.Buffer
	if err := WriteJUnit(&output, report); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`tests="1"`, `failures="1"`, `docker/install`, `message="boom"`} {
		if !bytes.Contains(output.Bytes(), []byte(want)) {
			t.Fatalf("JUnit output does not contain %q:\n%s", want, output.String())
		}
	}
}

func TestLifecycleRestoresPreexistingInstalledState(t *testing.T) {
	assets := fstest.MapFS{
		"modules/provider.sh": &fstest.MapFile{Data: []byte("#!/usr/bin/env bash\nexit 0\n"), Mode: fs.FileMode(0o755)},
	}
	bin := t.TempDir()
	ncdu := filepath.Join(bin, "ncdu")
	if err := os.WriteFile(ncdu, []byte("#!/usr/bin/env bash\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	report, err := TestLifecycle(context.Background(), LifecycleOptions{
		Options: Options{
			Assets: assets, Target: target, ModuleIDs: []string{"terminal-ncdu"},
			Quiet: true, LogDir: t.TempDir(), Timeout: time.Second,
		},
		Phases: []string{"install", "uninstall"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Results) != 2 {
		t.Fatalf("results = %+v", report.Results)
	}
	uninstall := report.Results[1]
	if uninstall.Status != "passed" || !uninstall.ExpectedInstalled || !uninstall.VerifyPassed {
		t.Fatalf("uninstall result = %+v", uninstall)
	}
}

func TestLifecycleRejectsUnknownPhase(t *testing.T) {
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	report, err := TestLifecycle(context.Background(), LifecycleOptions{
		Options: Options{Target: target, ModuleIDs: []string{"terminal-ncdu"}, Quiet: true},
		Phases:  []string{"instlal"},
	})
	if err == nil || report.Success {
		t.Fatalf("report=%+v err=%v", report, err)
	}
}

func TestCatalogDeclaresAutomationBoundaries(t *testing.T) {
	target := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}
	byID := map[string]CatalogEntry{}
	for _, entry := range Catalog(target) {
		byID[entry.ID] = entry
	}
	if byID["arch-desktop"].AutomationScope != "manual" {
		t.Fatalf("arch desktop automation = %+v", byID["arch-desktop"])
	}
	if byID["docker"].AutomationScope != "hosted" {
		t.Fatalf("docker automation = %+v", byID["docker"])
	}
}

func TestMacOSSpecificModulesRequireHostedRunner(t *testing.T) {
	target := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"}
	for _, entry := range Catalog(target) {
		if entry.ID == "macos-codex" {
			if entry.AutomationScope != "hosted" {
				t.Fatalf("macos codex automation = %+v", entry)
			}
			return
		}
	}
	t.Fatal("macos-codex not found")
}

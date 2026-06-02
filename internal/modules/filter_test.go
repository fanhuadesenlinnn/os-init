package modules

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestModuleMatchesTarget_UsesOSFallback(t *testing.T) {
	t.Parallel()

	linux := platform.Target{GOOS: "linux", Family: platform.FamilyDebian}
	darwin := platform.Target{GOOS: "darwin", Family: platform.FamilyUnknown}

	if !moduleMatchesTarget(Module{OS: "linux"}, linux) {
		t.Fatal("linux module should match linux target")
	}
	if moduleMatchesTarget(Module{OS: "linux"}, darwin) {
		t.Fatal("linux module should not match darwin target")
	}
	if moduleMatchesTarget(Module{OS: "all"}, darwin) {
		t.Fatal("all module should not match non-Linux targets")
	}
}

func TestModuleMatchesTarget_UsesFamiliesWhenPresent(t *testing.T) {
	t.Parallel()

	mod := Module{OS: "linux", Families: []string{"debian", "arch"}}

	if !moduleMatchesTarget(mod, platform.Target{GOOS: "linux", Family: platform.FamilyArch}) {
		t.Fatal("module should match arch family")
	}
	if !moduleMatchesTarget(mod, platform.Target{GOOS: "linux", Family: platform.FamilyDebian}) {
		t.Fatal("module should match debian family")
	}
	if moduleMatchesTarget(mod, platform.Target{GOOS: "linux", Family: platform.FamilyRedHat}) {
		t.Fatal("module should not match redhat family")
	}
}

func TestModuleMatchesTarget_RequiresSystemd(t *testing.T) {
	t.Parallel()

	mod := Module{OS: "linux", Requires: []string{"systemd"}}

	if !moduleMatchesTarget(mod, platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}) {
		t.Fatal("module should match systemd target")
	}
	if moduleMatchesTarget(mod, platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "openrc"}) {
		t.Fatal("module should not match non-systemd target")
	}
}

func TestForTarget_IncludesMihomoOnlyOnLinuxSystemdFamilies(t *testing.T) {
	t.Parallel()

	systemd := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"})
	if !hasModule(systemd, "mihomo") {
		t.Fatal("mihomo should appear on Debian-family systemd targets")
	}

	openrc := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "openrc"})
	if hasModule(openrc, "mihomo") {
		t.Fatal("mihomo should be hidden on non-systemd targets")
	}

	darwin := ForTarget(platform.Target{GOOS: "darwin", Family: platform.FamilyUnknown, Init: "unknown"})
	if len(darwin) != 0 {
		t.Fatal("non-Linux targets should not receive any modules")
	}
}

func hasModule(mods []Module, id string) bool {
	for _, m := range mods {
		if m.ID == id {
			return true
		}
	}
	return false
}

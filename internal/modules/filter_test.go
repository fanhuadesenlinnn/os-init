package modules

import (
	"testing"

	"github.com/dpanic/os-kickstart/internal/platform"
)

func TestModuleMatchesTarget_UsesOSFallback(t *testing.T) {
	t.Parallel()

	linux := platform.Target{GOOS: "linux", Family: platform.FamilyDebian}
	darwin := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}

	if !moduleMatchesTarget(Module{OS: "linux"}, linux) {
		t.Fatal("linux module should match linux target")
	}
	if moduleMatchesTarget(Module{OS: "linux"}, darwin) {
		t.Fatal("linux module should not match darwin target")
	}
	if !moduleMatchesTarget(Module{OS: "all"}, darwin) {
		t.Fatal("all module should match darwin target")
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

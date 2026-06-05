package modules

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
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
		t.Fatal("all module should match darwin targets")
	}
	if !moduleMatchesTarget(Module{OS: "darwin"}, darwin) {
		t.Fatal("darwin module should match darwin target")
	}
	if moduleMatchesTarget(Module{OS: "darwin"}, linux) {
		t.Fatal("darwin module should not match linux target")
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

	darwin := ForTarget(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"})
	if !hasModule(darwin, "shell-zsh") {
		t.Fatal("darwin targets should receive macOS-compatible shell modules")
	}
	if !hasModule(darwin, "neovim") {
		t.Fatal("darwin targets should receive macOS-compatible development modules")
	}
	if !hasModule(darwin, "macos-orbstack") {
		t.Fatal("darwin targets should receive OrbStack module")
	}
	if !hasModule(darwin, "macos-clash-verge-rev") {
		t.Fatal("darwin targets should receive Clash Verge Rev module")
	}
	if !hasModule(darwin, "macos-iterm2") {
		t.Fatal("darwin targets should receive iTerm2 module")
	}
	if !hasModule(darwin, "macos-google-chrome") {
		t.Fatal("darwin targets should receive Google Chrome module")
	}
	if !hasModule(darwin, "macos-clash-party") {
		t.Fatal("darwin targets should receive Clash Party module")
	}
	if !hasModule(darwin, "macos-cli-bat") {
		t.Fatal("darwin targets should receive macOS CLI modules")
	}
	if hasModule(darwin, "mihomo") {
		t.Fatal("mihomo should be hidden on darwin targets")
	}
	if hasModule(darwin, "docker") {
		t.Fatal("docker should be hidden on darwin targets")
	}
	if hasModule(darwin, "network-tune") {
		t.Fatal("network-tune should be hidden on darwin targets")
	}
	if hasModule(darwin, "shell-fzf") {
		t.Fatal("fzf should not be registered on darwin targets")
	}
}

func TestForTarget_ShowsArchDevKitOnlyOnArchLinux(t *testing.T) {
	t.Parallel()

	arch := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"})
	if !hasModule(arch, "archdevkit-workstation") {
		t.Fatal("ArchDevKit modules should appear on Arch Linux")
	}

	debian := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"})
	if hasModule(debian, "archdevkit-workstation") {
		t.Fatal("ArchDevKit modules should be hidden on Debian-family Linux")
	}

	redhat := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyRedHat, Init: "systemd"})
	if hasModule(redhat, "archdevkit-workstation") {
		t.Fatal("ArchDevKit modules should be hidden on RedHat-family Linux")
	}

	darwin := ForTarget(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"})
	if hasModule(darwin, "archdevkit-workstation") {
		t.Fatal("ArchDevKit modules should be hidden on macOS")
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

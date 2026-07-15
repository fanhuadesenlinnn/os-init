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

func TestForTarget_AppliesWSLCapabilityBoundaries(t *testing.T) {
	t.Parallel()

	wsl1 := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "unknown", Environment: platform.EnvironmentWSL, WSLVersion: 1})
	for _, id := range []string{"wsl-dev", "wsl-doctor", "mise", "shell-tmux", "neovim"} {
		if !hasModule(wsl1, id) {
			t.Fatalf("%s should be available on WSL1", id)
		}
	}
	for _, id := range []string{"wsl-systemd", "docker", "kernel-sysctl", "kernel-limits", "kernel-scheduler", "kernel-autotune", "network-ipv4", "network-tune", "mihomo"} {
		if hasModule(wsl1, id) {
			t.Fatalf("%s should be hidden on WSL1", id)
		}
	}

	wsl2 := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd", Environment: platform.EnvironmentWSL, WSLVersion: 2, WSLg: true})
	for _, id := range []string{"wsl-systemd", "wsl-dev", "wsl-doctor", "docker"} {
		if !hasModule(wsl2, id) {
			t.Fatalf("%s should be available on WSL2 with systemd", id)
		}
	}
	for _, id := range []string{"kernel-sysctl", "kernel-limits", "kernel-scheduler", "kernel-autotune", "network-ipv4", "network-tune", "mihomo"} {
		if hasModule(wsl2, id) {
			t.Fatalf("%s should be hidden on WSL2", id)
		}
	}
	docker, ok := moduleWithID(wsl2, "docker")
	if !ok || docker.Label != "Docker（WSL 原生 Engine）" {
		t.Fatalf("WSL should expose the native Docker variant: %#v", docker)
	}

	archWSL := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd", Environment: platform.EnvironmentWSL, WSLVersion: 2})
	for _, id := range []string{"arch-dns", "arch-mihomo", "arch-desktop", "arch-dev", "arch-workstation", "arch-doctor", "arch-status"} {
		if hasModule(archWSL, id) {
			t.Fatalf("%s should be hidden on Arch WSL", id)
		}
	}
	for _, id := range []string{"arch-base", "arch-archlinuxcn", "arch-git", "wsl-dev", "docker"} {
		if !hasModule(archWSL, id) {
			t.Fatalf("%s should remain available on Arch WSL", id)
		}
	}
}

func TestForTarget_AppliesOrbStackCapabilityBoundaries(t *testing.T) {
	t.Parallel()

	target := platform.Target{GOOS: "linux", ID: "archarm", Family: platform.FamilyArch, Init: "systemd", Environment: platform.EnvironmentOrbStack}
	mods := ForTarget(target)
	for _, id := range []string{"arch-dns", "arch-desktop", "network-tune", "kernel-autotune", "kernel-optimize"} {
		if hasModule(mods, id) {
			t.Fatalf("%s should be hidden in OrbStack", id)
		}
	}
	for _, id := range []string{"arch-base", "mise", "mise-go", "mise-python", "mise-node", "docker", "orbstack-arch-dev"} {
		if !hasModule(mods, id) {
			t.Fatalf("%s should remain available in OrbStack", id)
		}
	}
}

func TestForTarget_IncludesMihomoOnlyOnLinuxSystemdFamilies(t *testing.T) {
	t.Parallel()

	systemd := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"})
	if !hasModule(systemd, "mihomo") {
		t.Fatal("mihomo should appear on Debian-family systemd targets")
	}
	if !hasModule(systemd, "mise") || !hasModule(systemd, "shell-tmux") {
		t.Fatal("Debian-family targets should receive portable mise and tmux modules")
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
	if !hasModule(darwin, "macos-motrix-next") {
		t.Fatal("darwin targets should receive Motrix Next module")
	}
	if hasModule(darwin, "macos-clash-verge-rev") || hasModule(darwin, "macos-motrix") {
		t.Fatal("darwin targets should not receive removed macOS app modules")
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
	if hasModule(darwin, "shell-tmux") {
		t.Fatal("macOS should use its native tmux formula module")
	}
}

func TestForTarget_ShowsArchCapabilitiesOnlyOnArchLinux(t *testing.T) {
	t.Parallel()

	arch := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"})
	for _, id := range []string{"arch-base", "mise", "mise-go", "mise-python", "mise-node", "mise-dev-runtimes", "arch-mihomo", "arch-dev", "arch-workstation"} {
		if !hasModule(arch, id) {
			t.Fatalf("%s should appear on Arch Linux", id)
		}
	}
	if hasModule(arch, "mihomo") {
		t.Fatal("Arch should use arch-mihomo instead of the generic Linux Mihomo module")
	}
	if module, ok := moduleWithID(arch, "mise"); !ok || module.DeliveryFor(platform.Target{GOOS: "linux", Family: platform.FamilyArch}) != DeliveryArchNative {
		t.Fatal("Arch should use the native delivery backend of the shared mise module")
	}
	tmuxModule, ok := moduleWithID(arch, "shell-tmux")
	if !ok || tmuxModule.DeliveryFor(platform.Target{GOOS: "linux", Family: platform.FamilyArch}) != DeliveryArchNative {
		t.Fatal("Arch tmux should be marked as an Arch-native package")
	}
	if hasModule(arch, "arch-sing-box") {
		t.Fatal("removed Arch sing-box capability should not appear")
	}

	debian := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"})
	if hasModule(debian, "arch-base") {
		t.Fatal("Arch capabilities should be hidden on Debian-family Linux")
	}

	redhat := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyRedHat, Init: "systemd"})
	if hasModule(redhat, "arch-base") {
		t.Fatal("Arch capabilities should be hidden on RedHat-family Linux")
	}
	if !hasModule(redhat, "mise") || !hasModule(redhat, "shell-tmux") {
		t.Fatal("RedHat-family targets should receive portable mise and tmux modules")
	}

	darwin := ForTarget(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin, Init: "unknown"})
	if hasModule(darwin, "arch-base") {
		t.Fatal("Arch capabilities should be hidden on macOS")
	}
}

func moduleWithID(modules []Module, id string) (Module, bool) {
	for _, module := range modules {
		if module.ID == id {
			return module, true
		}
	}
	return Module{}, false
}

func TestArchCapabilityDependenciesAreExplicit(t *testing.T) {
	t.Parallel()
	mods := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"})
	byID := make(map[string]Module, len(mods))
	for _, mod := range mods {
		byID[mod.ID] = mod
	}
	for id, wants := range map[string][]string{
		"arch-aur":     {"arch-archlinuxcn"},
		"arch-mihomo":  {"arch-aur", "arch-archlinuxcn"},
		"arch-desktop": {"arch-base", "arch-aur", "arch-archlinuxcn", "arch-git", "arch-fonts"},
	} {
		got := byID[id].DependsOn
		if len(got) != len(wants) {
			t.Fatalf("%s dependencies = %v, want %v", id, got, wants)
		}
		for i := range wants {
			if got[i] != wants[i] {
				t.Fatalf("%s dependencies = %v, want %v", id, got, wants)
			}
		}
	}
}

func TestArchWorkstationPresetDependsOnDevAndDesktop(t *testing.T) {
	t.Parallel()
	mods := ForTarget(platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"})
	var preset Module
	for _, mod := range mods {
		if mod.ID == "arch-workstation" {
			preset = mod
		}
	}
	if len(preset.DependsOn) != 2 || preset.DependsOn[0] != "arch-dev" || preset.DependsOn[1] != "arch-desktop" {
		t.Fatalf("workstation dependencies = %v", preset.DependsOn)
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

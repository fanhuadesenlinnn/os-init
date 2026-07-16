package modules_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestAllModules_ReturnsNonEmpty(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	if len(mods) == 0 {
		t.Fatal("expected non-empty module list")
	}
}

func TestAllModules_PassesCatalogValidation(t *testing.T) {
	t.Parallel()
	if issues := modules.ValidateCatalog(modules.AllModules()); len(issues) > 0 {
		t.Fatalf("catalog validation failed: %v", issues)
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

func TestForOS_IncludesMacModulesOnlyOnDarwin(t *testing.T) {
	t.Parallel()

	mods := modules.ForOS("darwin")
	if len(mods) == 0 {
		t.Fatal("expected macOS-compatible modules on darwin")
	}
	if !hasModuleID(mods, "shell-zsh") {
		t.Fatal("shell-zsh should appear on darwin")
	}
	if !hasModuleID(mods, "neovim") {
		t.Fatal("neovim should appear on darwin")
	}
	if !hasModuleID(mods, "macos-orbstack") {
		t.Fatal("OrbStack should appear on darwin")
	}
	if !hasModuleID(mods, "macos-motrix-next") {
		t.Fatal("Motrix Next should appear on darwin")
	}
	if !hasModuleID(mods, "macos-squirrel-app") {
		t.Fatal("Squirrel should appear on darwin")
	}
	if !hasModuleID(mods, "macos-lm-studio") {
		t.Fatal("LM Studio should appear on darwin")
	}
	if hasModuleID(mods, "macos-clash-verge-rev") || hasModuleID(mods, "macos-motrix") {
		t.Fatal("removed Clash Verge Rev and legacy Motrix modules should not appear on darwin")
	}
	if !hasModuleID(mods, "macos-iterm2") {
		t.Fatal("iTerm2 should appear on darwin")
	}
	if !hasModuleID(mods, "macos-google-chrome") {
		t.Fatal("Google Chrome should appear on darwin")
	}
	if !hasModuleID(mods, "macos-ghostty") {
		t.Fatal("Ghostty should appear on darwin")
	}
	if hasModuleID(mods, "macos-neovide-app") {
		t.Fatal("standalone Neovide module should be merged into neovim")
	}
	if !hasModuleID(mods, "macos-clash-party") {
		t.Fatal("Clash Party should appear on darwin")
	}
	if !hasModuleID(mods, "macos-cli-bat") {
		t.Fatal("bat should appear on darwin")
	}
	if !hasModuleID(mods, "macos-cli-fzf") {
		t.Fatal("fzf should appear as a macOS CLI module on darwin")
	}
	if hasModuleID(mods, "docker") {
		t.Fatal("docker should not appear on darwin")
	}
	if hasModuleID(mods, "mihomo") {
		t.Fatal("mihomo should not appear on darwin")
	}
	if hasModuleID(mods, "network-tune") {
		t.Fatal("network-tune should not appear on darwin")
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
	if hasModuleID(mods, "macos-google-chrome") {
		t.Fatal("macOS cask modules should not appear on linux")
	}
	if hasModuleID(mods, "macos-cli-bat") {
		t.Fatal("macOS CLI modules should not appear on linux")
	}
}

func TestAllEntriesDeclareSupportedOperations(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	for _, m := range mods {
		if len(m.SupportedOperations) == 0 {
			t.Errorf("entry %q should declare supported operations", m.ID)
		}
	}
}

func TestPrivilegeNeeds_ArePlatformAware(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	byID := map[string]modules.Module{}
	for _, m := range mods {
		byID[m.ID] = m
	}

	darwin := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}
	linux := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}
	arch := platform.Target{GOOS: "linux", Family: platform.FamilyArch, Init: "systemd"}

	if modules.SelectionNeedsPrivilege([]modules.Module{byID["yazi"]}, darwin) {
		t.Fatal("macOS Yazi uses Homebrew and should not pre-prime sudo")
	}
	if !modules.SelectionNeedsPrivilege([]modules.Module{byID["yazi"]}, linux) {
		t.Fatal("Linux Yazi writes /usr/local/bin and should require privilege")
	}
	if modules.SelectionNeedsPrivilege([]modules.Module{byID["macos-cli-bat"]}, darwin) {
		t.Fatal("Homebrew formula modules should not pre-prime sudo on macOS")
	}
	if !modules.SelectionNeedsPrivilege([]modules.Module{byID["docker"]}, linux) {
		t.Fatal("Docker systemd install should require privilege")
	}
	if modules.SelectionNeedsPrivilege([]modules.Module{byID["mise"]}, darwin) {
		t.Fatal("macOS mise uses Homebrew and should not pre-prime sudo")
	}
	if modules.SelectionNeedsPrivilege([]modules.Module{byID["mise"]}, linux) {
		t.Fatal("portable Linux mise should not require system privilege")
	}
	if !modules.SelectionNeedsPrivilege([]modules.Module{byID["mise"]}, arch) {
		t.Fatal("Arch mise uses pacman and should require privilege")
	}
	if modules.SelectionNeedsPrivilege([]modules.Module{byID["mise-go"], byID["mise-python"], byID["mise-node"]}, arch) {
		t.Fatal("mise-managed runtimes are user-level even on Arch")
	}
}

func TestAllModules_HaveInstallSemantics(t *testing.T) {
	t.Parallel()
	for _, m := range modules.AllModules() {
		if m.EntryKind == modules.EntryModule && m.Kind == "" {
			t.Errorf("module %q should declare a kind", m.ID)
		}
	}
}

func TestCatalogRolesHaveDistinctExecutionSemantics(t *testing.T) {
	t.Parallel()
	for _, entry := range modules.AllModules() {
		switch entry.EntryKind {
		case modules.EntryModule:
			if entry.Verify.Empty() {
				t.Errorf("stateful module %q must declare verification", entry.ID)
			}
		case modules.EntryPreset:
			if entry.Script != "" || entry.Verify.Empty() == false || len(entry.DependsOn) == 0 {
				t.Errorf("preset %q must be dependency-only: %#v", entry.ID, entry)
			}
		case modules.EntryAction:
			if entry.Script == "" || !entry.Verify.Empty() || len(entry.DependsOn) != 0 {
				t.Errorf("action %q must be one-shot and stateless: %#v", entry.ID, entry)
			}
		default:
			t.Errorf("entry %q has unknown role %q", entry.ID, entry.EntryKind)
		}
	}
}

func TestShellModules_DeclareDependenciesAndActivation(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	zsh := findModule(t, mods, "shell-zsh")
	if zsh.Kind != modules.KindShellIntegration || !contains(zsh.Activates, modules.ActivationZshrc) {
		t.Fatalf("shell-zsh should own the complete zsh integration lifecycle: %#v", zsh)
	}
	for _, removedID := range []string{"shell-starship", "shell-autosuggestions", "shell-syntax-hl", "terminal-style"} {
		if hasModuleID(mods, removedID) {
			t.Fatalf("removed module %q is still registered", removedID)
		}
	}
}

func TestServiceAndManualModules_DeclareCompletionSemantics(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()

	docker := findModule(t, mods, "docker")
	if docker.Kind != modules.KindSystemService {
		t.Fatalf("docker kind = %q, want %q", docker.Kind, modules.KindSystemService)
	}
	if !docker.NeedsRelogin || !contains(docker.Activates, modules.ActivationRelogin) {
		t.Fatalf("docker should declare relogin activation, got needsRelogin=%v activates=%v", docker.NeedsRelogin, docker.Activates)
	}
	for _, kind := range []modules.CheckKind{modules.CheckCommandRun, modules.CheckSystemd, modules.CheckUserGroup} {
		if !checkHasKind(docker.Verify, kind) {
			t.Fatalf("docker should declare %s verification: %#v", kind, docker.Verify)
		}
	}

	orbstack := findModule(t, mods, "macos-orbstack")
	if orbstack.Kind != modules.KindInstallOnly {
		t.Fatalf("orbstack kind = %q, want %q", orbstack.Kind, modules.KindInstallOnly)
	}
	if len(orbstack.ManualSteps) == 0 || !contains(orbstack.Activates, modules.ActivationManual) {
		t.Fatalf("orbstack should declare manual first-run work, got steps=%v activates=%v", orbstack.ManualSteps, orbstack.Activates)
	}

	karabiner := findModule(t, mods, "macos-karabiner-elements")
	if len(karabiner.ManualSteps) == 0 || !contains(karabiner.Activates, modules.ActivationManual) {
		t.Fatalf("karabiner should declare required macOS permissions, got steps=%v activates=%v", karabiner.ManualSteps, karabiner.Activates)
	}
	if !checkHasKind(karabiner.Verify, modules.CheckFileContains) || !contains(karabiner.AffectedPaths, "$HOME/.config/karabiner/karabiner.json") {
		t.Fatalf("karabiner should verify and declare its managed config: verify=%#v paths=%v", karabiner.Verify, karabiner.AffectedPaths)
	}

	archDesktop := findModule(t, mods, "arch-desktop")
	if !contains(archDesktop.Activates, modules.ActivationManual) || len(archDesktop.ManualSteps) == 0 {
		t.Fatalf("Arch desktop should declare the post-login input-method activation step: %#v", archDesktop)
	}
	for _, path := range []string{"$HOME/.config/environment.d/fcitx5.conf", "$HOME/.config/fcitx5/profile", "$HOME/.local/share/fcitx5/rime"} {
		if !contains(archDesktop.AffectedPaths, path) {
			t.Fatalf("Arch desktop should declare managed Rime path %q: %v", path, archDesktop.AffectedPaths)
		}
	}
}

func TestMacOSModules_DeclareHomebrewStatusChecks(t *testing.T) {
	t.Parallel()
	for _, m := range modules.AllModules() {
		if m.OS != "darwin" {
			continue
		}
		switch m.Script {
		case "macos/install.sh":
			if !m.RunIndividually {
				t.Fatalf("macOS cask module %q should run individually", m.ID)
			}
			if !checkHasKind(m.Verify, modules.CheckBrewCask) {
				t.Fatalf("macOS cask module %q should declare a Brew cask check", m.ID)
			}
		case "macos/cli.sh":
			if !m.RunIndividually {
				t.Fatalf("macOS formula module %q should run individually", m.ID)
			}
			if !checkHasKind(m.Verify, modules.CheckBrewFormula) {
				t.Fatalf("macOS formula module %q should declare a Brew formula check", m.ID)
			}
		}
	}
}

func TestMacOSScriptComponentsMatchRegistry(t *testing.T) {
	t.Parallel()

	caskFromScript := shellArray(t, filepath.Join("..", "..", "modules", "macos", "install.sh"), "ALL_COMPONENTS")
	formulaFromScript := shellArray(t, filepath.Join("..", "..", "modules", "macos", "cli.sh"), "ALL_COMPONENTS")

	caskFromRegistry := componentsForScript("macos/install.sh")
	formulaFromRegistry := componentsForScript("macos/cli.sh")

	assertSameStringSet(t, caskFromRegistry, caskFromScript, "macOS cask components")
	assertSameStringSet(t, formulaFromRegistry, formulaFromScript, "macOS formula components")
}

func TestSharedScriptComponentsMatchRegistry(t *testing.T) {
	t.Parallel()

	cases := []struct {
		script string
		array  string
		label  string
	}{
		{script: "kernel/optimize.sh", array: "ALL_COMPONENTS", label: "kernel components"},
		{script: "shell/install.sh", array: "SUPPORTED_COMPONENTS", label: "shell components"},
		{script: "terminal/install.sh", array: "ALL_COMPONENTS", label: "terminal components"},
	}
	for _, tc := range cases {
		fromScript := shellArray(t, filepath.Join("..", "..", "modules", filepath.FromSlash(tc.script)), tc.array)
		assertSameStringSet(t, componentsForScript(tc.script), fromScript, tc.label)
	}
}

func TestSharedScriptsRejectUnknownComponents(t *testing.T) {
	for _, script := range []string{"kernel/optimize.sh", "shell/install.sh", "terminal/install.sh"} {
		script := script
		t.Run(script, func(t *testing.T) {
			path := filepath.Join("..", "..", "modules", filepath.FromSlash(script))
			cmd := exec.Command("bash", path, "__unknown_component__")
			cmd.Env = append(os.Environ(), "HOME="+t.TempDir(), "OS_INIT_LANG=en_US")
			output, err := cmd.CombinedOutput()
			if err == nil {
				t.Fatalf("unknown component unexpectedly succeeded: %s", output)
			}
			if !strings.Contains(strings.ToLower(string(output)), "unknown") {
				t.Fatalf("unknown component failure was not explicit: %s", output)
			}
		})
	}
}

func TestMacOSCustomHomebrewRoutes(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "..", "modules", "macos", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	if !strings.Contains(script, "stats|orbstack|loop|squirrel-app") {
		t.Fatal("Stats, OrbStack, Loop, and Squirrel should use brew install without a forced --cask flag")
	}
	if !strings.Contains(script, "run_brew tap AnInsomniacy/motrix-next") {
		t.Fatal("Motrix Next should add its Homebrew tap before installation")
	}
	if !strings.Contains(script, "run_brew trust --cask aninsomniacy/motrix-next/motrix-next") {
		t.Fatal("Motrix Next should trust only its fully-qualified cask")
	}
	if !strings.Contains(script, `motrix-next) echo "aninsomniacy/motrix-next/motrix-next"`) {
		t.Fatal("Motrix Next should install through its fully-qualified cask reference")
	}
	for _, command := range []string{"brew_install \"$reference\"", "brew_install --cask \"$reference\""} {
		if !strings.Contains(script, command) {
			t.Fatalf("macOS installer should contain route %q", command)
		}
	}
	for _, route := range []string{
		`install_karabiner_config`,
		`os_init_prepare_owned_user_path "karabiner-config"`,
		`os_init_restore_owned_user_path "karabiner-config"`,
	} {
		if !strings.Contains(script, route) {
			t.Fatalf("macOS installer should manage Karabiner config through %q", route)
		}
	}

	configPath := filepath.Join("..", "..", "modules", "macos", "karabiner", "karabiner.json")
	config, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read managed Karabiner config: %v", err)
	}
	for _, mapping := range []string{`"key_code": "caps_lock"`, `"key_code": "left_control"`, `"key_code": "left_shift"`, `"basic.to_if_held_down_threshold_milliseconds": 50`} {
		if !strings.Contains(string(config), mapping) {
			t.Fatalf("managed Karabiner config should contain %q", mapping)
		}
	}
}

func TestShellAndNeovimCombinedInstallRoutes(t *testing.T) {
	t.Parallel()

	shellData, err := os.ReadFile(filepath.Join("..", "..", "modules", "shell", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	shellScript := string(shellData)
	for _, want := range []string{
		"github.com/ohmyzsh/ohmyzsh.git",
		"romkatv/powerlevel10k.git",
		"ZSH_THEME=\"$theme\"",
		"ensure_oh_my_zsh_prerequisites",
	} {
		if !strings.Contains(shellScript, want) {
			t.Fatalf("shell installer should contain %q", want)
		}
	}
	if strings.Contains(shellScript, "raw.githubusercontent.com/robbyrussell/oh-my-zsh") {
		t.Fatal("Oh My Zsh installation should use the shared Git proxy path")
	}
	for _, unwanted := range []string{"brew_install orbstack", "pkg_install fzf", "pkg_install kubectl"} {
		if strings.Contains(shellScript, unwanted) {
			t.Fatalf("shell installer should not implicitly install %q", unwanted)
		}
	}

	nvimData, err := os.ReadFile(filepath.Join("..", "..", "modules", "neovim", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	nvimScript := string(nvimData)
	for _, want := range []string{
		"brew_install --cask neovide-app",
		"fanhuadesenlinnn/nvim.git",
		"neovide/config.toml",
	} {
		if !strings.Contains(nvimScript, want) {
			t.Fatalf("combined Neovim installer should contain %q", want)
		}
	}

	mods := modules.AllModules()
	combined := findModule(t, mods, "neovim")
	if combined.Label != "Neovim + Neovide + config-yuan" {
		t.Fatalf("combined Neovim label = %q", combined.Label)
	}
	if !checkHasGOOS(combined.Verify, "darwin") {
		t.Fatal("combined Neovim module should declare macOS Neovide status checks")
	}
}

func TestShellIntegrationModules_DeclareShellBlockChecks(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	for _, id := range []string{"shell-zsh", "shell-direnv"} {
		mod := findModule(t, mods, id)
		if !checkHasKind(mod.Verify, modules.CheckZshBlock) {
			t.Fatalf("%s should declare zsh block checks", id)
		}
	}
	for _, id := range []string{"mise", "yazi", "neovim"} {
		mod := findModule(t, mods, id)
		if !checkHasKind(mod.Verify, modules.CheckShellBlock) {
			t.Fatalf("%s should declare shell block checks", id)
		}
	}
}

func TestLegacyRuntimeManagersAreRemoved(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	for _, id := range []string{"shell-nvm", "shell-fnm"} {
		if hasModuleID(mods, id) {
			t.Fatalf("legacy runtime manager %s should not be registered", id)
		}
	}
	data, err := os.ReadFile(filepath.Join("..", "..", "modules", "shell", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), `want "nvm"`) || strings.Contains(string(data), `want "fnm"`) {
		t.Fatal("shell installer should not expose nvm/fnm installation routes")
	}
}

func TestMiseInstallsManagedRuntimeVersions(t *testing.T) {
	t.Parallel()
	data, err := os.ReadFile(filepath.Join("..", "..", "modules", "mise", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, want := range []string{
		`OS_INIT_MISE_NODE_VERSION:-24`,
		`OS_INIT_MISE_PYTHON_VERSION:-3.13`,
		`OS_INIT_MISE_GO_VERSION:-1.26`,
		`curl --fail --silent --show-error --location https://mise.run`,
		`MISE_INSTALL_PATH="$mise_binary"`,
		`MISE_VERSION="$version"`,
		`os_init_prepare_owned_user_path "mise-binary"`,
		`mise_exec use --global "${tool}@${version}"`,
		`mise_exec uninstall --all "$tool"`,
		`mise activate zsh --shims`,
		`mise activate zsh`,
		`mise activate bash --shims`,
		`arch_run_pacman -Syu --needed --noconfirm mise`,
		`https://registry.npmmirror.com`,
		`https://pypi.tuna.tsinghua.edu.cn/simple`,
		`https://goproxy.cn,direct`,
		`国内运行时镜像安装失败，使用官方源重试`,
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("mise installer should contain %q", want)
		}
	}

	miseCore := findModule(t, modules.AllModules(), "mise")
	if miseCore.Script != "mise/install.sh" || miseCore.OS != "all" {
		t.Fatalf("cross-platform mise core is not scoped correctly: %#v", miseCore)
	}
	if miseCore.Delivery.Default != modules.DeliveryPortable || miseCore.Delivery.Darwin != modules.DeliveryDarwinNative || miseCore.Delivery.Arch != modules.DeliveryArchNative {
		t.Fatalf("mise core delivery is not declared: %#v", miseCore.Delivery)
	}
	for _, id := range []string{"mise-go", "mise-python", "mise-node"} {
		runtimeModule := findModule(t, modules.AllModules(), id)
		if runtimeModule.Delivery.Default != modules.DeliveryUserRuntime || !contains(runtimeModule.DependsOn, "mise") {
			t.Fatalf("%s should be a user runtime depending on mise: %#v", id, runtimeModule)
		}
	}

	goMod, err := os.ReadFile(filepath.Join("..", "..", "go.mod"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(goMod), "go 1.26.1") {
		t.Fatal("the repository Go toolchain should stay in the configured mise Go 1.26 series")
	}
}

func TestDockerInstallerWritesConfiguredRegistryMirrors(t *testing.T) {
	t.Parallel()
	data, err := os.ReadFile(filepath.Join("..", "..", "modules", "docker", "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	for _, want := range []string{
		`json_array_from_csv "${DOCKER_REGISTRY_MIRRORS:-}"`,
		`daemon_add_entry "$tmp" "registry-mirrors" "$mirrors"`,
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("Docker installer should contain %q", want)
		}
	}
}

func shellArray(t *testing.T, path, name string) []string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	marker := name + "=("
	start := strings.Index(string(data), marker)
	if start < 0 {
		t.Fatalf("%s does not contain %s", path, marker)
	}
	rest := string(data)[start+len(marker):]
	end := strings.Index(rest, ")")
	if end < 0 {
		t.Fatalf("%s has unterminated %s array", path, name)
	}
	return strings.Fields(rest[:end])
}

func componentsForScript(script string) []string {
	var out []string
	for _, m := range modules.AllModules() {
		if m.Script != script || len(m.Components) == 0 {
			continue
		}
		out = append(out, m.Components...)
	}
	return out
}

func assertSameStringSet(t *testing.T, left, right []string, label string) {
	t.Helper()
	leftSet := stringSet(left)
	rightSet := stringSet(right)
	for item := range leftSet {
		if !rightSet[item] {
			t.Fatalf("%s: registry component %q is missing from script list", label, item)
		}
	}
	for item := range rightSet {
		if !leftSet[item] {
			t.Fatalf("%s: script component %q is missing from registry", label, item)
		}
	}
}

func stringSet(values []string) map[string]bool {
	out := make(map[string]bool, len(values))
	for _, value := range values {
		out[value] = true
	}
	return out
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

func TestAllModules_DoesNotRegisterRemovedModules(t *testing.T) {
	t.Parallel()

	for _, m := range modules.AllModules() {
		if m.ID == "sshd" {
			t.Fatal("sshd hardening module should not be registered")
		}
		if m.ID == "shell-fzf" {
			t.Fatal("fzf module should not be registered")
		}
		for _, component := range m.Components {
			if m.Script == "shell/install.sh" && component == "fzf" {
				t.Fatalf("shell module %q should not register fzf component", m.ID)
			}
		}
	}
}

func TestGroupByScript_MergesComponents(t *testing.T) {
	t.Parallel()
	selected := []modules.Module{
		{ID: "shell-zsh", Script: "shell/install.sh", Components: []string{"zsh"}},
		{ID: "shell-direnv", Script: "shell/install.sh", Components: []string{"direnv"}},
		{ID: "docker", Script: "docker/install.sh"},
	}
	groups := modules.GroupByScript(selected)
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	if len(groups[0].Components) != 2 {
		t.Errorf("expected 2 components for shell, got %d", len(groups[0].Components))
	}
	if groups[0].Components[0] != "zsh" || groups[0].Components[1] != "direnv" {
		t.Errorf("wrong components: %v", groups[0].Components)
	}
	if len(groups[0].ModuleIDs) != 2 || groups[0].ModuleIDs[0] != "shell-zsh" || groups[0].ModuleIDs[1] != "shell-direnv" {
		t.Errorf("wrong module IDs: %v", groups[0].ModuleIDs)
	}
	if len(groups[1].Components) != 0 {
		t.Errorf("docker should have no components, got %v", groups[1].Components)
	}
}

func TestGroupByScript_DeduplicatesComponentsButKeepsModuleLabels(t *testing.T) {
	t.Parallel()
	selected := []modules.Module{
		{ID: "component-a", Script: "shell/install.sh", Components: []string{"shared"}, Label: "Component A"},
		{ID: "component-b", Script: "shell/install.sh", Components: []string{"shared"}, Label: "Component B"},
	}
	groups := modules.GroupByScript(selected)
	if len(groups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(groups))
	}
	if got := groups[0].Components; !reflect.DeepEqual(got, []string{"shared"}) {
		t.Fatalf("components should be deduplicated, got %v", got)
	}
	if got := groups[0].ModuleLabels; !reflect.DeepEqual(got, []string{"Component A", "Component B"}) {
		t.Fatalf("module labels should be preserved, got %v", got)
	}
}

func TestGroupByScript_KeepsIndividualModulesSeparate(t *testing.T) {
	t.Parallel()
	selected := []modules.Module{
		{ID: "macos-visual-studio-code", Script: "macos/install.sh", Components: []string{"visual-studio-code"}, Label: "Visual Studio Code", RunIndividually: true},
		{ID: "macos-motrix-next", Script: "macos/install.sh", Components: []string{"motrix-next"}, Label: "Motrix Next", RunIndividually: true},
	}

	groups := modules.GroupByScript(selected)
	if len(groups) != 2 {
		t.Fatalf("individual macOS modules should produce 2 groups, got %d", len(groups))
	}
	if got := groups[0].Components; !reflect.DeepEqual(got, []string{"visual-studio-code"}) {
		t.Fatalf("first group components = %v", got)
	}
	if got := groups[1].Components; !reflect.DeepEqual(got, []string{"motrix-next"}) {
		t.Fatalf("second group components = %v", got)
	}
}

func hasModuleID(mods []modules.Module, id string) bool {
	for _, m := range mods {
		if m.ID == id {
			return true
		}
	}
	return false
}

func findModule(t *testing.T, mods []modules.Module, id string) modules.Module {
	t.Helper()
	for _, m := range mods {
		if m.ID == id {
			return m
		}
	}
	t.Fatalf("module %q not found", id)
	return modules.Module{}
}

func contains[T comparable](values []T, needle T) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

func checkHasKind(check modules.Check, kind modules.CheckKind) bool {
	if check.Kind == kind {
		return true
	}
	for _, child := range append(check.All, check.Any...) {
		if checkHasKind(child, kind) {
			return true
		}
	}
	return false
}

func checkHasGOOS(check modules.Check, goos string) bool {
	if check.GOOS == goos {
		return true
	}
	for _, child := range append(check.All, check.Any...) {
		if checkHasGOOS(child, goos) {
			return true
		}
	}
	return false
}

func TestNeedsUserInfo_ShellGitOnly(t *testing.T) {
	t.Parallel()
	if modules.NeedsUserInfo([]modules.Module{{ID: "docker"}}) {
		t.Error("docker should not need user info")
	}
	if !modules.NeedsUserInfo([]modules.Module{{ID: "git"}}) {
		t.Error("git should need user info")
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

	want := []string{
		"Shell 工具",
		"终端体验",
		"终端工具",
		"macOS 开发应用",
		"macOS 代理网络",
		"macOS 效率工具",
		"macOS 输入增强",
		"macOS 媒体下载",
		"macOS AI 笔记",
		"macOS 通讯办公",
		"macOS 字体",
		"macOS 命令行",
		"网络代理",
		"开发工具",
		"Arch Linux 能力",
		"Arch Linux 开发",
		"Arch Linux 套餐",
		"Arch Linux 操作",
	}
	if got := modules.InstallSubsections(); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected install subsections: got %v, want %v", got, want)
	}
}

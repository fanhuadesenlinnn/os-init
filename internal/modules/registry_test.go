package modules_test

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestAllModules_ReturnsNonEmpty(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	if len(mods) == 0 {
		t.Fatal("expected non-empty module list")
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
	if !hasModuleID(mods, "macos-clash-verge-rev") {
		t.Fatal("Clash Verge Rev should appear on darwin")
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

func TestNeedsSudo_AllowedModulesOnly(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	for _, m := range mods {
		if m.NeedsSudo {
			t.Errorf("module %q should not require sudo in the registry", m.ID)
		}
	}
}

func TestAllModules_HaveInstallSemantics(t *testing.T) {
	t.Parallel()
	for _, m := range modules.AllModules() {
		if m.Kind == "" {
			t.Errorf("module %q should declare a kind", m.ID)
		}
	}
}

func TestShellModules_DeclareDependenciesAndActivation(t *testing.T) {
	t.Parallel()
	mods := modules.AllModules()
	starship := findModule(t, mods, "shell-starship")
	if starship.Kind != modules.KindShellIntegration {
		t.Fatalf("shell-starship kind = %q, want %q", starship.Kind, modules.KindShellIntegration)
	}
	if !contains(starship.DependsOn, "shell-zsh") {
		t.Fatalf("shell-starship should depend on shell-zsh, got %v", starship.DependsOn)
	}
	if !contains(starship.Activates, modules.ActivationZshrc) {
		t.Fatalf("shell-starship should activate zshrc, got %v", starship.Activates)
	}

	auto := findModule(t, mods, "shell-autosuggestions")
	if got := auto.Components; !reflect.DeepEqual(got, []string{"autosuggestions"}) {
		t.Fatalf("autosuggestions should have its own component, got %v", got)
	}
	syntax := findModule(t, mods, "shell-syntax-hl")
	if got := syntax.Components; !reflect.DeepEqual(got, []string{"syntax-highlighting"}) {
		t.Fatalf("syntax highlighting should have its own component, got %v", got)
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

	orbstack := findModule(t, mods, "macos-orbstack")
	if orbstack.Kind != modules.KindInstallOnly {
		t.Fatalf("orbstack kind = %q, want %q", orbstack.Kind, modules.KindInstallOnly)
	}
	if len(orbstack.ManualSteps) == 0 || !contains(orbstack.Activates, modules.ActivationManual) {
		t.Fatalf("orbstack should declare manual first-run work, got steps=%v activates=%v", orbstack.ManualSteps, orbstack.Activates)
	}
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
		{ID: "shell-starship", Script: "shell/install.sh", Components: []string{"starship"}},
		{ID: "docker", Script: "docker/install.sh"},
	}
	groups := modules.GroupByScript(selected)
	if len(groups) != 2 {
		t.Fatalf("expected 2 groups, got %d", len(groups))
	}
	if len(groups[0].Components) != 2 {
		t.Errorf("expected 2 components for shell, got %d", len(groups[0].Components))
	}
	if groups[0].Components[0] != "zsh" || groups[0].Components[1] != "starship" {
		t.Errorf("wrong components: %v", groups[0].Components)
	}
	if len(groups[0].ModuleIDs) != 2 || groups[0].ModuleIDs[0] != "shell-zsh" || groups[0].ModuleIDs[1] != "shell-starship" {
		t.Errorf("wrong module IDs: %v", groups[0].ModuleIDs)
	}
	if len(groups[1].Components) != 0 {
		t.Errorf("docker should have no components, got %v", groups[1].Components)
	}
}

func TestGroupByScript_DeduplicatesComponentsButKeepsModuleLabels(t *testing.T) {
	t.Parallel()
	selected := []modules.Module{
		{ID: "shell-autosuggestions", Script: "shell/install.sh", Components: []string{"autosuggestions"}, Label: "zsh-autosuggestions"},
		{ID: "shell-syntax-hl", Script: "shell/install.sh", Components: []string{"syntax-highlighting"}, Label: "zsh-syntax-highlighting"},
	}
	groups := modules.GroupByScript(selected)
	if len(groups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(groups))
	}
	if got := groups[0].Components; !reflect.DeepEqual(got, []string{"autosuggestions", "syntax-highlighting"}) {
		t.Fatalf("components should stay distinct, got %v", got)
	}
	if got := groups[0].ModuleLabels; !reflect.DeepEqual(got, []string{"zsh-autosuggestions", "zsh-syntax-highlighting"}) {
		t.Fatalf("module labels should be preserved, got %v", got)
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

func TestNeedsUserInfo_ShellGitOnly(t *testing.T) {
	t.Parallel()
	if modules.NeedsUserInfo([]modules.Module{{ID: "docker"}}) {
		t.Error("docker should not need user info")
	}
	if !modules.NeedsUserInfo([]modules.Module{{ID: "shell-git"}}) {
		t.Error("shell-git should need user info")
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
	}
	if got := modules.InstallSubsections(); !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected install subsections: got %v, want %v", got, want)
	}
}

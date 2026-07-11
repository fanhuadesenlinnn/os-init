package tui

import (
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestConfirmView_RendersActionKeys(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	view := newConfirmModel(3, modeInstall).View()
	for _, want := range []string{"[Y]", "[Enter]", "确认执行", "[N]", "[Esc]"} {
		if !strings.Contains(view, want) {
			t.Fatalf("confirm view should contain %q, got %q", want, view)
		}
	}
}

func TestConfirmView_UninstallUsesSpecificActionText(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	view := newConfirmModel(1, modeUninstall).View()
	if !strings.Contains(view, "确认卸载") {
		t.Fatalf("uninstall confirm view should use uninstall wording, got %q", view)
	}
}

func TestConfirmView_ShowsPrivilegeReasons(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	mod := modules.Module{
		ID:              "docker",
		Label:           "Docker",
		Privilege:       modules.PrivilegeSystem,
		PrivilegeReason: "写入 systemd 服务",
		OS:              "linux",
	}
	model := newConfirmModelForSelection(
		[]modules.Module{mod},
		modeInstall,
		platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"},
	)
	view := model.View()
	if !strings.Contains(view, "需要 sudo 的模块") || !strings.Contains(view, "写入 systemd 服务") {
		t.Fatalf("confirm view should show privilege reason, got %q", view)
	}
}

func TestConfirmView_EnglishContainsNoChineseMetadata(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	mods := modules.AllModules()
	var selected []modules.Module
	for _, mod := range mods {
		if mod.ID == "docker" || mod.ID == "go" || mod.ID == "neovim" || mod.ID == "mihomo" {
			selected = append(selected, mod)
		}
	}
	model := newConfirmModelForSelection(
		selected,
		modeUninstall,
		platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"},
	)
	view := model.View()
	if containsHan(view) {
		t.Fatalf("English confirmation view contains Chinese text: %q", view)
	}
	for _, want := range []string{"Review Changes", "Important affected paths", "only with PURGE_DATA=1", "Modules needing sudo"} {
		if !strings.Contains(view, want) {
			t.Fatalf("English confirmation view should contain %q, got %q", want, view)
		}
	}
}

func TestConfirmView_EnglishUsesSingularModule(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	view := newConfirmModel(1, modeInstall).View()
	if !strings.Contains(view, "Run 1 module in install mode?") {
		t.Fatalf("English confirmation should use singular module, got %q", view)
	}
}

func TestLocalizedExecutionLine_HidesLegacyChineseOutput(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")

	for _, input := range []string{
		"[Install] 写入 Docker daemon 配置",
		"[Warning] 请重新登录",
		"=== Mihomo 安装完成 ===",
		"无法确定最新版本",
	} {
		got := localizedExecutionLine(input)
		if containsHan(got) {
			t.Fatalf("localized output still contains Chinese: input=%q output=%q", input, got)
		}
	}
}

func TestConfirmView_ShowsPlannedDependencyAdditions(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	plan := planner.Plan{
		Modules: []modules.Module{
			{ID: "shell-zsh", Label: "zsh + oh-my-zsh"},
			{ID: "shell-autosuggestions", Label: "zsh-autosuggestions"},
		},
		AddedDependencies: []planner.DependencyAddition{
			{
				ModuleID:        "shell-zsh",
				Label:           "zsh + oh-my-zsh",
				RequiredByID:    "shell-autosuggestions",
				RequiredByLabel: "zsh-autosuggestions",
			},
		},
	}

	view := newConfirmModelForPlan(plan, modeInstall, platform.Target{GOOS: "linux"}).View()
	if !strings.Contains(view, "自动补齐依赖") || !strings.Contains(view, "zsh + oh-my-zsh") {
		t.Fatalf("confirm view should show dependency additions, got %q", view)
	}
}

func TestConfirmView_ShowsSoftAssociations(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	plan := planner.Plan{
		Modules: []modules.Module{{ID: "docker", Label: "Docker"}},
		SoftAssociations: []planner.SoftAssociation{
			{
				ModuleID:       "docker",
				Label:          "Docker",
				SuggestedID:    "network-tune",
				SuggestedLabel: "网络 ▸ 队列与 MSS",
				ReasonZH:       "容器场景建议开启",
				ReasonEN:       "Suggested for container hosts",
			},
		},
	}

	view := newConfirmModelForPlan(plan, modeInstall, platform.Target{GOOS: "linux"}).View()
	if !strings.Contains(view, "相关建议") || !strings.Contains(view, "网络 ▸ 队列与 MSS") {
		t.Fatalf("confirm view should show soft associations, got %q", view)
	}
}

func TestConfirmViewShowsAffectedAndDestructivePaths(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")
	mod := modules.Module{
		ID:               "danger",
		Label:            "Danger",
		AffectedPaths:    []string{"/etc/example"},
		DestructivePaths: []string{"/var/lib/example (PURGE_DATA=1)"},
	}
	model := newConfirmModelForPlan(planner.Plan{Modules: []modules.Module{mod}}, modeUninstall, platform.Target{})
	view := model.View()
	if !strings.Contains(view, "重要影响路径") || !strings.Contains(view, "/etc/example") {
		t.Fatalf("affected paths missing from confirm view: %s", view)
	}
	if !strings.Contains(view, "显式清理开关可能删除") || !strings.Contains(view, "/var/lib/example") {
		t.Fatalf("destructive paths missing from uninstall confirm view: %s", view)
	}
}

func TestSelectionNeedsSudoPrime_IsPlatformAware(t *testing.T) {
	mods := modules.AllModules()
	byID := map[string]modules.Module{}
	for _, m := range mods {
		byID[m.ID] = m
	}

	darwin := platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}
	linux := platform.Target{GOOS: "linux", Family: platform.FamilyDebian, Init: "systemd"}

	if selectionNeedsSudoPrime([]modules.Module{byID["yazi"]}, darwin) {
		t.Fatal("macOS Yazi should not trigger sudo prime")
	}
	if selectionNeedsSudoPrime([]modules.Module{byID["go"]}, darwin) {
		t.Fatal("macOS Go uses Homebrew and should not trigger sudo prime")
	}
	if !selectionNeedsSudoPrime([]modules.Module{byID["yazi"]}, linux) {
		t.Fatal("Linux Yazi should trigger sudo prime")
	}
}

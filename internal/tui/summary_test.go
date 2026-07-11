package tui

import (
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

func TestSummaryView_ShowsNextStepsForSuccessfulModules(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	model := newSummaryModel(
		[]runner.Result{
			{Module: "Docker", ExitCode: 0},
			{Module: "OrbStack", ExitCode: 0},
			{Module: "starship 提示符", ExitCode: 0},
		},
		[]modules.Module{
			{
				ID:           "docker",
				Label:        "Docker",
				NeedsRelogin: true,
				Activates:    []string{modules.ActivationRelogin},
			},
			{
				ID:          "macos-orbstack",
				Label:       "OrbStack",
				ManualSteps: []string{"打开 OrbStack 完成首次初始化"},
			},
			{
				ID:        "shell-starship",
				Label:     "starship 提示符",
				Activates: []string{modules.ActivationZshrc},
			},
		},
	)

	view := model.View()
	for _, want := range []string{"后续动作", "重新登录一次", "打开新终端", "OrbStack: 打开 OrbStack 完成首次初始化"} {
		if !strings.Contains(view, want) {
			t.Fatalf("summary view should contain %q, got %q", want, view)
		}
	}
}

func TestSummaryView_HidesNextStepsForFailedModules(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")

	model := newSummaryModel(
		[]runner.Result{{Module: "Docker", ExitCode: 1}},
		[]modules.Module{{
			ID:           "docker",
			Label:        "Docker",
			NeedsRelogin: true,
			Activates:    []string{modules.ActivationRelogin},
		}},
	)

	view := model.View()
	if strings.Contains(view, "后续动作") || strings.Contains(view, "重新登录一次") {
		t.Fatalf("failed module should not show next steps, got %q", view)
	}
}

func TestSummaryShowsFailureReasonWithoutLog(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")
	model := newSummaryModel([]runner.Result{{Module: "启动执行", ExitCode: -1, Output: "资源解压失败\nmore"}}, nil)
	view := model.View()
	if !strings.Contains(view, "原因: 资源解压失败") {
		t.Fatalf("failure reason missing from summary: %s", view)
	}
}

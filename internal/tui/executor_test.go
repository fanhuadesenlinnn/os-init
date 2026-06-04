package tui

import (
	"reflect"
	"testing"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

func TestExpandGroupResult_ReturnsOneSummaryResultPerModule(t *testing.T) {
	group := modules.ScriptGroup{
		Script:       "shell/install.sh",
		Label:        "zsh + oh-my-zsh",
		ModuleLabels: []string{"zsh + oh-my-zsh", "starship 提示符"},
	}
	result := runner.Result{
		Module:   "shell/install.sh",
		ExitCode: 0,
		LogFile:  "logs/shell-install.log",
	}

	got := expandGroupResult(group, result)
	if len(got) != 2 {
		t.Fatalf("expected 2 summary results, got %d", len(got))
	}
	labels := []string{got[0].Module, got[1].Module}
	want := []string{"zsh + oh-my-zsh", "starship 提示符"}
	if !reflect.DeepEqual(labels, want) {
		t.Fatalf("unexpected labels: got %v, want %v", labels, want)
	}
	for _, item := range got {
		if item.ExitCode != result.ExitCode || item.LogFile != result.LogFile {
			t.Fatalf("summary item did not preserve script result: %+v", item)
		}
	}
}

func TestScriptTimeoutFromEnv(t *testing.T) {
	t.Setenv("OS_INIT_SCRIPT_TIMEOUT", "")
	if got := scriptTimeoutFromEnv(); got != defaultScriptTimeout {
		t.Fatalf("empty timeout = %s, want default %s", got, defaultScriptTimeout)
	}

	t.Setenv("OS_INIT_SCRIPT_TIMEOUT", "0")
	if got := scriptTimeoutFromEnv(); got != 0 {
		t.Fatalf("disabled timeout = %s, want 0", got)
	}

	t.Setenv("OS_INIT_SCRIPT_TIMEOUT", "90")
	if got := scriptTimeoutFromEnv(); got != 90*time.Second {
		t.Fatalf("numeric timeout = %s, want 90s", got)
	}

	t.Setenv("OS_INIT_SCRIPT_TIMEOUT", "2m")
	if got := scriptTimeoutFromEnv(); got != 2*time.Minute {
		t.Fatalf("duration timeout = %s, want 2m", got)
	}
}

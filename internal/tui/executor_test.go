package tui

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
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

func TestExecutorCancellationStopsCurrentGroupAndDoesNotContinue(t *testing.T) {
	tmp := t.TempDir()
	script := filepath.Join(tmp, "modules", "test", "run.sh")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(script, []byte("#!/bin/bash\necho started\nsleep 30\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	m := newExecutorModel([]modules.Module{{
		ID: "slow", Script: "test/run.sh", Label: "slow",
	}}, tmp, "", nil, "", ctx)

	done := make(chan tea.Msg, 1)
	go func() { done <- m.runCurrent()() }()
	time.Sleep(100 * time.Millisecond)
	cancel()

	select {
	case raw := <-done:
		msg, ok := raw.(scriptDoneMsg)
		if !ok {
			t.Fatalf("message = %T, want scriptDoneMsg", raw)
		}
		if msg.result.ExitCode == 0 || !strings.Contains(msg.result.Output, "取消") {
			t.Fatalf("canceled result = %+v", msg.result)
		}
		updated, cmd := m.Update(msg)
		if !updated.done || cmd == nil {
			t.Fatal("canceled executor should finish without starting another group")
		}
		if _, ok := cmd().(allDoneMsg); !ok {
			t.Fatalf("completion message = %T", cmd())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("canceled process group did not stop promptly")
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

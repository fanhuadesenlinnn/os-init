package tui

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/execution"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestExecutorCancellationStopsCurrentGroupAndDoesNotContinue(t *testing.T) {
	tmp := t.TempDir()
	script := filepath.Join(tmp, "modules", "test", "run.sh")
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(script, []byte("#!/bin/bash\necho started\nsleep 30\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	provider := filepath.Join(tmp, "modules", "provider.sh")
	providerScript := "#!/bin/bash\nshift\nscript=\"\"\nwhile [[ $# -gt 0 ]]; do case \"$1\" in --script) script=\"$2\"; shift 2 ;; --operation) shift 2 ;; --component) shift 2 ;; esac; done\nexec bash \"$(dirname \"$0\")/$script\"\n"
	if err := os.WriteFile(provider, []byte(providerScript), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	m := newExecutorModel([]modules.Module{{
		ID: "slow", Script: "test/run.sh", Label: "slow",
	}}, tmp, modules.OperationInstall, nil, "", ctx, nil)

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
		if msg.result.ExitCode == 0 || !strings.Contains(msg.result.Output, "canceled") {
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
	if got := scriptTimeoutFromEnv(); got != execution.DefaultTimeout {
		t.Fatalf("empty timeout = %s, want default %s", got, execution.DefaultTimeout)
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

func TestExecutorSkipsModuleAfterDependencyFailure(t *testing.T) {
	m := newExecutorModel([]modules.Module{
		{ID: "mise", Label: "mise"},
		{ID: "mise-go", Label: "Go", DependsOn: []string{"mise"}},
	}, t.TempDir(), modules.OperationInstall, nil, "", context.Background(), nil)
	m.current = 1
	m.failedModules["mise"] = true

	msg, ok := m.runCurrent()().(scriptDoneMsg)
	if !ok || msg.result.ExitCode != 125 || !strings.Contains(msg.result.Output, "mise") {
		t.Fatalf("dependency skip result = %#v", msg)
	}
}

func TestExecutorAddsBatchPackageMetadataStamp(t *testing.T) {
	tmp := t.TempDir()
	original := map[string]string{"EXISTING": "value"}
	m := newExecutorModel(nil, tmp, modules.OperationInstall, original, "", context.Background(), nil)
	if got := m.env["OS_INIT_PACKAGE_METADATA_STAMP"]; got != filepath.Join(tmp, ".package-metadata-ready") {
		t.Fatalf("metadata stamp = %q", got)
	}
	if m.env["EXISTING"] != "value" || len(original) != 1 {
		t.Fatalf("executor should preserve and copy caller env: executor=%v caller=%v", m.env, original)
	}
}

func TestOutputEndsWithNoteIgnoresANSI(t *testing.T) {
	output := "error\n\x1b[31mfinal failure\x1b[0m\n"
	if !outputEndsWithNote(output, "\x1b[31mfinal failure\x1b[0m") {
		t.Fatal("ANSI-formatted provider error should not be appended to the log twice")
	}
	if outputEndsWithNote(output, "different failure") {
		t.Fatal("different execution error should still be appended")
	}
}

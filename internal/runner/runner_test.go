package runner_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

func writeScript(t *testing.T, dir, relPath, content string) string {
	t.Helper()
	full := filepath.Join(dir, relPath)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
	provider := filepath.Join(dir, "modules", "provider.sh")
	if relPath != "provider.sh" {
		if err := os.WriteFile(provider, []byte(`#!/bin/bash
set -euo pipefail
shift
script=""; operation="install"; args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --script) script="$2"; shift 2 ;;
    --operation) operation="$2"; shift 2 ;;
    --component) args+=("$2"); shift 2 ;;
  esac
done
[[ "$operation" == update ]] && args+=(--update)
[[ "$operation" == uninstall ]] && args+=(--uninstall)
if [[ ${#args[@]} -gt 0 ]]; then
  exec bash "$(dirname "$0")/$script" "${args[@]}"
fi
exec bash "$(dirname "$0")/$script"
`), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return full
}

func TestRun_CapturesOutput(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/run.sh", "#!/bin/bash\necho hello\necho world")

	var lines []string
	onLine := func(line string) { lines = append(lines, line) }

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/run.sh",
		OnLine: onLine,
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ExitCode != 0 {
		t.Errorf("expected exit 0, got %d", result.ExitCode)
	}
	if len(lines) < 2 {
		t.Fatalf("expected >=2 lines, got %d", len(lines))
	}
	if lines[0] != "hello" {
		t.Errorf("expected 'hello', got %q", lines[0])
	}
}

func TestRun_CapturesExitCode(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/fail.sh", "#!/bin/bash\nexit 42")

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/fail.sh",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ExitCode != 42 {
		t.Errorf("expected exit 42, got %d", result.ExitCode)
	}
}

func TestRun_PassesComponents(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/args.sh", "#!/bin/bash\necho \"$@\"")

	var lines []string
	onLine := func(line string) { lines = append(lines, line) }

	_, err := runner.Run(context.Background(), runner.Params{
		TmpDir:     dir,
		Script:     "test/args.sh",
		Components: []string{"zsh", "direnv"},
		Operation:  "update",
		OnLine:     onLine,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) == 0 {
		t.Fatal("expected output")
	}
	if !strings.Contains(lines[0], "zsh") || !strings.Contains(lines[0], "direnv") || !strings.Contains(lines[0], "--update") {
		t.Errorf("expected args with components and mode, got %q", lines[0])
	}
}

func TestRun_UsesStableProviderProtocol(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	providerData, err := os.ReadFile(filepath.Join("..", "..", "modules", "provider.sh"))
	if err != nil {
		t.Fatal(err)
	}
	writeScript(t, dir, "modules/test/args.sh", "#!/bin/bash\nprintf '%s\\n' \"$@\"\n")
	if err := os.WriteFile(filepath.Join(dir, "modules", "provider.sh"), providerData, 0o755); err != nil {
		t.Fatal(err)
	}

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir, Script: "test/args.sh", Components: []string{"alpha", "beta"}, Operation: "update",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ExitCode != 0 || !strings.Contains(result.Output, "alpha\nbeta\n--update") {
		t.Fatalf("provider did not adapt the stable protocol: %+v", result)
	}
}

func TestRun_ContextCancellation(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/slow.sh", "#!/bin/bash\nsleep 60")

	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	result, err := runner.Run(ctx, runner.Params{
		TmpDir: dir,
		Script: "test/slow.sh",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ExitCode == 0 {
		t.Error("expected non-zero exit on cancellation")
	}
	if result.Duration > 5*time.Second {
		t.Error("cancellation took too long")
	}
}

func TestRun_WritesLogFile(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	logDir := t.TempDir()
	writeScript(t, dir, "modules/test/log.sh", "#!/bin/bash\necho logme")

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/log.sh",
		LogDir: logDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.LogFile == "" {
		t.Fatal("expected log file path")
	}
	data, err := os.ReadFile(result.LogFile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "logme") {
		t.Error("log file should contain script output")
	}
	info, err := os.Stat(result.LogFile)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Fatalf("log mode = %o, want 600", got)
	}
}

func TestRun_LogFileIncludesComponents(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	logDir := t.TempDir()
	writeScript(t, dir, "modules/test/log.sh", "#!/bin/bash\necho logme")

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir:     dir,
		Script:     "test/log.sh",
		Components: []string{"visual-studio-code"},
		LogDir:     logDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(filepath.Base(result.LogFile), "test-log-visual-studio-code-") {
		t.Fatalf("component-specific log filename = %q", result.LogFile)
	}
}

func TestRun_LogFilesAreUniqueWithinOneSecond(t *testing.T) {
	tmp := t.TempDir()
	writeScript(t, tmp, "modules/test/fast.sh", "#!/usr/bin/env bash\nexit 0\n")
	logDir := t.TempDir()
	first, err := runner.Run(context.Background(), runner.Params{TmpDir: tmp, Script: "test/fast.sh", LogDir: logDir})
	if err != nil {
		t.Fatal(err)
	}
	second, err := runner.Run(context.Background(), runner.Params{TmpDir: tmp, Script: "test/fast.sh", LogDir: logDir})
	if err != nil {
		t.Fatal(err)
	}
	if first.LogFile == second.LogFile {
		t.Fatalf("consecutive runs reused log file %q", first.LogFile)
	}
}

func TestRun_OversizedLineDoesNotDeadlock(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/huge.sh", "#!/bin/bash\ndd if=/dev/zero bs=1024 count=1200 2>/dev/null | tr '\\0' x\n")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	result, err := runner.Run(ctx, runner.Params{TmpDir: dir, Script: "test/huge.sh"})
	if err != nil {
		t.Fatal(err)
	}
	if ctx.Err() != nil {
		t.Fatal("oversized output line blocked the process until timeout")
	}
	if !strings.Contains(result.Output, "output reader error") {
		t.Fatalf("expected explicit reader error, got %q", result.Output)
	}
}

func TestRun_EnvVars(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/env.sh", "#!/bin/bash\necho $KICKSTART_USER_NAME")

	var lines []string
	onLine := func(line string) { lines = append(lines, line) }

	_, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/env.sh",
		Env:    map[string]string{"KICKSTART_USER_NAME": "TestUser"},
		OnLine: onLine,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) == 0 || lines[0] != "TestUser" {
		t.Errorf("expected 'TestUser', got %v", lines)
	}
}

func TestRun_StripANSI(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	writeScript(t, dir, "modules/test/color.sh", `#!/bin/bash
printf '\033[32mgreen\033[0m\n'`)

	var lines []string
	onLine := func(line string) { lines = append(lines, line) }

	_, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/color.sh",
		OnLine: onLine,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) == 0 {
		t.Fatal("expected output")
	}
	if strings.Contains(lines[0], "\033") {
		t.Error("ANSI codes should be stripped for OnLine callback")
	}
	if lines[0] != "green" {
		t.Errorf("expected 'green', got %q", lines[0])
	}
}

func TestRun_WritesLogFileWithoutANSI(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	logDir := t.TempDir()
	writeScript(t, dir, "modules/test/color-log.sh", `#!/bin/bash
printf '\033[0;32m[跳过]\033[0m Hack Nerd Font 已安装\n'`)

	result, err := runner.Run(context.Background(), runner.Params{
		TmpDir: dir,
		Script: "test/color-log.sh",
		LogDir: logDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(result.LogFile)
	if err != nil {
		t.Fatal(err)
	}
	logText := string(data)
	if strings.Contains(logText, "\033") || strings.Contains(logText, "0;32m") {
		t.Fatalf("log file should not contain ANSI color codes, got %q", logText)
	}
	if !strings.Contains(logText, "[跳过] Hack Nerd Font 已安装") {
		t.Fatalf("log file should contain clean message, got %q", logText)
	}
}

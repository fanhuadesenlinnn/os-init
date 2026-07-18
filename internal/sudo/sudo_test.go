package sudo

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestPrimeCommandPrefersNonInteractiveSudo(t *testing.T) {
	logPath := installFakeSudo(t, `
printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
if [ "$1" = "-n" ] && [ "$2" = "true" ]; then
  exit 0
fi
exit 1
`)

	cmd, ok := primeCommandForUID(1000)
	if !ok {
		t.Fatal("PrimeCommand unexpectedly unavailable")
	}
	if got, want := cmd.Args[1:], []string{"-n", "true"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("command args = %q, want %q", got, want)
	}
	if err := cmd.Run(); err != nil {
		t.Fatalf("non-interactive validation failed: %v", err)
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "-v") {
		t.Fatalf("interactive validation was invoked: %s", data)
	}
}

func TestPrimeCommandFallsBackToInteractiveValidation(t *testing.T) {
	logPath := installFakeSudo(t, `
printf '%s\n' "$*" >> "$FAKE_SUDO_LOG"
exit 1
`)

	cmd, ok := primeCommandForUID(1000)
	if !ok {
		t.Fatal("PrimeCommand unexpectedly unavailable")
	}
	if len(cmd.Args) < 4 || cmd.Args[1] != "-v" || cmd.Args[2] != "-p" {
		t.Fatalf("command args = %q, want interactive sudo validation", cmd.Args[1:])
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(data)); got != "-n true" {
		t.Fatalf("probe args = %q, want %q", got, "-n true")
	}
}

func TestPrimeCommandSkipsRoot(t *testing.T) {
	if cmd, ok := primeCommandForUID(0); ok || cmd != nil {
		t.Fatalf("root command = %v, ok = %v; want nil, false", cmd, ok)
	}
}

func installFakeSudo(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	logPath := filepath.Join(dir, "sudo.log")
	scriptPath := filepath.Join(dir, "sudo")
	if err := os.WriteFile(scriptPath, []byte("#!/bin/sh\nset -eu\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	t.Setenv("FAKE_SUDO_LOG", logPath)
	return logPath
}

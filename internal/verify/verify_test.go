package verify

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestMiseToolExecIsolatesVerificationFromCallerDirectory(t *testing.T) {
	home := t.TempDir()
	mountedCaller := t.TempDir()
	capture := filepath.Join(home, "mise-verify-env")
	miseBin := filepath.Join(home, ".local", "bin", "mise")
	if err := os.MkdirAll(filepath.Dir(miseBin), 0o755); err != nil {
		t.Fatal(err)
	}
	fakeMise := `#!/bin/sh
printf '%s\n' \
  "PWD=$PWD" \
  "HOME=$HOME" \
  "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
  "MISE_CONFIG_DIR=$MISE_CONFIG_DIR" \
  "MISE_GLOBAL_CONFIG_FILE=$MISE_GLOBAL_CONFIG_FILE" \
  "MISE_DATA_DIR=$MISE_DATA_DIR" \
  "MISE_CEILING_PATHS=$MISE_CEILING_PATHS" \
  "MISE_CONFIG_FILE=${MISE_CONFIG_FILE-unset}" \
  "MISE_TRUSTED_CONFIG_PATHS=${MISE_TRUSTED_CONFIG_PATHS-unset}" \
  > "$MISE_VERIFY_CAPTURE"
case "$1" in
  which) exit 0 ;;
  exec)
    shift
    [ "${1:-}" != "--" ] || shift
    exec "$@"
    ;;
  *) exit 2 ;;
esac
`
	if err := os.WriteFile(miseBin, []byte(fakeMise), 0o755); err != nil {
		t.Fatal(err)
	}

	originalDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(mountedCaller); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(originalDir) })
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin")
	t.Setenv("MISE_VERIFY_CAPTURE", capture)
	t.Setenv("MISE_CONFIG_FILE", "/mnt/mac/Users/alice/.config/mise/config.toml")
	t.Setenv("MISE_CONFIG_DIR", "/mnt/mac/Users/alice/.config/mise")
	t.Setenv("MISE_CEILING_PATHS", "/mnt/mac/Users/alice")
	t.Setenv("MISE_TRUSTED_CONFIG_PATHS", "/mnt/mac/Users/alice")

	module := modules.Module{Verify: modules.MiseToolExec("fake-tool", "sh", "-c", "exit 0")}
	result := New().Module(context.Background(), module)
	if !result.Active || !result.Passed {
		t.Fatalf("verification = %+v", result)
	}
	data, err := os.ReadFile(capture)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	for _, want := range []string{
		"PWD=" + home,
		"HOME=" + home,
		"XDG_CONFIG_HOME=" + filepath.Join(home, ".config"),
		"MISE_CONFIG_DIR=" + filepath.Join(home, ".config", "mise"),
		"MISE_GLOBAL_CONFIG_FILE=" + filepath.Join(home, ".config", "mise", "config.toml"),
		"MISE_DATA_DIR=" + filepath.Join(home, ".local", "share", "mise"),
		"MISE_CEILING_PATHS=" + home,
		"MISE_CONFIG_FILE=unset",
		"MISE_TRUSTED_CONFIG_PATHS=unset",
	} {
		if !strings.Contains(got, want+"\n") {
			t.Fatalf("mise verification environment missing %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "/mnt/mac/Users/alice") {
		t.Fatalf("host-mounted mise path leaked into verification:\n%s", got)
	}
}

func TestModuleEvaluatesComposedLiveChecks(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	config := filepath.Join(home, "config.txt")
	if err := os.WriteFile(config, []byte("enabled=true\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	module := modules.Module{Verify: modules.All(
		modules.Path("$HOME/config.txt"),
		modules.FileContains("$HOME/config.txt", "enabled=true"),
	)}
	result := New().Module(context.Background(), module)
	if !result.Active || !result.Passed {
		t.Fatalf("verification = %+v", result)
	}
}

func TestModuleIgnoresOtherGOOSChecks(t *testing.T) {
	other := "linux"
	if runtime.GOOS == "linux" {
		other = "darwin"
	}
	module := modules.Module{Verify: modules.OnGOOS(other, modules.Path("/definitely/missing"))}
	result := New().Module(context.Background(), module)
	if result.Active || !result.Passed {
		t.Fatalf("verification = %+v", result)
	}
}

package verify

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

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

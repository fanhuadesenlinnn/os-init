package execution_test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/execution"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestTimeoutFromEnv(t *testing.T) {
	tests := map[string]time.Duration{
		"":    execution.DefaultTimeout,
		"0":   0,
		"90":  90 * time.Second,
		"2m":  2 * time.Minute,
		"bad": execution.DefaultTimeout,
	}
	for value, want := range tests {
		if got := execution.TimeoutFromEnv(value); got != want {
			t.Fatalf("TimeoutFromEnv(%q) = %s, want %s", value, got, want)
		}
	}
}

func TestBatchEnvironmentAndDependencyPolicy(t *testing.T) {
	extra := map[string]string{"EXISTING": "value"}
	env := execution.BatchEnvironment(extra, "/tmp/os-init", true)
	if env["EXISTING"] != "value" || env["OS_INIT_NONINTERACTIVE"] != "1" {
		t.Fatalf("unexpected batch environment: %v", env)
	}
	if got := env["OS_INIT_PACKAGE_METADATA_STAMP"]; got != filepath.Join("/tmp/os-init", ".package-metadata-ready") {
		t.Fatalf("metadata stamp = %q", got)
	}
	if len(extra) != 1 {
		t.Fatalf("caller environment was mutated: %v", extra)
	}

	module := modules.Module{ID: "mise-go", DependsOn: []string{"mise", "dev-build-deps"}}
	if got := execution.FailedDependency(module, map[string]bool{"mise": true}); got != "mise" {
		t.Fatalf("failed dependency = %q", got)
	}
	result := execution.DependencySkip(module, modules.OperationInstall, "mise")
	if result.Status != "skipped" || result.ExitCode != 125 || result.Passed() {
		t.Fatalf("dependency skip = %+v", result)
	}
}

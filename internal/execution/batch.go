package execution

import (
	"fmt"
	"path/filepath"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

// BatchEnvironment gives every frontend the same isolated per-run package
// metadata stamp and never mutates the caller's environment map.
func BatchEnvironment(extra map[string]string, tmpDir string, nonInteractive bool) map[string]string {
	env := make(map[string]string, len(extra)+2)
	for key, value := range extra {
		env[key] = value
	}
	if nonInteractive {
		env["OS_INIT_NONINTERACTIVE"] = "1"
	}
	env["OS_INIT_PACKAGE_METADATA_STAMP"] = filepath.Join(tmpDir, ".package-metadata-ready")
	return env
}

// FailedDependency returns the first failed prerequisite of a planned module.
func FailedDependency(module modules.Module, failed map[string]bool) string {
	for _, dependency := range module.DependsOn {
		if failed[dependency] {
			return dependency
		}
	}
	return ""
}

// DependencySkip is the common result used when a prerequisite failed.
func DependencySkip(module modules.Module, operation modules.Operation, dependency string) Result {
	return Result{
		ModuleID:  module.ID,
		Label:     module.Label,
		Operation: operation,
		Status:    "skipped",
		ExitCode:  125,
		Error:     fmt.Sprintf("dependency module %s failed", dependency),
	}
}

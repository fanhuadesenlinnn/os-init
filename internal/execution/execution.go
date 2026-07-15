// Package execution provides the shared module execution use case used by
// interactive and non-interactive frontends.
package execution

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
	"github.com/fanhuadesenlinnn/os-init/internal/verify"
)

const DefaultTimeout = 45 * time.Minute

// Request describes one planned module invocation.
type Request struct {
	TmpDir            string
	Module            modules.Module
	Operation         modules.Operation
	Env               map[string]string
	LogDir            string
	Timeout           time.Duration
	Verify            bool
	ExpectedInstalled *bool
	OnLine            func(string)
	Recorder          state.Recorder
}

// Result is the frontend-independent outcome of one module invocation.
type Result struct {
	ModuleID          string
	Label             string
	Operation         modules.Operation
	Status            string
	ExitCode          int
	Output            string
	Duration          time.Duration
	LogFile           string
	VerifyActive      bool
	VerifyPassed      bool
	ExpectedInstalled bool
	Error             string
	ProviderProtocol  int
	ProviderStatus    string
	StateError        string
}

func (r Result) Passed() bool { return r.Status == "passed" }

// Run executes and optionally verifies one planned module.
func Run(ctx context.Context, req Request) Result {
	if req.Operation == "" {
		req.Operation = modules.OperationInstall
	}
	stepCtx := ctx
	var cancel context.CancelFunc
	if req.Timeout > 0 {
		stepCtx, cancel = context.WithTimeout(ctx, req.Timeout)
		defer cancel()
	}

	runResult, runErr := runner.Run(stepCtx, runner.Params{
		TmpDir:     req.TmpDir,
		Script:     req.Module.Script,
		Components: req.Module.Components,
		Operation:  string(req.Operation),
		Env:        req.Env,
		OnLine:     req.OnLine,
		LogDir:     req.LogDir,
	})
	result := Result{
		ModuleID: req.Module.ID, Label: req.Module.Label, Operation: req.Operation,
		Status: "passed", ExitCode: runResult.ExitCode, Output: runResult.Output,
		Duration: runResult.Duration, LogFile: runResult.LogFile,
		ProviderProtocol: runResult.ProviderProtocol, ProviderStatus: runResult.ProviderStatus,
	}
	if runErr != nil {
		result.Status = "failed"
		result.Error = runErr.Error()
	}
	if stepCtx.Err() == context.DeadlineExceeded {
		result.Status = "failed"
		result.ExitCode = -1
		result.Error = fmt.Sprintf("module execution timed out after %s", req.Timeout)
	}
	if ctx.Err() != nil {
		result.Status = "failed"
		result.ExitCode = -1
		result.Error = "module execution canceled"
	}
	if runResult.ExitCode != 0 {
		result.Status = "failed"
		if result.Error == "" {
			result.Error = LastOutputLine(runResult.Output)
		}
	}
	if result.Passed() && req.Verify && !req.Module.Verify.Empty() {
		checked := verify.New().Module(ctx, req.Module)
		result.VerifyActive = checked.Active
		result.VerifyPassed = checked.Passed
		wantInstalled := req.Operation != modules.OperationUninstall
		if req.ExpectedInstalled != nil {
			wantInstalled = *req.ExpectedInstalled
		}
		result.ExpectedInstalled = wantInstalled
		if checked.Active && checked.Passed != wantInstalled {
			result.Status = "failed"
			result.ExitCode = -1
			result.Error = "post-operation verification failed"
		}
	}
	if req.Recorder != nil {
		err := req.Recorder.Save(state.Record{ModuleID: result.ModuleID, Operation: string(result.Operation), Status: result.Status, ExitCode: result.ExitCode, ProviderProtocol: result.ProviderProtocol, ProviderStatus: result.ProviderStatus, AffectedPaths: append([]string(nil), req.Module.AffectedPaths...), LogFile: result.LogFile, Error: result.Error})
		if err != nil {
			result.StateError = err.Error()
		}
	}
	return result
}

func LastOutputLine(output string) string {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) == 0 || lines[0] == "" {
		return "provider failed"
	}
	return lines[len(lines)-1]
}

// TimeoutFromEnv parses the public timeout syntax consistently for every
// frontend. Numeric values are interpreted as seconds.
func TimeoutFromEnv(value string) time.Duration {
	value = strings.TrimSpace(value)
	if value == "" {
		return DefaultTimeout
	}
	if value == "0" {
		return 0
	}
	if parsed, err := time.ParseDuration(value); err == nil && parsed >= 0 {
		return parsed
	}
	if seconds, err := time.ParseDuration(value + "s"); err == nil && seconds >= 0 {
		return seconds
	}
	return DefaultTimeout
}

// Package headless implements the non-interactive OS Init control plane.
package headless

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	kickembed "github.com/fanhuadesenlinnn/os-init/internal/embed"
	"github.com/fanhuadesenlinnn/os-init/internal/execution"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
	"github.com/fanhuadesenlinnn/os-init/internal/verify"
)

// Options configures a non-interactive execution.
type Options struct {
	Assets            fs.FS
	Target            platform.Target
	ModuleIDs         []string
	All               bool
	Operation         modules.Operation
	Verify            bool
	ContinueOnError   bool
	Quiet             bool
	LogDir            string
	Timeout           time.Duration
	Env               map[string]string
	Output            io.Writer
	ExpectedInstalled *bool
	Recorder          state.Recorder
}

// LifecycleOptions configures repeated real installation lifecycle checks.
type LifecycleOptions struct {
	Options
	Phases []string
}

// CatalogEntry is the stable, machine-readable catalog representation.
type CatalogEntry struct {
	ID                  string               `json:"id"`
	Label               string               `json:"label"`
	Description         string               `json:"description"`
	Kind                modules.EntryKind    `json:"entry_kind"`
	Category            string               `json:"category"`
	Subsection          string               `json:"subsection,omitempty"`
	DependsOn           []string             `json:"depends_on,omitempty"`
	SupportedOperations []modules.Operation  `json:"supported_operations"`
	NeedsPrivilege      bool                 `json:"needs_privilege"`
	ManualSteps         []string             `json:"manual_steps,omitempty"`
	AutomationScope     string               `json:"automation_scope"`
	AutomationLifecycle string               `json:"automation_lifecycle"`
	AutomationReason    string               `json:"automation_reason,omitempty"`
	Delivery            modules.DeliveryKind `json:"delivery"`
}

// Plan is a compact serializable execution plan.
type Plan struct {
	Target            platform.Target              `json:"target"`
	Operation         modules.Operation            `json:"operation"`
	Requested         []string                     `json:"requested"`
	Modules           []CatalogEntry               `json:"modules"`
	AddedDependencies []planner.DependencyAddition `json:"added_dependencies,omitempty"`
	Issues            []planner.Issue              `json:"issues,omitempty"`
}

// StepResult describes one provider invocation and its verification result.
type StepResult struct {
	ModuleID          string            `json:"module_id"`
	Label             string            `json:"label"`
	Operation         modules.Operation `json:"operation"`
	Status            string            `json:"status"`
	ExitCode          int               `json:"exit_code"`
	DurationMS        int64             `json:"duration_ms"`
	LogFile           string            `json:"log_file,omitempty"`
	VerifyActive      bool              `json:"verify_active"`
	VerifyPassed      bool              `json:"verify_passed"`
	ExpectedInstalled bool              `json:"expected_installed"`
	Error             string            `json:"error,omitempty"`
	ProviderProtocol  int               `json:"provider_protocol,omitempty"`
	ProviderStatus    string            `json:"provider_status,omitempty"`
	StateError        string            `json:"state_error,omitempty"`
}

// Report is the durable result of a headless run.
type Report struct {
	SchemaVersion int               `json:"schema_version"`
	StartedAt     time.Time         `json:"started_at"`
	FinishedAt    time.Time         `json:"finished_at"`
	Target        platform.Target   `json:"target"`
	Operation     modules.Operation `json:"operation"`
	Requested     []string          `json:"requested"`
	Success       bool              `json:"success"`
	Results       []StepResult      `json:"results"`
}

// Catalog returns modules available on the detected target.
func Catalog(target platform.Target) []CatalogEntry {
	mods := modules.ResolveForContext(modules.ForTarget(target), os.Geteuid() == 0)
	entries := make([]CatalogEntry, 0, len(mods))
	for _, mod := range mods {
		entries = append(entries, catalogEntry(mod, target))
	}
	return entries
}

// BuildPlan resolves IDs, presets, dependencies, target constraints and order.
func BuildPlan(target platform.Target, ids []string, all bool, operation modules.Operation) (Plan, []modules.Module, error) {
	if operation == "" {
		operation = modules.OperationInstall
	}
	available := modules.ResolveForContext(modules.ForTarget(target), os.Geteuid() == 0)
	selected, requested, err := selectModules(available, ids, all, operation)
	if err != nil {
		return Plan{}, nil, err
	}
	built := planner.Build(selected, target, planner.Options{Operation: operation})
	compact := Plan{
		Target:            target,
		Operation:         operation,
		Requested:         requested,
		AddedDependencies: built.AddedDependencies,
		Issues:            built.Issues,
	}
	for _, mod := range built.Modules {
		compact.Modules = append(compact.Modules, catalogEntry(mod, target))
	}
	if issue, blocked := built.BlockingIssue(); blocked {
		return compact, nil, fmt.Errorf("%s", issue.MessageEN)
	}
	return compact, built.Modules, nil
}

// Execute runs a planned operation one module at a time and optionally verifies
// the resulting live-system state after each invocation.
func Execute(ctx context.Context, opts Options) (Report, error) {
	if opts.Target.GOOS == "" {
		opts.Target = platform.Detect()
	}
	if opts.Operation == "" {
		opts.Operation = modules.OperationInstall
	}
	if opts.Output == nil {
		opts.Output = os.Stdout
	}
	if opts.LogDir == "" {
		opts.LogDir = "logs"
	}
	if opts.Timeout == 0 {
		opts.Timeout = execution.TimeoutFromEnv(os.Getenv("OS_INIT_SCRIPT_TIMEOUT"))
	}

	plan, planned, err := BuildPlan(opts.Target, opts.ModuleIDs, opts.All, opts.Operation)
	report := Report{
		SchemaVersion: 1,
		StartedAt:     time.Now().UTC(),
		Target:        opts.Target,
		Operation:     opts.Operation,
		Requested:     append([]string(nil), plan.Requested...),
		Success:       true,
	}
	if err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}
	if len(planned) == 0 {
		report.FinishedAt = time.Now().UTC()
		return report, errors.New("execution plan is empty")
	}
	if err := nonInteractivePrivilegeCheck(planned, opts.Target); err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}

	tmpDir, cleanup, err := kickembed.Extract(opts.Assets)
	if err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}
	defer cleanup()

	for _, mod := range planned {
		if ctx.Err() != nil {
			report.Success = false
			break
		}
		if !opts.Quiet {
			fmt.Fprintf(opts.Output, "[%s] %s (%s)\n", opts.Operation, mod.ID, mod.Label)
		}
		result := execution.Run(ctx, execution.Request{
			TmpDir:            tmpDir,
			Module:            mod,
			Operation:         opts.Operation,
			Env:               mergedEnv(opts.Env),
			LogDir:            opts.LogDir,
			Timeout:           opts.Timeout,
			Verify:            opts.Verify,
			ExpectedInstalled: opts.ExpectedInstalled,
			Recorder:          opts.Recorder,
			OnLine: func(line string) {
				if !opts.Quiet {
					fmt.Fprintln(opts.Output, line)
				}
			},
		})
		step := StepResult{
			ModuleID:     mod.ID,
			Label:        mod.Label,
			Operation:    opts.Operation,
			Status:       "passed",
			ExitCode:     result.ExitCode,
			DurationMS:   result.Duration.Milliseconds(),
			LogFile:      result.LogFile,
			VerifyActive: result.VerifyActive, VerifyPassed: result.VerifyPassed,
			ExpectedInstalled: result.ExpectedInstalled, Error: result.Error,
			ProviderProtocol: result.ProviderProtocol, ProviderStatus: result.ProviderStatus,
			StateError: result.StateError,
		}
		if step.Status != "passed" {
			report.Success = false
		}
		report.Results = append(report.Results, step)
		if step.Status != "passed" && !opts.ContinueOnError {
			break
		}
	}
	report.FinishedAt = time.Now().UTC()
	if ctx.Err() != nil {
		return report, ctx.Err()
	}
	if !report.Success {
		return report, errors.New("one or more modules failed")
	}
	return report, nil
}

// Verify checks selected modules without changing the system.
func Verify(ctx context.Context, target platform.Target, ids []string, all bool) (Report, error) {
	available := modules.ResolveForContext(modules.ForTarget(target), os.Geteuid() == 0)
	selected, requested, err := selectModules(available, ids, all, modules.OperationInstall)
	report := Report{
		SchemaVersion: 1,
		StartedAt:     time.Now().UTC(),
		Target:        target,
		Operation:     "verify",
		Requested:     requested,
		Success:       true,
	}
	if err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}
	for _, mod := range selected {
		checked := verify.New().Module(ctx, mod)
		step := StepResult{ModuleID: mod.ID, Label: mod.Label, Operation: "verify", Status: "passed", VerifyActive: checked.Active, VerifyPassed: checked.Passed}
		if !checked.Active {
			step.Status = "skipped"
			step.Error = "module has no active verification check"
		} else if !checked.Passed {
			step.Status = "failed"
			step.Error = "verification failed"
			report.Success = false
		}
		report.Results = append(report.Results, step)
	}
	report.FinishedAt = time.Now().UTC()
	if !report.Success {
		return report, errors.New("one or more module verifications failed")
	}
	return report, nil
}

// TestLifecycle installs each requested module through the same public control
// plane used by unattended installs, then repeats, updates and uninstalls it as
// requested. CI should normally pass one module per fresh job/container for
// isolation; --all is intended as a sequential compatibility sweep.
func TestLifecycle(ctx context.Context, opts LifecycleOptions) (Report, error) {
	if opts.Target.GOOS == "" {
		opts.Target = platform.Detect()
	}
	available := modules.ResolveForContext(modules.ForTarget(opts.Target), os.Geteuid() == 0)
	selected, requested, err := selectModules(available, opts.ModuleIDs, opts.All, modules.OperationInstall)
	report := Report{
		SchemaVersion: 1,
		StartedAt:     time.Now().UTC(),
		Target:        opts.Target,
		Operation:     "test",
		Requested:     requested,
		Success:       true,
	}
	if err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}
	phases := opts.Phases
	if len(phases) == 0 {
		phases = []string{"install", "reinstall", "update", "uninstall"}
	}
	if err := validateLifecyclePhases(phases); err != nil {
		report.Success = false
		report.FinishedAt = time.Now().UTC()
		return report, err
	}
	stop := false
	for _, mod := range selected {
		baseline := verify.New().Module(ctx, mod)
		baselineInstalled := baseline.Active && baseline.Passed
		moduleFailed := false
		for _, phase := range phases {
			if moduleFailed && phase != "uninstall" {
				report.Results = append(report.Results, StepResult{
					ModuleID: mod.ID, Label: mod.Label, Operation: modules.Operation(phase),
					Status: "skipped", Error: "an earlier lifecycle phase failed",
				})
				continue
			}
			operation := modules.Operation(phase)
			if phase == "reinstall" {
				operation = modules.OperationInstall
			}
			if !mod.SupportsOperation(operation) {
				report.Results = append(report.Results, StepResult{
					ModuleID: mod.ID, Label: mod.Label, Operation: operation,
					Status: "skipped", Error: "operation is not supported by this module",
				})
				continue
			}
			runOpts := opts.Options
			runOpts.Target = opts.Target
			runOpts.ModuleIDs = []string{mod.ID}
			runOpts.All = false
			runOpts.Operation = operation
			runOpts.Verify = true
			runOpts.ContinueOnError = false
			expectedInstalled := true
			if operation == modules.OperationUninstall {
				expectedInstalled = baselineInstalled
			}
			runOpts.ExpectedInstalled = &expectedInstalled
			partial, runErr := Execute(ctx, runOpts)
			if phase == "reinstall" {
				for i := range partial.Results {
					partial.Results[i].Operation = "reinstall"
				}
			}
			report.Results = append(report.Results, partial.Results...)
			if runErr != nil {
				report.Success = false
				moduleFailed = true
			}
		}
		if moduleFailed && !opts.ContinueOnError {
			stop = true
		}
		if stop {
			break
		}
	}
	report.FinishedAt = time.Now().UTC()
	if !report.Success {
		return report, errors.New("one or more module lifecycle checks failed")
	}
	return report, nil
}

func validateLifecyclePhases(phases []string) error {
	for _, phase := range phases {
		switch phase {
		case "install", "reinstall", "update", "uninstall":
		default:
			return fmt.Errorf("unsupported lifecycle phase: %s", phase)
		}
	}
	return nil
}

// WriteJSON writes a report or catalog using stable indentation.
func WriteJSON(w io.Writer, value any) error {
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}

func selectModules(available []modules.Module, ids []string, all bool, operation modules.Operation) ([]modules.Module, []string, error) {
	byID := make(map[string]modules.Module, len(available))
	for _, mod := range available {
		byID[mod.ID] = mod
	}
	if all {
		selected := make([]modules.Module, 0, len(available))
		requested := make([]string, 0, len(available))
		for _, mod := range available {
			if mod.EntryKind != modules.EntryModule || !mod.SupportsOperation(operation) {
				continue
			}
			selected = append(selected, mod)
			requested = append(requested, mod.ID)
		}
		return selected, requested, nil
	}
	if len(ids) == 0 {
		return nil, nil, errors.New("specify at least one module ID or --all")
	}
	selected := make([]modules.Module, 0, len(ids))
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			continue
		}
		mod, ok := byID[id]
		if !ok {
			return nil, ids, fmt.Errorf("module is not available on this system: %s", id)
		}
		selected = append(selected, mod)
		seen[id] = true
	}
	return selected, append([]string(nil), ids...), nil
}

func catalogEntry(mod modules.Module, target platform.Target) CatalogEntry {
	scope, lifecycle, reason := automationPolicy(mod)
	return CatalogEntry{
		ID:                  mod.ID,
		Label:               mod.Label,
		Description:         mod.Description,
		Kind:                mod.EntryKind,
		Category:            mod.Category,
		Subsection:          mod.Subsection,
		DependsOn:           mod.DependsOn,
		SupportedOperations: mod.SupportedOperations,
		NeedsPrivilege:      modules.SelectionNeedsPrivilege([]modules.Module{mod}, target),
		ManualSteps:         mod.ManualSteps,
		AutomationScope:     scope,
		AutomationLifecycle: lifecycle,
		AutomationReason:    reason,
		Delivery:            mod.DeliveryFor(target),
	}
}

func automationPolicy(mod modules.Module) (scope, lifecycle, reason string) {
	scope, lifecycle = "container", declaredLifecycle(mod)
	if mod.EntryKind == modules.EntryPreset {
		return "planner", "plan-only", "presets expand dependencies and have no provider"
	}
	if mod.EntryKind == modules.EntryAction {
		return "hosted", "install-only", "diagnostic actions are not lifecycle modules"
	}
	if mod.OS == "darwin" {
		return "hosted", lifecycle, "requires a fresh GitHub-hosted macOS VM"
	}
	switch mod.ID {
	case "kernel-sysctl", "kernel-limits", "kernel-scheduler", "kernel-autotune", "network-ipv4", "docker":
		return "hosted", "full", "requires a disposable native Ubuntu VM for meaningful verification"
	case "mihomo", "arch-mihomo":
		return "hosted", "install-only", "service activation requires a real test configuration"
	case "network-tune":
		return "manual", "install-only", "may disrupt the GitHub runner network while changing queues and firewall rules"
	case "arch-dns":
		return "manual", "install-only", "may replace resolver configuration and disconnect the GitHub job"
	case "arch-desktop":
		return "manual", "install-only", "requires an Arch graphical session, display manager and virtual GPU"
	case "wsl-systemd":
		return "manual", "full", "requires a real WSL2 distribution and a host-side wsl.exe --shutdown restart"
	default:
		return scope, lifecycle, reason
	}
}

func declaredLifecycle(mod modules.Module) string {
	install := mod.SupportsOperation(modules.OperationInstall)
	update := mod.SupportsOperation(modules.OperationUpdate)
	uninstall := mod.SupportsOperation(modules.OperationUninstall)
	switch {
	case install && update && uninstall:
		return "full"
	case install && update:
		return "install-update"
	case install:
		return "install-only"
	default:
		return "custom"
	}
}

func nonInteractivePrivilegeCheck(selected []modules.Module, target platform.Target) error {
	if os.Geteuid() == 0 || !modules.SelectionNeedsPrivilege(selected, target) {
		return nil
	}
	if _, err := exec.LookPath("sudo"); err != nil {
		return errors.New("selected modules require sudo, but sudo is not installed")
	}
	if err := exec.Command("sudo", "-n", "true").Run(); err != nil {
		return errors.New("selected modules require non-interactive sudo; run sudo -v first or configure passwordless sudo")
	}
	return nil
}

func mergedEnv(extra map[string]string) map[string]string {
	env := map[string]string{"OS_INIT_NONINTERACTIVE": "1"}
	for key, value := range extra {
		env[key] = value
	}
	return env
}

// AbsLogDir makes relative report paths predictable for callers that change
// working directories after execution.
func AbsLogDir(path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

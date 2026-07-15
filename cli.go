package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	appconfig "github.com/fanhuadesenlinnn/os-init/internal/config"
	"github.com/fanhuadesenlinnn/os-init/internal/headless"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/runtimecontext"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
)

type moduleFlags struct {
	all             bool
	yes             bool
	quiet           bool
	continueOnError bool
	verify          bool
	format          string
	report          string
	junit           string
	logDir          string
	timeout         time.Duration
	exclude         string
	lifecycle       string
	operation       string
}

func runModuleCommand(args []string) error {
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		fmt.Print(moduleUsageText())
		return nil
	}
	appconfig.Apply(assets)
	runtimeCtx := runtimecontext.Detect()
	target := runtimeCtx.Target
	command := args[0]

	switch command {
	case "list":
		flags, ids, err := parseModuleFlags(command, args[1:])
		if err != nil {
			return err
		}
		if len(ids) > 0 {
			return errors.New("module list does not accept module IDs")
		}
		entries := filterCatalog(headless.Catalog(target), flags.exclude)
		switch flags.format {
		case "json":
			return headless.WriteJSON(os.Stdout, entries)
		case "ids":
			for _, entry := range entries {
				if entry.Kind != modules.EntryAction {
					fmt.Println(entry.ID)
				}
			}
			return nil
		case "text", "":
			for _, entry := range entries {
				fmt.Printf("%-30s %s\n", entry.ID, entry.Label)
			}
			return nil
		default:
			return fmt.Errorf("unsupported format: %s", flags.format)
		}

	case "plan":
		flags, ids, err := parseModuleFlags(command, args[1:])
		if err != nil {
			return err
		}
		operation, err := parseOperation(flags.operation)
		if err != nil {
			return err
		}
		ids = normalizeSelection(&flags, ids, target, operation)
		plan, _, planErr := headless.BuildPlan(target, ids, flags.all, operation)
		if flags.format == "json" {
			if err := headless.WriteJSON(os.Stdout, plan); err != nil {
				return err
			}
		} else {
			fmt.Printf("Target: %s/%s (%s), environment=%s", target.GOOS, target.Family, target.ID, target.Environment)
			if target.Environment == platform.EnvironmentWSL {
				fmt.Printf(", wsl%d", target.WSLVersion)
			}
			fmt.Printf("\nOperation: %s\n", operation)
			for _, entry := range plan.Modules {
				fmt.Printf("- %-28s %s\n", entry.ID, entry.Label)
			}
		}
		return planErr

	case "install", "update", "uninstall":
		flags, ids, err := parseModuleFlags(command, args[1:])
		if err != nil {
			return err
		}
		if !flags.yes {
			return errors.New("non-interactive changes require --yes")
		}
		operation := modules.Operation(command)
		ids = normalizeSelection(&flags, ids, target, operation)
		report, runErr := runHeadlessOperation(flags, ids, runtimeCtx, operation)
		if err := emitReport(flags, report); err != nil {
			return err
		}
		return runErr

	case "verify":
		flags, ids, err := parseModuleFlags(command, args[1:])
		if err != nil {
			return err
		}
		ids = normalizeSelection(&flags, ids, target, modules.OperationInstall)
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		report, runErr := headless.Verify(ctx, target, ids, flags.all)
		if err := emitReport(flags, report); err != nil {
			return err
		}
		return runErr

	case "test":
		flags, ids, err := parseModuleFlags(command, args[1:])
		if err != nil {
			return err
		}
		if !flags.yes {
			return errors.New("module lifecycle tests change the system and require --yes")
		}
		ids = normalizeSelection(&flags, ids, target, modules.OperationInstall)
		ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer cancel()
		report, runErr := headless.TestLifecycle(ctx, headless.LifecycleOptions{
			Options: headless.Options{
				Assets: assets, Target: target, ModuleIDs: ids, All: flags.all,
				Verify: true, ContinueOnError: flags.continueOnError,
				Quiet: flags.quiet || flags.format == "json", LogDir: flags.logDir,
				Timeout: flags.timeout, Output: os.Stdout,
				Env:      runtimecontext.Merge(runtimeCtx.Environment(), nonInteractiveEnv()),
				Recorder: state.Default(),
			},
			Phases: splitCSV(flags.lifecycle),
		})
		if err := emitReport(flags, report); err != nil {
			return err
		}
		return runErr
	default:
		return fmt.Errorf("unknown module command: %s\n\n%s", command, moduleUsageText())
	}
}

func parseModuleFlags(command string, args []string) (moduleFlags, []string, error) {
	values := moduleFlags{format: "text", verify: true, logDir: "logs", operation: "install"}
	set := flag.NewFlagSet("os-init module "+command, flag.ContinueOnError)
	set.SetOutput(io.Discard)
	set.BoolVar(&values.all, "all", false, "select all available modules")
	set.BoolVar(&values.yes, "yes", false, "approve non-interactive changes")
	set.BoolVar(&values.quiet, "quiet", false, "suppress live provider output")
	set.BoolVar(&values.continueOnError, "continue-on-error", false, "continue after a module failure")
	set.BoolVar(&values.verify, "verify", true, "verify state after execution")
	set.StringVar(&values.format, "format", "text", "text, json, or ids")
	set.StringVar(&values.report, "report", "", "write JSON report to a file")
	set.StringVar(&values.junit, "junit", "", "write JUnit XML report to a file")
	set.StringVar(&values.logDir, "log-dir", "logs", "provider log directory")
	set.DurationVar(&values.timeout, "timeout", 0, "per-module timeout; 0 uses configuration")
	set.StringVar(&values.exclude, "exclude", "", "comma-separated module IDs to exclude")
	set.StringVar(&values.lifecycle, "lifecycle", "install,reinstall,update,uninstall", "lifecycle phases")
	set.StringVar(&values.operation, "operation", "install", "plan operation")
	if err := set.Parse(args); err != nil {
		return values, nil, fmt.Errorf("%w\n\n%s", err, moduleUsageText())
	}
	return values, set.Args(), nil
}

func runHeadlessOperation(flags moduleFlags, ids []string, runtimeCtx runtimecontext.Context, operation modules.Operation) (headless.Report, error) {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	return headless.Execute(ctx, headless.Options{
		Assets: assets, Target: runtimeCtx.Target, ModuleIDs: ids, All: flags.all,
		Operation: operation, Verify: flags.verify,
		ContinueOnError: flags.continueOnError,
		Quiet:           flags.quiet || flags.format == "json", LogDir: flags.logDir,
		Timeout: flags.timeout, Env: runtimecontext.Merge(runtimeCtx.Environment(), nonInteractiveEnv()), Output: os.Stdout, Recorder: state.Default(),
	})
}

func emitReport(flags moduleFlags, report headless.Report) error {
	if flags.format == "json" {
		if err := headless.WriteJSON(os.Stdout, report); err != nil {
			return err
		}
	} else {
		for _, result := range report.Results {
			fmt.Printf("%-8s %-30s %-10s", strings.ToUpper(result.Status), result.ModuleID, result.Operation)
			if result.Error != "" {
				fmt.Printf(" %s", result.Error)
			}
			fmt.Println()
		}
		fmt.Printf("Result: success=%t modules=%d\n", report.Success, len(report.Results))
	}
	if flags.report != "" {
		if err := writeFile(flags.report, func(w io.Writer) error { return headless.WriteJSON(w, report) }); err != nil {
			return err
		}
	}
	if flags.junit != "" {
		if err := writeFile(flags.junit, func(w io.Writer) error { return headless.WriteJUnit(w, report) }); err != nil {
			return err
		}
	}
	return nil
}

func writeFile(path string, write func(io.Writer) error) error {
	if dir := filepath.Dir(path); dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if err := write(file); err != nil {
		_ = file.Close()
		return err
	}
	return file.Close()
}

func filterCatalog(entries []headless.CatalogEntry, excluded string) []headless.CatalogEntry {
	blocked := stringSet(splitCSV(excluded))
	filtered := make([]headless.CatalogEntry, 0, len(entries))
	for _, entry := range entries {
		if !blocked[entry.ID] {
			filtered = append(filtered, entry)
		}
	}
	return filtered
}

func applyExcludes(ids []string, excluded string) []string {
	blocked := stringSet(splitCSV(excluded))
	if len(blocked) == 0 {
		return ids
	}
	filtered := make([]string, 0, len(ids))
	for _, id := range ids {
		if !blocked[id] {
			filtered = append(filtered, id)
		}
	}
	return filtered
}

func normalizeSelection(flags *moduleFlags, ids []string, target platform.Target, operation modules.Operation) []string {
	if !flags.all || strings.TrimSpace(flags.exclude) == "" {
		return applyExcludes(ids, flags.exclude)
	}
	entries := filterCatalog(headless.Catalog(target), flags.exclude)
	ids = ids[:0]
	for _, entry := range entries {
		if entry.Kind == modules.EntryModule && supportsOperation(entry.SupportedOperations, operation) {
			ids = append(ids, entry.ID)
		}
	}
	flags.all = false
	return ids
}

func supportsOperation(operations []modules.Operation, operation modules.Operation) bool {
	for _, candidate := range operations {
		if candidate == operation {
			return true
		}
	}
	return false
}

func splitCSV(value string) []string {
	var result []string
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}

func stringSet(values []string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
}

func parseOperation(value string) (modules.Operation, error) {
	operation := modules.Operation(value)
	switch operation {
	case modules.OperationInstall, modules.OperationUpdate, modules.OperationUninstall:
		return operation, nil
	default:
		return "", fmt.Errorf("unsupported operation: %s", value)
	}
}

func nonInteractiveEnv() map[string]string {
	env := map[string]string{}
	if value := os.Getenv("OS_INIT_GIT_NAME"); value != "" {
		env["KICKSTART_USER_NAME"] = value
	}
	if value := os.Getenv("OS_INIT_GIT_EMAIL"); value != "" {
		env["KICKSTART_USER_EMAIL"] = value
	}
	return env
}

func moduleUsageText() string {
	lines := []string{
		"OS Init non-interactive module commands",
		"",
		"Usage:",
		"  os-init module list [--format text|json|ids]",
		"  os-init module plan [flags] <module-id>...",
		"  os-init module install|update|uninstall --yes [flags] <module-id>...",
		"  os-init module verify [flags] <module-id>...",
		"  os-init module test --yes [flags] <module-id>...",
		"",
		"Selection:",
		"  --all                    Select all modules available on this system",
		"  --exclude id,id          Exclude module IDs from catalog/list selection",
		"",
		"Execution:",
		"  --yes                    Required for commands that change the system",
		"  --quiet                  Suppress live output; full logs are still saved",
		"  --continue-on-error      Continue with later modules after a failure",
		"  --verify                 Run declarative post-operation checks (default true)",
		"  --timeout 45m            Per-module timeout; 0 uses OS_INIT_SCRIPT_TIMEOUT",
		"  --log-dir logs           Directory for private provider logs",
		"",
		"Reports:",
		"  --format text|json       Console output format",
		"  --report report.json     Write the complete JSON report",
		"  --junit report.xml       Write a JUnit XML report",
		"",
		"Lifecycle testing:",
		"  --lifecycle install,reinstall,update,uninstall",
		"",
		"Examples:",
		"  os-init module list --format ids",
		"  os-init module plan terminal-ncdu docker",
		"  os-init module install --yes --quiet terminal-ncdu",
		"  os-init module test --yes --report report.json --junit report.xml terminal-ncdu",
	}
	return strings.Join(lines, "\n") + "\n"
}

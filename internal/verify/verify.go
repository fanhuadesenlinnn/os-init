// Package verify evaluates the declarative installation checks attached to
// modules. It is intentionally independent from the TUI so interactive and
// non-interactive callers can use the same definition of "installed".
package verify

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

// Result describes whether a check applied to this platform and whether it
// passed. An inactive platform-specific check is not a failure.
type Result struct {
	Passed bool `json:"passed"`
	Active bool `json:"active"`
}

// Checker evaluates module verification expressions against the live system.
type Checker struct {
	goos    string
	brewMu  sync.Mutex
	brew    map[string]map[string]bool
	brewErr map[string]error
}

// New returns a checker for the current operating system.
func New() *Checker {
	return &Checker{
		goos:    runtime.GOOS,
		brew:    map[string]map[string]bool{},
		brewErr: map[string]error{},
	}
}

// Module evaluates a module's complete verification expression.
func (c *Checker) Module(ctx context.Context, module modules.Module) Result {
	passed, active := c.evaluate(ctx, module.Verify)
	return Result{Passed: passed, Active: active}
}

func (c *Checker) evaluate(ctx context.Context, check modules.Check) (bool, bool) {
	if check.GOOS != "" && check.GOOS != c.goos {
		return true, false
	}
	if len(check.All) > 0 {
		active := false
		for _, child := range check.All {
			passed, childActive := c.evaluate(ctx, child)
			active = active || childActive
			if childActive && !passed {
				return false, true
			}
		}
		return true, active
	}
	if len(check.Any) > 0 {
		active := false
		for _, child := range check.Any {
			passed, childActive := c.evaluate(ctx, child)
			active = active || childActive
			if childActive && passed {
				return true, true
			}
		}
		return false, active
	}
	if check.Kind == "" {
		return false, false
	}

	value := ""
	if len(check.Values) > 0 {
		value = check.Values[0]
	}
	switch check.Kind {
	case modules.CheckCommand:
		_, err := exec.LookPath(value)
		return err == nil, true
	case modules.CheckCommandRun:
		return commandSucceeds(ctx, check.Values), true
	case modules.CheckPath:
		_, err := os.Stat(expandPath(value))
		return err == nil, true
	case modules.CheckFileContains:
		if len(check.Values) != 2 {
			return false, true
		}
		data, err := os.ReadFile(expandPath(check.Values[0]))
		return err == nil && strings.Contains(string(data), check.Values[1]), true
	case modules.CheckBrewCask:
		return c.brewInstalled(ctx, "--cask", value), true
	case modules.CheckBrewFormula:
		return c.brewInstalled(ctx, "--formula", value), true
	case modules.CheckZshBlock:
		return blockExists(filepath.Join(userHome(), ".zshrc"), value), true
	case modules.CheckShellBlock:
		return shellBlockExists(value), true
	case modules.CheckSystemd:
		return commandSucceeds(ctx, []string{"systemctl", "is-active", "--quiet", value}), true
	case modules.CheckUserGroup:
		out, err := exec.CommandContext(ctx, "id", "-nG").Output()
		if err != nil {
			return false, true
		}
		for _, group := range strings.Fields(string(out)) {
			if group == value {
				return true, true
			}
		}
		return false, true
	default:
		return false, true
	}
}

func commandSucceeds(ctx context.Context, args []string) bool {
	if len(args) == 0 || args[0] == "" {
		return false
	}
	return exec.CommandContext(ctx, args[0], args[1:]...).Run() == nil
}

func (c *Checker) brewInstalled(ctx context.Context, kind, name string) bool {
	c.brewMu.Lock()
	defer c.brewMu.Unlock()
	if _, ok := c.brew[kind]; !ok {
		out, err := exec.CommandContext(ctx, "brew", "list", kind).Output()
		c.brewErr[kind] = err
		items := map[string]bool{}
		for _, item := range strings.Fields(string(out)) {
			items[item] = true
		}
		c.brew[kind] = items
	}
	return c.brewErr[kind] == nil && c.brew[kind][name]
}

func shellBlockExists(name string) bool {
	home := userHome()
	for _, rc := range []string{".zshrc", ".bashrc"} {
		if blockExists(filepath.Join(home, rc), name) {
			return true
		}
	}
	return false
}

func blockExists(path, name string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	text := string(data)
	return strings.Contains(text, "# >>> os-init "+name+" >>>") &&
		strings.Contains(text, "# <<< os-init "+name+" <<<")
}

func userHome() string {
	home, _ := os.UserHomeDir()
	return home
}

func expandPath(path string) string {
	home := userHome()
	if path == "$HOME" {
		return home
	}
	if strings.HasPrefix(path, "$HOME/") {
		return filepath.Join(home, strings.TrimPrefix(path, "$HOME/"))
	}
	return os.ExpandEnv(path)
}

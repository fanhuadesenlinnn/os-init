package tui

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

type installStatusChecker struct {
	lookPath func(string) (string, error)
	stat     func(string) (os.FileInfo, error)
	readFile func(string) ([]byte, error)
	run      func(context.Context, string, ...string) ([]byte, error)
	homeDir  func() (string, error)

	brewCasksOnce   sync.Once
	brewCasks       map[string]bool
	brewCasksErr    error
	brewFormulaOnce sync.Once
	brewFormula     map[string]bool
	brewFormulaErr  error
}

func defaultInstallStatusChecker() *installStatusChecker {
	return &installStatusChecker{
		lookPath: exec.LookPath,
		stat:     os.Stat,
		readFile: os.ReadFile,
		run: func(ctx context.Context, name string, args ...string) ([]byte, error) {
			cmd := exec.CommandContext(ctx, name, args...)
			return cmd.CombinedOutput()
		},
		homeDir: os.UserHomeDir,
	}
}

func (c *installStatusChecker) moduleInstalled(ctx context.Context, m modules.Module) bool {
	checks := 0

	if m.InstalledBrewCask != "" {
		checks++
		if !c.brewCaskInstalled(ctx, m.InstalledBrewCask) && !c.pathExists(m.InstalledCheck) {
			return false
		}
	} else if m.InstalledBrewFormula != "" {
		checks++
		if !c.brewFormulaInstalled(ctx, m.InstalledBrewFormula) {
			return false
		}
	} else {
		if m.InstalledCmd != "" {
			checks++
			if !c.commandExists(m.InstalledCmd) {
				return false
			}
		}
		for _, command := range m.InstalledCommands {
			checks++
			if !c.commandSucceeds(ctx, command) {
				return false
			}
		}
		if len(m.InstalledAnyCommands) > 0 {
			checks++
			if !c.anyCommandSucceeds(ctx, m.InstalledAnyCommands) {
				return false
			}
		}
		if m.InstalledCheck != "" {
			checks++
			if !c.pathExists(m.InstalledCheck) {
				return false
			}
		}
		if len(m.InstalledAnyChecks) > 0 {
			checks++
			if !c.anyPathExists(m.InstalledAnyChecks) {
				return false
			}
		}
	}

	if m.InstalledGrepFile != "" {
		checks++
		if !c.grepFile(m.InstalledGrepFile) {
			return false
		}
	}
	for _, grepFile := range m.InstalledGrepFiles {
		checks++
		if !c.grepFile(grepFile) {
			return false
		}
	}
	for _, block := range m.InstalledZshBlocks {
		checks++
		if !c.zshBlockExists(block) {
			return false
		}
	}
	for _, block := range m.InstalledShellBlocks {
		checks++
		if !c.shellBlockExists(block) {
			return false
		}
	}
	for _, service := range m.InstalledSystemdServices {
		checks++
		if !c.systemdServiceActive(ctx, service) {
			return false
		}
	}
	for _, group := range m.InstalledUserGroups {
		checks++
		if !c.currentUserInGroup(ctx, group) {
			return false
		}
	}

	return checks > 0
}

func (c *installStatusChecker) commandExists(command string) bool {
	_, err := c.lookPath(command)
	return err == nil
}

func (c *installStatusChecker) commandSucceeds(ctx context.Context, command []string) bool {
	if len(command) == 0 || command[0] == "" {
		return false
	}
	_, err := c.run(ctx, command[0], command[1:]...)
	return err == nil
}

func (c *installStatusChecker) anyCommandSucceeds(ctx context.Context, commands [][]string) bool {
	for _, command := range commands {
		if c.commandSucceeds(ctx, command) {
			return true
		}
	}
	return false
}

func (c *installStatusChecker) pathExists(path string) bool {
	if path == "" {
		return false
	}
	_, err := c.stat(c.expandPath(path))
	return err == nil
}

func (c *installStatusChecker) anyPathExists(paths []string) bool {
	for _, path := range paths {
		if c.pathExists(path) {
			return true
		}
	}
	return false
}

func (c *installStatusChecker) grepFile(spec string) bool {
	path, pattern, ok := strings.Cut(spec, ":")
	if !ok || path == "" || pattern == "" {
		return false
	}
	data, err := c.readFile(c.expandPath(path))
	return err == nil && strings.Contains(string(data), pattern)
}

func (c *installStatusChecker) zshBlockExists(name string) bool {
	home, err := c.homeDir()
	if err != nil || home == "" {
		return false
	}
	return c.blockExists(filepath.Join(home, ".zshrc"), name)
}

func (c *installStatusChecker) shellBlockExists(name string) bool {
	files := c.shellRCFiles()
	if len(files) == 0 {
		return false
	}
	for _, file := range files {
		if c.blockExists(file, name) {
			return true
		}
	}
	return false
}

func (c *installStatusChecker) shellRCFiles() []string {
	home, err := c.homeDir()
	if err != nil || home == "" {
		return nil
	}
	var files []string
	for _, name := range []string{".zshrc", ".bashrc"} {
		path := filepath.Join(home, name)
		if _, err := c.stat(path); err == nil {
			files = append(files, path)
		}
	}
	if len(files) == 0 {
		files = append(files, filepath.Join(home, ".zshrc"))
	}
	return files
}

func (c *installStatusChecker) blockExists(path, name string) bool {
	data, err := c.readFile(path)
	if err != nil {
		return false
	}
	begin := "# >>> os-init " + name + " >>>"
	end := "# <<< os-init " + name + " <<<"
	text := string(data)
	return strings.Contains(text, begin) && strings.Contains(text, end)
}

func (c *installStatusChecker) systemdServiceActive(ctx context.Context, service string) bool {
	if service == "" {
		return false
	}
	_, err := c.run(ctx, "systemctl", "is-active", "--quiet", service)
	return err == nil
}

func (c *installStatusChecker) currentUserInGroup(ctx context.Context, group string) bool {
	if group == "" {
		return false
	}
	out, err := c.run(ctx, "id", "-nG")
	if err != nil {
		return false
	}
	for _, item := range strings.Fields(string(out)) {
		if item == group {
			return true
		}
	}
	return false
}

func (c *installStatusChecker) brewCaskInstalled(ctx context.Context, name string) bool {
	c.brewCasksOnce.Do(func() {
		c.brewCasks, c.brewCasksErr = c.brewList(ctx, "--cask")
	})
	return c.brewCasksErr == nil && c.brewCasks[name]
}

func (c *installStatusChecker) brewFormulaInstalled(ctx context.Context, name string) bool {
	c.brewFormulaOnce.Do(func() {
		c.brewFormula, c.brewFormulaErr = c.brewList(ctx, "--formula")
	})
	return c.brewFormulaErr == nil && c.brewFormula[name]
}

func (c *installStatusChecker) brewList(ctx context.Context, kind string) (map[string]bool, error) {
	out, err := c.run(ctx, "brew", "list", kind)
	if err != nil {
		return nil, err
	}
	result := map[string]bool{}
	for _, line := range strings.Fields(string(out)) {
		result[line] = true
	}
	return result, nil
}

func (c *installStatusChecker) expandPath(path string) string {
	home, err := c.homeDir()
	if err == nil && home != "" {
		if path == "$HOME" {
			return home
		}
		if strings.HasPrefix(path, "$HOME/") {
			return filepath.Join(home, strings.TrimPrefix(path, "$HOME/"))
		}
	}
	return os.ExpandEnv(path)
}

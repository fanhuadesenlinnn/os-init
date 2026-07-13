package tui

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func testStatusChecker(t *testing.T, home string) *installStatusChecker {
	t.Helper()

	commands := map[string]bool{}
	runOK := map[string][]byte{}
	c := &installStatusChecker{
		lookPath: func(name string) (string, error) {
			if commands[name] {
				return "/bin/" + filepath.Base(name), nil
			}
			return "", errors.New("missing")
		},
		stat:     os.Stat,
		readFile: os.ReadFile,
		run: func(_ context.Context, name string, args ...string) ([]byte, error) {
			key := name
			for _, arg := range args {
				key += "\x00" + arg
			}
			out, ok := runOK[key]
			if !ok {
				return nil, errors.New("failed")
			}
			return out, nil
		},
		homeDir: func() (string, error) { return home, nil },
	}

	c.run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
		key := name
		for _, arg := range args {
			key += "\x00" + arg
		}
		out, ok := runOK[key]
		if !ok {
			return nil, errors.New("failed")
		}
		return out, nil
	}
	t.Cleanup(func() {
		_ = commands
		_ = runOK
	})
	return c
}

func TestInstallStatusChecker_DetectsHomebrewCaskWithoutAppPath(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)
	checker.run = fakeRun(map[string][]byte{
		"brew\x00list\x00--cask": []byte("font-hack-nerd-font\n"),
	})

	mod := modules.Module{Verify: modules.BrewCask("font-hack-nerd-font")}
	if !checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("expected Homebrew cask module to be installed")
	}
}

func TestInstallStatusChecker_DetectsHomebrewFormulaWithoutPATHCommand(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)
	checker.run = fakeRun(map[string][]byte{
		"brew\x00list\x00--formula": []byte("iftop\nrsync\nbind\n"),
	})

	mod := modules.Module{Verify: modules.BrewFormula("iftop")}
	if !checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("expected Homebrew formula module to be installed even when command is outside PATH")
	}
}

func TestInstallStatusChecker_RequiresMacOSSpecificFormulaAndPaths(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)
	checker.goos = "darwin"
	checker.run = fakeRun(map[string][]byte{
		"brew\x00list\x00--formula": []byte("zoxide\n"),
	})
	writeFile(t, filepath.Join(home, ".zshrc"), "# >>> os-init zoxide >>>\neval zoxide\n# <<< os-init zoxide <<<\n")
	writeFile(t, filepath.Join(home, ".config", "nvim", "init.lua"), "-- config-yuan\n")
	writeFile(t, filepath.Join(home, ".config", "neovide", "config.toml"), "[font]\n")

	zoxide := modules.Module{Verify: modules.All(modules.BrewFormula("zoxide"), modules.ZshBlock("zoxide"))}
	if !checker.moduleInstalled(context.Background(), zoxide) {
		t.Fatal("zoxide should require both the Homebrew formula and managed zsh block on macOS")
	}

	combined := modules.Module{Verify: modules.All(
		modules.Path("$HOME/.config/nvim/init.lua"),
		modules.OnGOOS("darwin", modules.Path("$HOME/.config/neovide/config.toml")),
	)}
	if !checker.moduleInstalled(context.Background(), combined) {
		t.Fatal("combined Neovim module should require its macOS-specific config path")
	}
	if err := os.Remove(filepath.Join(home, ".config", "neovide", "config.toml")); err != nil {
		t.Fatal(err)
	}
	if checker.moduleInstalled(context.Background(), combined) {
		t.Fatal("combined Neovim module should be incomplete without the Neovide config on macOS")
	}
}

func TestInstallStatusChecker_ShellIntegrationRequiresManagedBlock(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)
	checker.lookPath = func(name string) (string, error) {
		if name == "zsh" {
			return "/bin/zsh", nil
		}
		return "", errors.New("missing")
	}

	mod := modules.Module{Verify: modules.All(modules.Command("zsh"), modules.ShellBlock("oh-my-zsh"))}
	if checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("zsh should not be complete without the shell block")
	}

	writeFile(t, filepath.Join(home, ".zshrc"), "# >>> os-init oh-my-zsh >>>\nsource \"$ZSH/oh-my-zsh.sh\"\n# <<< os-init oh-my-zsh <<<\n")
	if !checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("zsh should be complete with command and managed shell block")
	}
}

func TestInstallStatusChecker_ShellBlockCanExistInOneInteractiveRc(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)

	writeFile(t, filepath.Join(home, ".zshrc"), "# >>> os-init go >>>\nexport PATH=\"/usr/local/go/bin:$PATH\"\n# <<< os-init go <<<\n")
	writeFile(t, filepath.Join(home, ".bashrc"), "# user bash config\n")

	mod := modules.Module{Verify: modules.ShellBlock("go")}
	if !checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("shell integration should be complete when the managed block exists in one interactive rc file")
	}
}

func TestInstallStatusChecker_SystemServiceRequiresCommandsServicesAndGroup(t *testing.T) {
	home := t.TempDir()
	checker := testStatusChecker(t, home)
	checker.run = fakeRun(map[string][]byte{
		"docker\x00--version":                                     []byte("Docker version 1\n"),
		"dockerd\x00--version":                                    []byte("Docker daemon\n"),
		"docker\x00compose\x00version":                            []byte("Docker Compose\n"),
		"systemctl\x00is-active\x00--quiet\x00docker.service":     nil,
		"systemctl\x00is-active\x00--quiet\x00containerd.service": nil,
		"id\x00-nG": []byte("staff docker\n"),
	})

	mod := modules.Module{Verify: modules.All(
		modules.CommandRun("docker", "--version"),
		modules.CommandRun("dockerd", "--version"),
		modules.CommandRun("docker", "compose", "version"),
		modules.SystemdService("docker.service"),
		modules.SystemdService("containerd.service"),
		modules.UserGroup("docker"),
	)}
	if !checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("docker should be complete when commands, services, and group all pass")
	}

	checker.run = fakeRun(map[string][]byte{
		"docker\x00--version":                                 []byte("Docker version 1\n"),
		"dockerd\x00--version":                                []byte("Docker daemon\n"),
		"docker\x00compose\x00version":                        []byte("Docker Compose\n"),
		"systemctl\x00is-active\x00--quiet\x00docker.service": nil,
		"id\x00-nG": []byte("staff docker\n"),
	})
	if checker.moduleInstalled(context.Background(), mod) {
		t.Fatal("docker should not be complete when containerd service is inactive")
	}
}

func TestMacOSFormulaShellHooksDeclareStatusBlocks(t *testing.T) {
	mods := modules.AllModules()
	for _, id := range []string{"macos-cli-zoxide", "macos-cli-mise"} {
		mod := findTUIModule(t, mods, id)
		if mod.Kind != modules.KindShellIntegration {
			t.Fatalf("%s kind = %q, want shell integration", id, mod.Kind)
		}
		want := modules.ZshBlock(mod.Components[0])
		if !checkContains(mod.Verify, want) {
			t.Fatalf("%s verification does not contain zsh block %q: %#v", id, mod.Components[0], mod.Verify)
		}
	}
}

func checkContains(check, wanted modules.Check) bool {
	if reflect.DeepEqual(check, wanted) {
		return true
	}
	for _, child := range append(check.All, check.Any...) {
		if checkContains(child, wanted) {
			return true
		}
	}
	return false
}

func fakeRun(outputs map[string][]byte) func(context.Context, string, ...string) ([]byte, error) {
	return func(_ context.Context, name string, args ...string) ([]byte, error) {
		key := name
		for _, arg := range args {
			key += "\x00" + arg
		}
		out, ok := outputs[key]
		if !ok {
			return nil, errors.New("failed")
		}
		return out, nil
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func findTUIModule(t *testing.T, mods []modules.Module, id string) modules.Module {
	t.Helper()
	for _, mod := range mods {
		if mod.ID == id {
			return mod
		}
	}
	t.Fatalf("module %s not found", id)
	return modules.Module{}
}

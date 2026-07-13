package modules

// EntryKind separates stateful modules from dependency-only presets and
// one-shot actions while keeping a single flat selection surface in the TUI.
type EntryKind string

const (
	EntryModule EntryKind = "module"
	EntryPreset EntryKind = "preset"
	EntryAction EntryKind = "action"
)

// Operation is a lifecycle operation supported by a module provider.
type Operation string

const (
	OperationInstall   Operation = "install"
	OperationUpdate    Operation = "update"
	OperationUninstall Operation = "uninstall"
)

// Phase provides a stable, language-independent order for otherwise
// unrelated modules. Dependencies still take precedence over this hint.
type Phase int

const (
	PhaseBootstrap Phase = iota + 10
	PhaseShell
	PhaseTerminal
	PhaseNetwork
	PhaseRuntime
	PhaseApplication
	PhaseSystem
	PhaseAction
)

// CheckKind identifies an atomic verification mechanism.
type CheckKind string

const (
	CheckCommand      CheckKind = "command"
	CheckCommandRun   CheckKind = "command-run"
	CheckPath         CheckKind = "path"
	CheckFileContains CheckKind = "file-contains"
	CheckBrewCask     CheckKind = "brew-cask"
	CheckBrewFormula  CheckKind = "brew-formula"
	CheckZshBlock     CheckKind = "zsh-block"
	CheckShellBlock   CheckKind = "shell-block"
	CheckSystemd      CheckKind = "systemd"
	CheckUserGroup    CheckKind = "user-group"
)

// Check is a composable verification expression. All and Any may contain
// nested expressions; an atomic check uses Kind and Values.
type Check struct {
	Kind   CheckKind
	Values []string
	GOOS   string
	All    []Check
	Any    []Check
}

func All(checks ...Check) Check { return Check{All: compactChecks(checks)} }
func Any(checks ...Check) Check { return Check{Any: compactChecks(checks)} }

func Command(name string) Check       { return atom(CheckCommand, name) }
func CommandRun(args ...string) Check { return Check{Kind: CheckCommandRun, Values: args} }
func Path(path string) Check          { return atom(CheckPath, path) }
func FileContains(path, pattern string) Check {
	return Check{Kind: CheckFileContains, Values: []string{path, pattern}}
}
func BrewCask(name string) Check            { return atom(CheckBrewCask, name) }
func BrewFormula(name string) Check         { return atom(CheckBrewFormula, name) }
func ZshBlock(name string) Check            { return atom(CheckZshBlock, name) }
func ShellBlock(name string) Check          { return atom(CheckShellBlock, name) }
func SystemdService(name string) Check      { return atom(CheckSystemd, name) }
func UserGroup(name string) Check           { return atom(CheckUserGroup, name) }
func OnGOOS(goos string, check Check) Check { check.GOOS = goos; return check }

func atom(kind CheckKind, value string) Check {
	if value == "" {
		return Check{}
	}
	return Check{Kind: kind, Values: []string{value}}
}

func compactChecks(checks []Check) []Check {
	out := make([]Check, 0, len(checks))
	for _, check := range checks {
		if !check.Empty() {
			out = append(out, check)
		}
	}
	return out
}

func (c Check) Empty() bool {
	return c.Kind == "" && len(c.All) == 0 && len(c.Any) == 0
}

// Preset is a dependency-only catalog entry. It never reaches the executor.
type Preset struct {
	ID          string
	Label       string
	Description string
	Subsection  string
	OS          string
	Families    []string
	Includes    []string
	Phase       Phase
	Order       int
}

// Action is a one-shot catalog entry such as doctor or status.
type Action struct {
	ID          string
	Label       string
	Description string
	Subsection  string
	OS          string
	Families    []string
	Script      string
	Components  []string
	Privilege   PrivilegePolicy
	Phase       Phase
	Order       int
}

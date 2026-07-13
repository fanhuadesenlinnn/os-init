package tui

import (
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

// screen represents which TUI screen is active.
type screen int

const (
	screenLanguage screen = iota
	screenBanner
	screenConfig
	screenMenu
	screenMode
	screenGitInfo
	screenConfirm
	screenExecutor
	screenSummary
)

// mode represents the operation mode.
type mode int

const (
	modeInstall mode = iota
	modeUpdate
	modeUninstall
)

func (m mode) String() string {
	switch m {
	case modeInstall:
		return text("安装", "install")
	case modeUpdate:
		return text("更新", "update")
	case modeUninstall:
		return text("卸载", "uninstall")
	}
	return ""
}

// Flag returns the CLI flag for the mode.
func (m mode) Flag() string {
	switch m {
	case modeUpdate:
		return "--update"
	case modeUninstall:
		return "--uninstall"
	}
	return ""
}

// Shared messages between screens.

type switchScreenMsg struct{ to screen }

type languageSelectedMsg struct{ code string }

type configReadyMsg struct{}

type selectedModulesMsg struct{ modules []modules.Module }

type selectedModeMsg struct{ mode mode }

type userInfoMsg struct {
	name    string
	email   string
	webhook string
}

type confirmMsg struct{ confirmed bool }

type sudoDoneMsg struct{ err error }

type scriptOutputMsg struct {
	module string
	line   string
}

type scriptDoneMsg struct{ result runner.Result }

type allDoneMsg struct{}

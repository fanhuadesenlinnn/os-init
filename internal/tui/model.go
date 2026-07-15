package tui

import (
	"context"
	"io/fs"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	appconfig "github.com/fanhuadesenlinnn/os-init/internal/config"
	kickembed "github.com/fanhuadesenlinnn/os-init/internal/embed"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
	"github.com/fanhuadesenlinnn/os-init/internal/runtimecontext"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
	"github.com/fanhuadesenlinnn/os-init/internal/sudo"
)

// Config holds parameters passed from main.go.
type Config struct {
	Assets   fs.FS
	Version  string
	Commit   string
	Runtime  runtimecontext.Context
	Recorder state.Recorder
}

// Model is the root Bubble Tea model.
type Model struct {
	config Config
	screen screen
	width  int
	height int

	// Screen models
	language      languageModel
	banner        bannerModel
	configStartup configStartupModel
	menu          menuModel
	mode          modeModel
	gitInfo       gitInfoModel
	confirm       confirmModel
	executor      executorModel
	summary       summaryModel

	// Shared state
	requestedModules []modules.Module
	selectedModules  []modules.Module
	selectedMode     mode
	executionPlan    planner.Plan
	executionEnv     map[string]string
	userName         string
	userEmail        string
	webhookURL       string
	tmpDir           string
	cleanupFn        func()
	sudoCancel       func()
	executionCancel  context.CancelFunc
	exitAfterExecute bool
}

// New creates a new root Model.
func New(cfg Config) Model {
	appconfig.Apply(cfg.Assets)
	if cfg.Runtime.Target.GOOS == "" {
		cfg.Runtime = runtimecontext.Detect()
	}
	model := Model{
		config:        cfg,
		screen:        screenLanguage,
		language:      newLanguageModel(),
		configStartup: newConfigStartupModel(cfg.Assets),
		mode:          newModeModel(),
	}
	return model
}

func (m Model) startMenu() (Model, tea.Cmd) {
	target := m.config.Runtime.Target
	mods := modules.ForTarget(target)
	mods = modules.ResolveForContext(mods, os.Geteuid() == 0)
	m.menu = newMenuModel(mods)
	m.screen = screenMenu
	return m, m.menu.Init()
}

func (m Model) startExecution() (Model, tea.Cmd) {
	tmpDir, cleanup, err := kickembed.Extract(m.config.Assets)
	if err != nil {
		if m.sudoCancel != nil {
			m.sudoCancel()
			m.sudoCancel = nil
		}
		m.screen = screenSummary
		m.summary = newSummaryModel([]runner.Result{{
			Module:   text("启动执行", "Start execution"),
			ExitCode: -1,
			Output:   err.Error(),
		}}, m.selectedModules)
		return m, nil
	}
	m.tmpDir = tmpDir
	m.cleanupFn = cleanup
	globalCleanup = cleanup

	env := map[string]string{
		"KICKSTART_USER_NAME":  m.userName,
		"KICKSTART_USER_EMAIL": m.userEmail,
	}
	env = runtimecontext.Merge(m.config.Runtime.Environment(), env)
	for k, v := range m.executionEnv {
		env[k] = v
	}

	executionCtx, executionCancel := context.WithCancel(context.Background())
	m.executionCancel = executionCancel
	globalExecutionCancel = executionCancel
	m.executor = newExecutorModel(
		m.selectedModules,
		tmpDir,
		plannerOperation(m.selectedMode),
		env,
		m.webhookURL,
		executionCtx,
		m.config.Recorder,
	)
	m.executor.program = globalProgram
	m.screen = screenExecutor
	return m, m.executor.Init()
}

func (m Model) showMode() (Model, tea.Cmd) {
	m.mode = newModeModel(m.requestedModules...)
	m.screen = screenMode
	return m, m.mode.Init()
}

func (m Model) buildExecutionPlan() (Model, bool) {
	base := m.requestedModules
	if len(base) == 0 {
		base = m.selectedModules
	}

	plan := planner.Build(base, m.config.Runtime.Target, planner.Options{Operation: plannerOperation(m.selectedMode)})
	m.executionPlan = plan
	if issue, ok := plan.BlockingIssue(); ok {
		m.selectedModules = base
		m.menu.notice = planIssueText(issue)
		m.screen = screenMenu
		return m, false
	}

	m.selectedModules = plan.Modules
	return m, true
}

func (m Model) showGitInfoOrConfirm() (Model, tea.Cmd) {
	showUserInfo := modules.NeedsUserInfo(m.selectedModules)
	showWebhook := modules.NeedsWebhook(m.selectedModules)
	if !showUserInfo && !showWebhook {
		return m.showConfirm()
	}
	m.gitInfo = newGitInfoModel(showUserInfo, showWebhook)
	m.screen = screenGitInfo
	return m, m.gitInfo.Init()
}

func (m Model) showConfirm() (Model, tea.Cmd) {
	if len(m.executionPlan.Modules) == 0 && len(m.selectedModules) > 0 {
		next, ok := m.buildExecutionPlan()
		if !ok {
			return next, nil
		}
		m = next
	}
	m.confirm = newConfirmModelForPlan(m.executionPlan, m.selectedMode, m.config.Runtime.Target)
	m.screen = screenConfirm
	return m, m.confirm.Init()
}

func plannerOperation(m mode) modules.Operation {
	switch m {
	case modeUpdate:
		return modules.OperationUpdate
	case modeUninstall:
		return modules.OperationUninstall
	default:
		return modules.OperationInstall
	}
}

func planIssueText(issue planner.Issue) string {
	return text(issue.MessageZH, issue.MessageEN)
}

var (
	// globalProgram holds the tea.Program reference for sending messages
	// from background goroutines (e.g., real-time script output).
	globalProgram *tea.Program

	// globalCleanup is called on SIGTERM or abnormal exit to remove tmpdir.
	globalCleanup func()

	// globalExecutionCancel stops the active process group before cleanup.
	globalExecutionCancel context.CancelFunc
)

// SetProgram injects the tea.Program reference. Must be called
// after tea.NewProgram and before Run.
func SetProgram(p *tea.Program) {
	globalProgram = p
}

// RunCleanup calls the registered cleanup function (tmpdir removal).
func RunCleanup() {
	if globalExecutionCancel != nil {
		globalExecutionCancel()
		globalExecutionCancel = nil
	}
	if globalCleanup != nil {
		globalCleanup()
		globalCleanup = nil
	}
}

// Init returns the initial command for the program.
func (m Model) Init() tea.Cmd {
	return m.initScreen(m.screen)
}

// Update handles messages and routes them to the active screen.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		// Fall through — let active screen also handle window size

	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			if m.screen == screenExecutor && m.executionCancel != nil {
				m.executionCancel()
				m.executor.canceling = true
				m.exitAfterExecute = true
				return m, nil
			}
			if m.cleanupFn != nil {
				m.cleanupFn()
			}
			if m.sudoCancel != nil {
				m.sudoCancel()
			}
			return m, tea.Quit
		}
	}

	// Route to active screen
	var cmd tea.Cmd
	switch m.screen {
	case screenLanguage:
		m.language, cmd = m.language.Update(msg)
	case screenBanner:
		m.banner, cmd = m.banner.Update(msg)
	case screenConfig:
		m.configStartup, cmd = m.configStartup.Update(msg)
	case screenMenu:
		m.menu, cmd = m.menu.Update(msg)
	case screenMode:
		m.mode, cmd = m.mode.Update(msg)
	case screenGitInfo:
		m.gitInfo, cmd = m.gitInfo.Update(msg)
	case screenConfirm:
		m.confirm, cmd = m.confirm.Update(msg)
	case screenExecutor:
		m.executor, cmd = m.executor.Update(msg)
	case screenSummary:
		m.summary, cmd = m.summary.Update(msg)
	}

	// Handle screen transition messages
	switch msg := msg.(type) {
	case languageSelectedMsg:
		appconfig.SetRuntimeOverride("OS_INIT_LANG", msg.code)
		appconfig.Apply(m.config.Assets)
		m.configStartup = newConfigStartupModel(m.config.Assets)
		if os.Getenv("OS_INIT_CONFIG_PROMPT") == "0" {
			return m.startMenu()
		}
		m.screen = screenConfig
		return m, m.configStartup.Init()

	case configReadyMsg:
		return m.startMenu()

	case switchScreenMsg:
		m.screen = msg.to
		switch msg.to {
		case screenGitInfo:
			return m.showGitInfoOrConfirm()
		case screenConfirm:
			return m.showConfirm()
		}
		return m, m.initScreen(msg.to)

	case selectedModulesMsg:
		m.requestedModules = msg.modules
		m.selectedModules = msg.modules
		m.executionPlan = planner.Plan{}
		m.executionEnv = nil
		next, ok := m.buildExecutionPlan()
		if !ok {
			return next, nil
		}
		m = next
		return m.showMode()

	case selectedModeMsg:
		m.selectedMode = msg.mode
		next, ok := m.buildExecutionPlan()
		if !ok {
			return next, nil
		}
		m = next
		if m.selectedMode == modeUninstall {
			return m.showConfirm()
		}
		return m.showGitInfoOrConfirm()

	case userInfoMsg:
		m.userName = msg.name
		m.userEmail = msg.email
		m.webhookURL = msg.webhook
		return m.showConfirm()

	case confirmMsg:
		if m.sudoCancel == nil && selectionNeedsSudoPrime(m.selectedModules, m.config.Runtime.Target) {
			if cmd, ok := sudo.PrimeCommand(); ok {
				return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
					return sudoDoneMsg{err: err}
				})
			}
		}
		return m.startExecution()

	case sudoDoneMsg:
		if msg.err != nil {
			m.confirm.err = sudo.PrimeError(msg.err)
			m.screen = screenConfirm
			return m, nil
		}
		m.sudoCancel = sudo.StartKeepAlive()
		return m.startExecution()

	case allDoneMsg:
		if m.cleanupFn != nil {
			m.cleanupFn()
			m.cleanupFn = nil
			globalCleanup = nil
		}
		if m.sudoCancel != nil {
			m.sudoCancel()
			m.sudoCancel = nil
		}
		if m.executionCancel != nil {
			m.executionCancel()
			m.executionCancel = nil
			globalExecutionCancel = nil
		}
		if m.exitAfterExecute {
			return m, tea.Quit
		}
		m.summary = newSummaryModel(m.executor.summaryResults, m.selectedModules)
		m.screen = screenSummary
		return m, m.summary.Init()
	}

	return m, cmd
}

func selectionNeedsSudoPrime(selected []modules.Module, target platform.Target) bool {
	return selectionNeedsSudoPrimeForUID(selected, target, os.Geteuid())
}

func selectionNeedsSudoPrimeForUID(selected []modules.Module, target platform.Target, effectiveUID int) bool {
	return effectiveUID != 0 && modules.SelectionNeedsPrivilege(selected, target)
}

// View renders the active screen.
func (m Model) View() string {
	switch m.screen {
	case screenLanguage:
		return m.language.View()
	case screenBanner:
		return m.banner.View()
	case screenConfig:
		return m.configStartup.View()
	case screenMenu:
		return m.menu.View()
	case screenMode:
		return m.mode.View()
	case screenGitInfo:
		return m.gitInfo.View()
	case screenConfirm:
		return m.confirm.View()
	case screenExecutor:
		return m.executor.View()
	case screenSummary:
		return m.summary.View()
	}
	return ""
}

func (m Model) initScreen(s screen) tea.Cmd {
	switch s {
	case screenLanguage:
		return m.language.Init()
	case screenBanner:
		return m.banner.Init()
	case screenConfig:
		return m.configStartup.Init()
	case screenMenu:
		return m.menu.Init()
	case screenMode:
		return m.mode.Init()
	case screenGitInfo:
		return m.gitInfo.Init()
	case screenConfirm:
		return m.confirm.Init()
	case screenExecutor:
		return m.executor.Init()
	case screenSummary:
		return m.summary.Init()
	}
	return nil
}

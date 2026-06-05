package tui

import (
	"io/fs"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	appconfig "github.com/fanhuadesenlinnn/os-init/internal/config"
	kickembed "github.com/fanhuadesenlinnn/os-init/internal/embed"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/sudo"
)

// Config holds parameters passed from main.go.
type Config struct {
	Assets  fs.FS
	Version string
	Commit  string
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
	archDevKit    archDevKitModel
	mode          modeModel
	gitInfo       gitInfoModel
	confirm       confirmModel
	executor      executorModel
	summary       summaryModel

	// Shared state
	selectedModules []modules.Module
	selectedMode    mode
	executionEnv    map[string]string
	userName        string
	userEmail       string
	webhookURL      string
	tmpDir          string
	cleanupFn       func()
	sudoCancel      func()
}

// New creates a new root Model.
func New(cfg Config) Model {
	appconfig.Apply(cfg.Assets)
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
	target := platform.Detect()
	mods := modules.ForTarget(target)
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
		m.summary = newSummaryModel(nil)
		return m, nil
	}
	m.tmpDir = tmpDir
	m.cleanupFn = cleanup
	globalCleanup = cleanup

	env := map[string]string{
		"KICKSTART_USER_NAME":  m.userName,
		"KICKSTART_USER_EMAIL": m.userEmail,
	}
	for k, v := range m.executionEnv {
		env[k] = v
	}

	m.executor = newExecutorModel(
		m.selectedModules,
		tmpDir,
		m.selectedMode.Flag(),
		env,
		m.webhookURL,
	)
	m.executor.program = globalProgram
	m.screen = screenExecutor
	return m, m.executor.Init()
}

var (
	// globalProgram holds the tea.Program reference for sending messages
	// from background goroutines (e.g., real-time script output).
	globalProgram *tea.Program

	// globalCleanup is called on SIGTERM or abnormal exit to remove tmpdir.
	globalCleanup func()
)

// SetProgram injects the tea.Program reference. Must be called
// after tea.NewProgram and before Run.
func SetProgram(p *tea.Program) {
	globalProgram = p
}

// RunCleanup calls the registered cleanup function (tmpdir removal).
func RunCleanup() {
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
	case screenArchDevKit:
		m.archDevKit, cmd = m.archDevKit.Update(msg)
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
		case screenArchDevKit:
			m.archDevKit = newArchDevKitModel(m.config.Assets)
			return m, m.archDevKit.Init()
		case screenGitInfo:
			showUserInfo := modules.NeedsUserInfo(m.selectedModules)
			showWebhook := modules.NeedsWebhook(m.selectedModules)
			if !showUserInfo && !showWebhook {
				m.screen = screenConfirm
				m.confirm = newConfirmModelForSelection(m.selectedModules, m.selectedMode, platform.Detect())
				return m, m.confirm.Init()
			}
			m.gitInfo = newGitInfoModel(showUserInfo, showWebhook)
			return m, m.gitInfo.Init()
		case screenConfirm:
			m.confirm = newConfirmModelForSelection(m.selectedModules, m.selectedMode, platform.Detect())
			return m, m.confirm.Init()
		}
		return m, m.initScreen(msg.to)

	case selectedModulesMsg:
		m.selectedModules = msg.modules
		m.executionEnv = nil

	case archDevKitSelectedMsg:
		m.selectedModules = []modules.Module{msg.module}
		m.executionEnv = msg.env
		m.selectedMode = modeInstall
		m.screen = screenConfirm
		m.confirm = newConfirmModelForSelection(m.selectedModules, m.selectedMode, platform.Detect())
		return m, m.confirm.Init()

	case selectedModeMsg:
		m.selectedMode = msg.mode

	case userInfoMsg:
		m.userName = msg.name
		m.userEmail = msg.email
		m.webhookURL = msg.webhook

	case confirmMsg:
		if m.sudoCancel == nil && selectionNeedsSudoPrime(m.selectedModules, platform.Detect()) {
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
		}
		if m.sudoCancel != nil {
			m.sudoCancel()
			m.sudoCancel = nil
		}
		m.summary = newSummaryModel(m.executor.summaryResults)
		m.screen = screenSummary
		return m, m.summary.Init()
	}

	return m, cmd
}

func selectionNeedsSudoPrime(selected []modules.Module, target platform.Target) bool {
	return modules.SelectionNeedsPrivilege(selected, target)
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
	case screenArchDevKit:
		return m.archDevKit.View()
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
	case screenArchDevKit:
		return m.archDevKit.Init()
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

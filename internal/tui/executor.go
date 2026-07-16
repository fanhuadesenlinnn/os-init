package tui

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/execution"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
	"github.com/fanhuadesenlinnn/os-init/internal/state"
)

const maxOutputLines = 5

type executorModel struct {
	modules        []modules.Module
	scriptResults  []runner.Result
	summaryResults []runner.Result
	current        int
	output         []string // last N lines of current script
	spinner        spinner.Model
	progress       progress.Model
	done           bool
	canceling      bool

	// Execution context
	tmpDir        string
	operation     modules.Operation
	env           map[string]string
	webhookURL    string
	program       *tea.Program
	ctx           context.Context
	recorder      state.Recorder
	failedModules map[string]bool
}

func newExecutorModel(
	selected []modules.Module,
	tmpDir string,
	operation modules.Operation,
	env map[string]string,
	webhookURL string,
	ctx context.Context,
	recorder state.Recorder,
) executorModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(ColorAccent)

	p := progress.New(progress.WithDefaultGradient())

	runEnv := execution.BatchEnvironment(env, tmpDir, false)

	return executorModel{
		modules:        append([]modules.Module(nil), selected...),
		scriptResults:  make([]runner.Result, 0, len(selected)),
		summaryResults: make([]runner.Result, 0, len(selected)),
		spinner:        s,
		progress:       p,
		tmpDir:         tmpDir,
		operation:      operation,
		env:            runEnv,
		webhookURL:     webhookURL,
		ctx:            ctx,
		recorder:       recorder,
		failedModules:  make(map[string]bool),
	}
}

// Init uses a pointer receiver so the "no groups -> immediately done"
// shortcut actually mutates the embedded executorModel; with a value
// receiver the assignment to m.done was on a copy (staticcheck SA4005).
func (m *executorModel) Init() tea.Cmd {
	if len(m.modules) == 0 {
		m.done = true
		return func() tea.Msg { return allDoneMsg{} }
	}
	return tea.Batch(m.spinner.Tick, m.runCurrent())
}

func (m executorModel) Update(msg tea.Msg) (executorModel, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case progress.FrameMsg:
		model, cmd := m.progress.Update(msg)
		m.progress = model.(progress.Model)
		return m, cmd

	case scriptOutputMsg:
		line := localizedExecutionLine(msg.line)
		if len(m.output) > 0 && m.output[len(m.output)-1] == line {
			return m, nil
		}
		m.output = append(m.output, line)
		if len(m.output) > maxOutputLines {
			m.output = m.output[len(m.output)-maxOutputLines:]
		}
		return m, nil

	case scriptDoneMsg:
		mod := m.modules[m.current]
		if msg.result.ExitCode != 0 {
			m.failedModules[mod.ID] = true
		}
		m.scriptResults = append(m.scriptResults, msg.result)
		item := msg.result
		item.Module = moduleLabel(mod.ID, mod.Label)
		m.summaryResults = append(m.summaryResults, item)
		m.current++
		m.output = nil
		if m.ctx != nil && m.ctx.Err() != nil {
			m.done = true
			return m, func() tea.Msg { return allDoneMsg{} }
		}

		if m.current >= len(m.modules) {
			m.done = true
			return m, func() tea.Msg { return allDoneMsg{} }
		}
		return m, m.runCurrent()

	case tea.WindowSizeMsg:
		m.progress.Width = msg.Width - 10
		if m.progress.Width < 20 {
			m.progress.Width = 20
		}
		return m, nil
	}

	return m, nil
}

func (m executorModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render(text("  正在执行模块...", "  Running Modules...")) + "\n\n")
	if m.canceling {
		b.WriteString(ErrorStyle.Render(text("  正在取消，等待当前进程安全退出...", "  Canceling; waiting for the active process to exit safely...")) + "\n\n")
	}

	for i, mod := range m.modules {
		var icon string
		var labelStyle lipgloss.Style

		switch {
		case i < m.current:
			if m.scriptResults[i].ExitCode == 0 {
				icon = OKStyle.Render("  \u2713 ")
			} else {
				icon = ErrorStyle.Render("  \u2717 ")
			}
			labelStyle = lipgloss.NewStyle()
		case i == m.current:
			icon = "  " + m.spinner.View() + " "
			labelStyle = lipgloss.NewStyle().Bold(true)
		default:
			icon = MutedStyle.Render("  \u25CB ")
			labelStyle = MutedStyle
		}

		label := moduleLabel(mod.ID, mod.Label)

		b.WriteString(icon + labelStyle.Render(label) + "\n")

		// Show live output for current script
		if i == m.current && len(m.output) > 0 {
			for _, line := range m.output {
				truncated := line
				if len(truncated) > 80 {
					truncated = truncated[:77] + "..."
				}
				b.WriteString(MutedStyle.Render("    \u2502 "+truncated) + "\n")
			}
		}
	}

	// Progress bar
	total := len(m.modules)
	pct := 0.0
	if total > 0 {
		pct = float64(m.current) / float64(total)
	}
	b.WriteString("\n  " + m.progress.ViewAs(pct))
	b.WriteString(MutedStyle.Render(fmt.Sprintf("  %d/%d", m.current, total)))

	return b.String()
}

func (m executorModel) runCurrent() tea.Cmd {
	if m.current >= len(m.modules) {
		return nil
	}

	mod := m.modules[m.current]
	if dependency := execution.FailedDependency(mod, m.failedModules); dependency != "" {
		return func() tea.Msg {
			return scriptDoneMsg{result: runner.Result{
				Module:   mod.ID,
				ExitCode: 125,
				Output:   fmt.Sprintf(text("跳过：依赖模块 %s 执行失败\n", "Skipped: dependency %s failed\n"), dependency),
			}}
		}
	}
	tmpDir := m.tmpDir
	operation := m.operation
	env := m.env
	prog := m.program
	timeout := execution.TimeoutFromEnv(os.Getenv("OS_INIT_SCRIPT_TIMEOUT"))

	return func() tea.Msg {
		ctx := m.ctx
		if ctx == nil {
			ctx = context.Background()
		}

		step := execution.Run(ctx, execution.Request{
			TmpDir:    tmpDir,
			Module:    mod,
			Operation: operation,
			Env:       env,
			LogDir:    "logs",
			Timeout:   timeout,
			Verify:    true,
			Recorder:  m.recorder,
			OnLine: func(line string) {
				if prog != nil {
					prog.Send(scriptOutputMsg{
						module: mod.ID,
						line:   line,
					})
				}
			},
		})
		result := runner.Result{Module: mod.ID, ExitCode: step.ExitCode, Output: step.Output, Duration: step.Duration, LogFile: step.LogFile}
		if step.Error != "" && !outputEndsWithNote(result.Output, step.Error) {
			result.Output = appendResultNote(result.Output, step.Error)
			appendLogNote(result.LogFile, step.Error)
		}
		return scriptDoneMsg{result: result}
	}
}

func outputEndsWithNote(output, note string) bool {
	if strings.TrimSpace(output) == "" || strings.TrimSpace(note) == "" {
		return false
	}
	return execution.LastOutputLine(runner.StripANSI(output)) == strings.TrimSpace(runner.StripANSI(note))
}

func scriptTimeoutFromEnv() time.Duration {
	return execution.TimeoutFromEnv(os.Getenv("OS_INIT_SCRIPT_TIMEOUT"))
}

func appendResultNote(output, note string) string {
	if output == "" {
		return note + "\n"
	}
	if strings.HasSuffix(output, "\n") {
		return output + note + "\n"
	}
	return output + "\n" + note + "\n"
}

func appendLogNote(path, note string) {
	if path == "" {
		return
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = file.WriteString(note + "\n")
}

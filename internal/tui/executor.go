package tui

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

const maxOutputLines = 5
const defaultScriptTimeout = 45 * time.Minute

type executorModel struct {
	groups         []modules.ScriptGroup
	scriptResults  []runner.Result
	summaryResults []runner.Result
	current        int
	output         []string // last N lines of current script
	spinner        spinner.Model
	progress       progress.Model
	done           bool
	canceling      bool

	// Execution context
	tmpDir     string
	mode       string
	env        map[string]string
	webhookURL string
	program    *tea.Program
	ctx        context.Context
}

func newExecutorModel(
	selected []modules.Module,
	tmpDir string,
	modeFlag string,
	env map[string]string,
	webhookURL string,
	ctx context.Context,
) executorModel {
	groups := modules.GroupByScript(selected)

	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(ColorAccent)

	p := progress.New(progress.WithDefaultGradient())

	return executorModel{
		groups:         groups,
		scriptResults:  make([]runner.Result, 0, len(groups)),
		summaryResults: make([]runner.Result, 0, len(selected)),
		spinner:        s,
		progress:       p,
		tmpDir:         tmpDir,
		mode:           modeFlag,
		env:            env,
		webhookURL:     webhookURL,
		ctx:            ctx,
	}
}

// Init uses a pointer receiver so the "no groups -> immediately done"
// shortcut actually mutates the embedded executorModel; with a value
// receiver the assignment to m.done was on a copy (staticcheck SA4005).
func (m *executorModel) Init() tea.Cmd {
	if len(m.groups) == 0 {
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
		m.output = append(m.output, msg.line)
		if len(m.output) > maxOutputLines {
			m.output = m.output[len(m.output)-maxOutputLines:]
		}
		return m, nil

	case scriptDoneMsg:
		group := m.groups[m.current]
		m.scriptResults = append(m.scriptResults, msg.result)
		m.summaryResults = append(m.summaryResults, expandGroupResult(group, msg.result)...)
		m.current++
		m.output = nil
		if m.ctx != nil && m.ctx.Err() != nil {
			m.done = true
			return m, func() tea.Msg { return allDoneMsg{} }
		}

		if m.current >= len(m.groups) {
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

	for i, g := range m.groups {
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

		label := groupDisplayLabel(g)
		if len(g.Components) > 1 {
			label = label + " +" + fmt.Sprintf("%d", len(g.Components)-1)
		}

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
	total := len(m.groups)
	pct := 0.0
	if total > 0 {
		pct = float64(m.current) / float64(total)
	}
	b.WriteString("\n  " + m.progress.ViewAs(pct))
	b.WriteString(MutedStyle.Render(fmt.Sprintf("  %d/%d", m.current, total)))

	return b.String()
}

func (m executorModel) runCurrent() tea.Cmd {
	if m.current >= len(m.groups) {
		return nil
	}

	g := m.groups[m.current]
	tmpDir := m.tmpDir
	modeFlag := m.mode
	env := m.env
	sudo := g.NeedsSudo
	prog := m.program
	timeout := scriptTimeoutFromEnv()

	return func() tea.Msg {
		parent := m.ctx
		if parent == nil {
			parent = context.Background()
		}
		ctx := parent
		var cancel context.CancelFunc
		if timeout > 0 {
			ctx, cancel = context.WithTimeout(ctx, timeout)
			defer cancel()
		}

		result, err := runner.Run(ctx, runner.Params{
			TmpDir:     tmpDir,
			Script:     g.Script,
			Components: g.Components,
			Mode:       modeFlag,
			Env:        env,
			LogDir:     "logs",
			Sudo:       sudo,
			OnLine: func(line string) {
				if prog != nil {
					prog.Send(scriptOutputMsg{
						module: g.Script,
						line:   line,
					})
				}
			},
		})
		if parent.Err() == context.Canceled {
			note := text("用户已取消执行，当前模块进程组已终止。", "Execution canceled; the active module process group was terminated.")
			result.ExitCode = -1
			result.Output = appendResultNote(result.Output, note)
			appendLogNote(result.LogFile, note)
			return scriptDoneMsg{result: result}
		}
		if ctx.Err() == context.DeadlineExceeded {
			note := fmt.Sprintf(text("模块执行超过 %s，已终止。", "module exceeded %s and was stopped."), formatDuration(timeout))
			result.ExitCode = -1
			result.Output = appendResultNote(result.Output, note)
			appendLogNote(result.LogFile, note)
			if prog != nil {
				prog.Send(scriptOutputMsg{module: g.Script, line: note})
			}
			return scriptDoneMsg{result: result}
		}
		if err != nil {
			return scriptDoneMsg{result: runner.Result{
				Module:   g.Script,
				ExitCode: -1,
				Output:   err.Error(),
			}}
		}
		return scriptDoneMsg{result: result}
	}
}

func scriptTimeoutFromEnv() time.Duration {
	value := strings.TrimSpace(os.Getenv("OS_INIT_SCRIPT_TIMEOUT"))
	if value == "" {
		return defaultScriptTimeout
	}
	if value == "0" {
		return 0
	}
	if d, err := time.ParseDuration(value); err == nil && d >= 0 {
		return d
	}
	seconds, err := strconv.Atoi(value)
	if err == nil && seconds >= 0 {
		return time.Duration(seconds) * time.Second
	}
	return defaultScriptTimeout
}

func formatDuration(d time.Duration) string {
	if d%time.Second == 0 {
		return d.String()
	}
	return d.Round(time.Second).String()
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

func expandGroupResult(group modules.ScriptGroup, result runner.Result) []runner.Result {
	labels := group.ModuleLabels
	if len(labels) == 0 {
		labels = []string{group.Label}
	}

	results := make([]runner.Result, 0, len(labels))
	for idx, label := range labels {
		item := result
		if idx < len(group.ModuleIDs) {
			label = moduleLabel(group.ModuleIDs[idx], label)
		}
		item.Module = label
		results = append(results, item)
	}
	return results
}

func groupDisplayLabel(group modules.ScriptGroup) string {
	if len(group.ModuleIDs) > 0 {
		return moduleLabel(group.ModuleIDs[0], group.Label)
	}
	return group.Label
}

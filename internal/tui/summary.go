package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/runner"
)

type summaryModel struct {
	results  []runner.Result
	selected []modules.Module
}

func newSummaryModel(results []runner.Result, selected []modules.Module) summaryModel {
	return summaryModel{results: results, selected: selected}
}

func (m summaryModel) Init() tea.Cmd { return nil }

func (m summaryModel) Update(msg tea.Msg) (summaryModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "enter":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m summaryModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render(text("  执行结果", "  Results")) + "\n\n")

	succeeded := 0
	failed := 0

	for _, r := range m.results {
		var (
			icon   string
			status string
		)

		if r.ExitCode == 0 {
			icon = OKStyle.Render("  ✓")
			status = OKStyle.Render(text("成功", "succeeded"))
			succeeded++
		} else {
			icon = ErrorStyle.Render("  ✗")
			status = ErrorStyle.Render(fmt.Sprintf(text("退出码 %d", "exit code %d"), r.ExitCode))
			failed++
		}

		duration := MutedStyle.Render(fmt.Sprintf("(%s)", r.Duration.Round(100*1e6))) // round to 100ms
		module := r.Module

		line := fmt.Sprintf("%s %s  %s  %s", icon, module, status, duration)
		b.WriteString(line + "\n")

		if r.LogFile != "" {
			b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    日志: %s", "    log: %s"), r.LogFile)) + "\n")
		} else if r.ExitCode != 0 && strings.TrimSpace(r.Output) != "" {
			detail := strings.TrimSpace(strings.SplitN(r.Output, "\n", 2)[0])
			detail = localizedExecutionLine(detail)
			if len([]rune(detail)) > 120 {
				detail = string([]rune(detail)[:117]) + "..."
			}
			b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    原因: %s", "    reason: %s"), detail)) + "\n")
		}
	}

	// Summary line
	b.WriteString("\n")
	summary := fmt.Sprintf(text("  %d 个成功", "  %d succeeded"), succeeded)
	if failed > 0 {
		summary += fmt.Sprintf(text(", %d 个失败", ", %d failed"), failed)
	}
	if failed > 0 {
		b.WriteString(ErrorStyle.Render(summary))
	} else {
		b.WriteString(OKStyle.Render(summary))
	}

	nextSteps := m.nextSteps()
	if len(nextSteps) > 0 {
		b.WriteString("\n\n")
		b.WriteString(lipgloss.NewStyle().Bold(true).Foreground(ColorAccent2).Render(text("  后续动作", "  Next Steps")) + "\n")
		for _, step := range nextSteps {
			b.WriteString(MutedStyle.Render("  - "+step) + "\n")
		}
	}

	b.WriteString("\n\n" + renderHelpLine(
		helpAction{key: "Enter", desc: text("退出", "quit"), tone: helpPrimary},
		helpAction{key: "Q", desc: text("退出", "quit")},
	))

	return b.String()
}

func (m summaryModel) nextSteps() []string {
	success := map[string]bool{}
	for _, result := range m.results {
		if result.ExitCode == 0 {
			success[result.Module] = true
		}
	}

	var steps []string
	seen := map[string]bool{}
	add := func(step string) {
		step = strings.TrimSpace(step)
		if step == "" || seen[step] {
			return
		}
		seen[step] = true
		steps = append(steps, step)
	}

	shellRefresh := false
	relogin := false
	for _, mod := range m.selected {
		label := moduleLabel(mod.ID, mod.Label)
		if !success[label] {
			continue
		}
		if mod.NeedsRelogin || hasActivation(mod.Activates, modules.ActivationRelogin) {
			relogin = true
		}
		if hasActivation(mod.Activates, modules.ActivationZshrc) || hasActivation(mod.Activates, modules.ActivationShellProfile) {
			shellRefresh = true
		}
		for _, step := range mod.ManualSteps {
			add(fmt.Sprintf("%s: %s", label, manualStepText(step)))
		}
	}

	if shellRefresh {
		add(text("打开新终端或执行 exec zsh，让 shell 配置生效。", "Open a new terminal or run exec zsh so shell configuration takes effect."))
	}
	if relogin {
		add(text("重新登录一次，让用户组、默认 shell 或桌面会话变更生效。", "Log in again so group, default shell, or desktop session changes take effect."))
	}
	return steps
}

func hasActivation(values []string, activation string) bool {
	for _, value := range values {
		if value == activation {
			return true
		}
	}
	return false
}

func manualStepText(step string) string {
	if !langIsEnglish() {
		return step
	}
	switch step {
	case "打开 OrbStack 完成首次初始化":
		return "open OrbStack to finish first-time initialization"
	case "打开应用后导入自己的代理配置，不由 os-init 接管订阅和系统代理":
		return "open the app and import your own proxy profile; os-init does not manage subscriptions or system proxy settings"
	case "打开 Royal TSX 后导入或创建自己的连接配置":
		return "open Royal TSX and import or create your connection configuration"
	case "打开 Seafile Client 后登录账号并选择同步目录":
		return "open Seafile Client, sign in, and choose sync directories"
	case "打开 Bitwarden 后登录账号或导入自己的密码库":
		return "open Bitwarden and sign in or import your vault"
	case "替换订阅或提供 MIHOMO_CONFIG_SOURCE 后再启用服务":
		return "replace the subscription or set MIHOMO_CONFIG_SOURCE before enabling the service"
	case "ArchDevKit 保留独立配置和状态：~/.config/archdevkit/config.env、~/.local/state/archdevkit":
		return "ArchDevKit keeps independent config and state at ~/.config/archdevkit/config.env and ~/.local/state/archdevkit"
	case "桌面模块会写入 Hyprland、Waybar、Rofi、Dunst、Yazi、GTK 等用户配置":
		return "the desktop module writes Hyprland, Waybar, Rofi, Dunst, Yazi, GTK, and related user config"
	case "Motrix Next 未签名；如 macOS 拒绝打开，请先核对上游说明再决定是否移除隔离属性":
		return "Motrix Next is unsigned; if macOS blocks it, review the upstream guidance before deciding whether to remove quarantine attributes"
	case "SSH 会自动使用 simple 提示符，TTY 会自动使用 plain 提示符":
		return "SSH automatically uses the simple prompt, and TTY sessions automatically use the plain prompt"
	default:
		return step
	}
}

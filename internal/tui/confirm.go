package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/planner"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

type confirmModel struct {
	count             int
	mode              mode
	err               string
	privilegeNeeds    []modules.PrivilegeNeed
	addedDependencies []planner.DependencyAddition
	softAssociations  []planner.SoftAssociation
	executionOrder    []modules.Module
	affectedPaths     []string
	destructivePaths  []string
}

func newConfirmModel(count int, m mode) confirmModel {
	return confirmModel{count: count, mode: m}
}

func newConfirmModelForSelection(selected []modules.Module, m mode, target platform.Target) confirmModel {
	return newConfirmModelForPlan(planner.Plan{Modules: selected}, m, target)
}

func newConfirmModelForPlan(plan planner.Plan, m mode, target platform.Target) confirmModel {
	return confirmModel{
		count:             len(plan.Modules),
		mode:              m,
		privilegeNeeds:    modules.PrivilegeNeeds(plan.Modules, target),
		addedDependencies: plan.AddedDependencies,
		softAssociations:  plan.SoftAssociations,
		executionOrder:    plan.Modules,
		affectedPaths:     collectModulePaths(plan.Modules, false),
		destructivePaths:  collectModulePaths(plan.Modules, true),
	}
}

func (m confirmModel) Init() tea.Cmd { return nil }

func (m confirmModel) Update(msg tea.Msg) (confirmModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "y", "Y", "enter":
			return m, func() tea.Msg { return confirmMsg{confirmed: true} }
		case "n", "N", "esc":
			return m, func() tea.Msg { return switchScreenMsg{to: screenMenu} }
		}
	}
	return m, nil
}

func (m confirmModel) View() string {
	var b strings.Builder

	titleStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	b.WriteString(titleStyle.Render(text("  确认执行", "  Review Changes")) + "\n\n")

	warnStyle := lipgloss.NewStyle().Bold(true).Foreground(ColorWarn)
	msg := fmt.Sprintf("  将以%s模式执行 %d 个模块，是否继续？", m.mode.String(), m.count)
	if langIsEnglish() {
		moduleWord := "modules"
		if m.count == 1 {
			moduleWord = "module"
		}
		msg = fmt.Sprintf("  Run %d %s in %s mode?", m.count, moduleWord, m.mode.String())
	}
	b.WriteString(warnStyle.Render(msg) + "\n\n")

	if len(m.privilegeNeeds) > 0 {
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  需要 sudo 的模块: %d 个", "  Modules needing sudo: %d"), len(m.privilegeNeeds))) + "\n")
		for i, need := range m.privilegeNeeds {
			if i >= 3 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个模块需要系统权限", "    %d more modules need system privileges"), len(m.privilegeNeeds)-i)) + "\n")
				break
			}
			b.WriteString(MutedStyle.Render(fmt.Sprintf("    - %s: %s", moduleLabel(need.ModuleID, need.Label), modulePrivilegeReason(need.ModuleID, need.Reason))) + "\n")
		}
		b.WriteString("\n")
	}

	if len(m.addedDependencies) > 0 {
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  自动补齐依赖: %d 个", "  Auto-added dependencies: %d"), len(m.addedDependencies))) + "\n")
		for i, dep := range m.addedDependencies {
			if i >= 3 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个自动补齐依赖", "    %d more auto-added dependencies"), len(m.addedDependencies)-i)) + "\n")
				break
			}
			label := moduleLabel(dep.ModuleID, dep.Label)
			requiredBy := moduleLabel(dep.RequiredByID, dep.RequiredByLabel)
			b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    - %s：由 %s 需要", "    - %s: required by %s"), label, requiredBy)) + "\n")
		}
		b.WriteString("\n")
	}

	if len(m.softAssociations) > 0 {
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  相关建议: %d 个", "  Related suggestions: %d"), len(m.softAssociations))) + "\n")
		for i, assoc := range m.softAssociations {
			if i >= 3 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个相关建议", "    %d more related suggestions"), len(m.softAssociations)-i)) + "\n")
				break
			}
			label := moduleLabel(assoc.SuggestedID, assoc.SuggestedLabel)
			reason := text(assoc.ReasonZH, assoc.ReasonEN)
			b.WriteString(MutedStyle.Render(fmt.Sprintf("    - %s: %s", label, reason)) + "\n")
		}
		b.WriteString("\n")
	}

	if len(m.executionOrder) > 1 {
		b.WriteString(MutedStyle.Render(text("  执行顺序预览:", "  Execution order preview:")) + "\n")
		for i, mod := range m.executionOrder {
			if i >= 5 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个模块", "    %d more modules"), len(m.executionOrder)-i)) + "\n")
				break
			}
			b.WriteString(MutedStyle.Render(fmt.Sprintf("    %d. %s", i+1, moduleLabel(mod.ID, mod.Label))) + "\n")
		}
		b.WriteString("\n")
	}

	if len(m.affectedPaths) > 0 {
		b.WriteString(MutedStyle.Render(text("  重要影响路径:", "  Important affected paths:")) + "\n")
		for i, path := range m.affectedPaths {
			if i >= 5 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个路径", "    %d more paths"), len(m.affectedPaths)-i)) + "\n")
				break
			}
			b.WriteString(MutedStyle.Render("    - "+localizedMetadata(path)) + "\n")
		}
		b.WriteString("\n")
	}

	if m.mode == modeUninstall && len(m.destructivePaths) > 0 {
		b.WriteString(ErrorStyle.Render(text("  显式清理开关可能删除:", "  Explicit purge flags may delete:")) + "\n")
		for i, path := range m.destructivePaths {
			if i >= 3 {
				b.WriteString(MutedStyle.Render(fmt.Sprintf(text("    另有 %d 个路径", "    %d more paths"), len(m.destructivePaths)-i)) + "\n")
				break
			}
			b.WriteString(MutedStyle.Render("    - "+localizedMetadata(path)) + "\n")
		}
		b.WriteString("\n")
	}

	if m.err != "" {
		b.WriteString(ErrorStyle.Render("  "+m.err) + "\n\n")
	}

	confirmTone := helpPrimary
	confirmText := text("确认执行", "confirm")
	if m.mode == modeUninstall {
		confirmTone = helpWarn
		confirmText = text("确认卸载", "confirm uninstall")
	}
	b.WriteString(renderHelpLine(
		helpAction{key: "Y", desc: confirmText, tone: confirmTone},
		helpAction{key: "Enter", desc: confirmText, tone: confirmTone},
		helpAction{key: "N", desc: text("取消", "cancel")},
		helpAction{key: "Esc", desc: text("返回", "back")},
	))

	return b.String()
}

func collectModulePaths(selected []modules.Module, destructive bool) []string {
	seen := map[string]bool{}
	var paths []string
	for _, mod := range selected {
		values := mod.AffectedPaths
		if destructive {
			values = mod.DestructivePaths
		}
		for _, path := range values {
			path = strings.TrimSpace(path)
			if path == "" || seen[path] {
				continue
			}
			seen[path] = true
			paths = append(paths, path)
		}
	}
	return paths
}

package tui

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"golang.org/x/term"
)

type menuItem struct {
	module    modules.Module
	separator bool
	label     string
	Status    string
}

type menuModel struct {
	items     []menuItem
	allMods   []modules.Module
	cursor    int
	selected  map[int]bool
	width     int
	height    int
	offset    int
	checksRan bool
	spinner   spinner.Model
	filtering bool
	filter    string
	visible   []int // indices of visible items when filtering
	notice    string
}

func newMenuModel(mods []modules.Module) menuModel {
	var items []menuItem

	items = append(items, menuItem{separator: true, label: "系统优化"})
	for _, m := range mods {
		if m.Category == "optimization" {
			items = append(items, menuItem{module: m})
		}
	}

	items = append(items, menuItem{separator: true, label: ""}) // spacer
	items = append(items, menuItem{separator: true, label: "软件安装"})
	for _, sub := range modules.InstallSubsections() {
		hasItems := false
		for _, m := range mods {
			if m.Category == "installation" && m.Subsection == sub {
				hasItems = true
				break
			}
		}
		if !hasItems {
			continue
		}
		items = append(items, menuItem{separator: true, label: "  " + sub})
		for _, m := range mods {
			if m.Category == "installation" && m.Subsection == sub {
				items = append(items, menuItem{module: m})
			}
		}
	}

	cursor := 0
	for i, item := range items {
		if !item.separator {
			cursor = i
			break
		}
	}

	// Sync installed check uses local files and commands only; network update
	// checks still run asynchronously after the menu is visible.
	checker := defaultInstallStatusChecker()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	for i := range items {
		if items[i].separator {
			continue
		}
		mod := items[i].module
		if checker.moduleInstalled(ctx, mod) {
			items[i].Status = statusInstalled()
		}
	}

	s := spinner.New()
	s.Spinner = spinner.MiniDot
	s.Style = lipgloss.NewStyle().Foreground(ColorAccent2)

	return menuModel{
		items:    items,
		allMods:  mods,
		cursor:   cursor,
		selected: make(map[int]bool),
		height:   detectTermHeight(),
		spinner:  s,
	}
}

func (m menuModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, runUpdateChecks(m.allMods))
}

func (m menuModel) Update(msg tea.Msg) (menuModel, tea.Cmd) {
	switch msg := msg.(type) {
	case spinner.TickMsg:
		if !m.checksRan {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}

	case updateCheckDoneMsg:
		m.checksRan = true
		for _, r := range msg.results {
			if r.status == "" {
				continue
			}
			for i := range m.items {
				if !m.items[i].separator && m.items[i].module.ID == r.moduleID {
					current := m.items[i].Status
					// Only upgrade: update > installed+ver > installed > empty
					if isUpdateStatus(r.status) {
						m.items[i].Status = r.status
					} else if strings.Contains(r.status, " ") && !strings.Contains(current, " ") {
						// New has version, current doesn't
						m.items[i].Status = r.status
					} else if current == "" {
						m.items[i].Status = r.status
					}
				}
			}
		}
		return m, nil

	case tea.WindowSizeMsg:
		m.width = msg.Width
		// header=3 + help=1 + spacing=1 + footer=2 + sticky=1 + buffer=2 = 10
		m.height = msg.Height - 10
		if m.height < 10 {
			m.height = 10
		}
		m.fixScroll()

	case tea.KeyMsg:
		m.notice = ""
		// Filter mode input
		if m.filtering {
			switch msg.String() {
			case "esc":
				m.filtering = false
				m.filter = ""
				m.visible = nil
				m.fixScroll()
				return m, nil
			case "backspace":
				if runes := []rune(m.filter); len(runes) > 0 {
					m.filter = string(runes[:len(runes)-1])
					m.applyFilter()
				}
				return m, nil
			case "enter":
				m.filtering = false
				return m, nil
			default:
				if msg.Type == tea.KeyRunes && len(msg.Runes) > 0 {
					m.filter += string(msg.Runes)
					m.applyFilter()
				}
				return m, nil
			}
		}

		switch msg.String() {
		case "up", "k":
			m.cursor = m.prevSelectable(m.cursor)
			m.fixScroll()
		case "down", "j":
			m.cursor = m.nextSelectable(m.cursor)
			m.fixScroll()
		case " ":
			if m.isVisibleSelectable(m.cursor) {
				if m.selected[m.cursor] {
					delete(m.selected, m.cursor)
				} else {
					m.selected[m.cursor] = true
				}
			}
		case "ctrl+a":
			indices := m.selectableIndices()
			allSelected := len(indices) > 0
			for _, i := range indices {
				if !m.selected[i] {
					allSelected = false
					break
				}
			}
			if allSelected {
				for _, i := range indices {
					delete(m.selected, i)
				}
			} else {
				for _, i := range indices {
					m.selected[i] = true
				}
			}
		case "/":
			m.filtering = true
			m.filter = ""
			return m, nil
		case "enter":
			selected := m.getSelected()
			if len(selected) == 0 {
				return m, nil
			}
			return m, func() tea.Msg { return selectedModulesMsg{modules: selected} }
		case "q", "esc":
			if m.filter != "" {
				m.filter = ""
				m.visible = nil
				return m, nil
			}
			return m, tea.Quit
		}
	}

	return m, nil
}

func detectTermHeight() int {
	_, h, err := term.GetSize(int(os.Stdout.Fd()))
	if err != nil || h <= 0 {
		h = 30
	}
	usable := h - 10
	if usable < 10 {
		usable = 10
	}
	return usable
}

func (m *menuModel) applyFilter() {
	if m.filter == "" {
		m.visible = nil
		return
	}
	lower := strings.ToLower(m.filter)
	m.visible = nil
	for i, item := range m.items {
		if item.separator {
			continue
		}
		if strings.Contains(strings.ToLower(item.module.Label), lower) ||
			strings.Contains(strings.ToLower(item.module.Description), lower) {
			m.visible = append(m.visible, i)
		}
	}
	// Move cursor to first visible item
	if len(m.visible) > 0 {
		m.cursor = m.visible[0]
	}
	m.offset = 0
}

func (m *menuModel) fixScroll() {
	cursorLine := m.cursor
	if m.filter != "" {
		cursorLine = 0
		found := false
		for pos, idx := range m.visible {
			if idx == m.cursor {
				cursorLine = pos
				found = true
				break
			}
		}
		if !found {
			m.offset = 0
			return
		}
	}
	// Scroll by 1 to keep cursor visible
	for cursorLine < m.offset {
		m.offset--
	}
	for cursorLine >= m.offset+m.height {
		m.offset++
	}

	// Clamp
	if m.offset < 0 {
		m.offset = 0
	}
	lineCount := len(m.items)
	if m.filter != "" {
		lineCount = len(m.visible)
	}
	max := lineCount - m.height
	if max < 0 {
		max = 0
	}
	if m.offset > max {
		m.offset = max
	}
}

func (m menuModel) selectableIndices() []int {
	if m.filter != "" {
		return append([]int(nil), m.visible...)
	}
	indices := make([]int, 0, m.selectableCount())
	for i, item := range m.items {
		if !item.separator {
			indices = append(indices, i)
		}
	}
	return indices
}

func (m menuModel) isVisibleSelectable(index int) bool {
	for _, candidate := range m.selectableIndices() {
		if candidate == index {
			return true
		}
	}
	return false
}

func (m menuModel) selectableCount() int {
	n := 0
	for _, item := range m.items {
		if !item.separator {
			n++
		}
	}
	return n
}

var (
	updateAvailableStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("231"))
	installedStyle       = MutedStyle
	sectionStyle         = lipgloss.NewStyle().Bold(true).Foreground(ColorAccent)
	subsectionStyle      = lipgloss.NewStyle().Foreground(ColorAccent2)
)

func (m menuModel) View() string {
	var b strings.Builder
	w := m.width
	if w <= 0 {
		w = 80
	}

	// ── Header ──────────────────────────────────────────────────
	titleText := HeaderTitleStyle.Render("OS Init")
	byText := HeaderByLineStyle.Render(text(" 中国大陆优化", " Mainland China optimized"))
	headerLeft := lipgloss.JoinHorizontal(lipgloss.Center, titleText, byText)

	// spinner moved to footer

	header := HeaderBorderStyle.Width(w - 4).Render(headerLeft)
	b.WriteString(header + "\n")

	// ── Help bar ────────────────────────────────────────────────
	helpParts := []helpAction{
		{key: "↑/↓", desc: text("移动", "move")},
		{key: "Space", desc: text("选择", "select"), tone: helpPrimary},
		{key: "Ctrl+A", desc: text("全选", "select all")},
		{key: "/", desc: text("过滤", "filter")},
		{key: "Enter", desc: text("确认", "confirm"), tone: helpPrimary},
		{key: "Q", desc: text("退出", "quit")},
	}
	b.WriteString(renderHelpLine(helpParts...) + "\n")

	// ── Filter bar ──────────────────────────────────────────────
	if m.filtering {
		b.WriteString(
			lipgloss.NewStyle().Foreground(ColorAccent2).Render(" / "+m.filter+"█") + "\n",
		)
	} else if m.filter != "" {
		b.WriteString(
			lipgloss.NewStyle().Foreground(ColorAccent2).Render(text(" 过滤: ", " Filter: ")+m.filter) +
				MutedStyle.Render(text(" (esc 清空)", " (esc clear)")) + "\n",
		)
	}
	if m.notice != "" {
		b.WriteString("  " + lipgloss.NewStyle().Foreground(ColorWarn).Render(m.notice) + "\n")
	}

	b.WriteString("\n")
	// ── List ────────────────────────────────────────────────────
	var lines []string
	if m.filter != "" {
		if len(m.visible) == 0 {
			lines = append(lines, MutedStyle.Render(text("  没有匹配的模块", "  No matching modules")))
		} else {
			for _, idx := range m.visible {
				lines = append(lines, m.renderItem(idx, m.items[idx]))
			}
		}
	} else {
		for i, item := range m.items {
			lines = append(lines, m.renderItem(i, item))
		}
	}

	// Apply scroll window — always render exactly m.height lines to prevent flicker
	start := m.offset
	if start > len(lines) {
		start = len(lines)
	}
	end := start + m.height
	if end > len(lines) {
		end = len(lines)
	}

	// Sticky section header — only show when the original separator is above the viewport
	if m.filter == "" && start > 0 {
		sectionIdx := -1
		currentSection := ""
		for idx := start - 1; idx >= 0; idx-- {
			if m.items[idx].separator && m.items[idx].label != "" && !strings.HasPrefix(m.items[idx].label, "  ") {
				sectionIdx = idx
				currentSection = m.items[idx].label
				break
			}
		}
		// Only show sticky if the separator is ABOVE the viewport (not visible)
		if sectionIdx >= 0 && sectionIdx < start {
			b.WriteString(sectionStyle.Render(fmt.Sprintf("  ── %s ──", moduleSection(currentSection))) + "\n")
		}
	}

	rendered := 0
	for _, line := range lines[start:end] {
		b.WriteString(line + "\n")
		rendered++
	}

	// Show scroll indicator or pad
	if end < len(lines) {
		remaining := m.remainingModuleCount(end)
		b.WriteString(MutedStyle.Render(fmt.Sprintf(text("  ▼ 还有 %d 个模块", "  ▼ %d more modules"), remaining)) + "\n")
		rendered++
	}

	// Pad remaining lines to keep total height constant
	for rendered < m.height+1 {
		b.WriteString("\n")
		rendered++
	}

	// ── Footer status bar ───────────────────────────────────────
	count := len(m.selected)
	total := m.selectableCount()
	leftText := FooterCountStyle.Render(fmt.Sprintf(text(" 已选 %d / %d", " Selected %d / %d"), count, total))

	updates := 0
	for _, item := range m.items {
		if isUpdateStatus(item.Status) {
			updates++
		}
	}

	rightText := ""
	if !m.checksRan {
		rightText = m.spinner.View() + HeaderSpinnerLabel.Render(text(" 正在检查更新 ", " Checking updates "))
	} else if updates > 0 {
		rightText = FooterUpdateStyle.Render(
			fmt.Sprintf(text("%d 项可更新 ", "%d updates available "), updates),
		)
	}

	// Pad the bar to fill the full terminal width
	// FooterBarStyle has Padding(0,1) = 2 chars total
	leftWidth := lipgloss.Width(leftText)
	rightWidth := lipgloss.Width(rightText)
	gap := w - leftWidth - rightWidth - 2
	if gap < 0 {
		gap = 0
	}

	footerBar := FooterBarStyle.Width(w).Render(
		leftText + strings.Repeat(" ", gap) + rightText,
	)
	b.WriteString("\n" + footerBar)

	return b.String()
}

func (m menuModel) renderItem(i int, item menuItem) string {
	if item.separator {
		label := item.label
		if label == "" {
			return "" // spacer
		}
		if !strings.HasPrefix(label, "  ") {
			return sectionStyle.Render(fmt.Sprintf("  ── %s ──", moduleSection(label)))
		}
		return subsectionStyle.Render(fmt.Sprintf("    %s", moduleSection(label)))
	}

	cursor := "  "
	if i == m.cursor {
		cursor = lipgloss.NewStyle().Foreground(ColorAccent).Render("▸ ")
	}

	checkbox := "[ ]"
	if m.selected[i] {
		checkbox = lipgloss.NewStyle().Foreground(ColorOK).Render("[✓]")
	}

	label := moduleLabel(item.module.ID, item.module.Label)
	if i == m.cursor {
		label = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Render(label)
	}

	line := fmt.Sprintf("%s%s %s", cursor, checkbox, label)

	if item.module.Description != "" {
		line += MutedStyle.Render(" — " + moduleDescription(item.module.ID, item.module.Description))
	}

	if item.Status != "" {
		switch {
		case isUpdateStatus(item.Status):
			line += " " + updateAvailableStyle.Render(item.Status)
		case isInstalledStatus(item.Status):
			line += " " + installedStyle.Render(item.Status)
		default:
			line += " " + MutedStyle.Render(item.Status)
		}
	}

	return line
}

func (m menuModel) prevSelectable(from int) int {
	indices := m.selectableIndices()
	if len(indices) == 0 {
		return from
	}
	for pos, idx := range indices {
		if idx == from {
			return indices[(pos-1+len(indices))%len(indices)]
		}
	}
	return indices[len(indices)-1]
}

func (m menuModel) nextSelectable(from int) int {
	indices := m.selectableIndices()
	if len(indices) == 0 {
		return from
	}
	for pos, idx := range indices {
		if idx == from {
			return indices[(pos+1)%len(indices)]
		}
	}
	return indices[0]
}

func (m menuModel) remainingModuleCount(end int) int {
	if m.filter != "" {
		if end >= len(m.visible) {
			return 0
		}
		return len(m.visible) - end
	}
	remaining := 0
	for i := end; i < len(m.items); i++ {
		if !m.items[i].separator {
			remaining++
		}
	}
	return remaining
}

func (m menuModel) getSelected() []modules.Module {
	var result []modules.Module
	for i, item := range m.items {
		if m.selected[i] && !item.separator {
			result = append(result, item.module)
		}
	}
	return result
}

func selectedHasModule(selected []modules.Module, id string) bool {
	for _, m := range selected {
		if m.ID == id {
			return true
		}
	}
	return false
}

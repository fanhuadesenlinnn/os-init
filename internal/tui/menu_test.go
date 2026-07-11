package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func testMenu() menuModel {
	return menuModel{
		items: []menuItem{
			{separator: true, label: "Group"},
			{module: modules.Module{ID: "alpha", Label: "Alpha", Description: "first"}},
			{module: modules.Module{ID: "docker", Label: "Docker", Description: "containers"}},
			{module: modules.Module{ID: "terminal", Label: "终端样式", Description: "终端体验"}},
		},
		cursor:   1,
		selected: map[int]bool{},
		height:   10,
	}
}

func TestMenuFirstSpaceSelectsCurrentItem(t *testing.T) {
	m, _ := testMenu().Update(tea.KeyMsg{Type: tea.KeySpace})
	if !m.selected[1] {
		t.Fatal("first Space should select the visible current item")
	}
}

func TestMenuFilterAcceptsUnicodeAndPaste(t *testing.T) {
	m := testMenu()
	m.filtering = true

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("终端")})
	if m.filter != "终端" || len(m.visible) != 1 || m.visible[0] != 3 {
		t.Fatalf("unicode filter = %q visible=%v", m.filter, m.visible)
	}

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyBackspace})
	if m.filter != "终" {
		t.Fatalf("backspace should remove one rune, got %q", m.filter)
	}

	m.filter = ""
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("docker")})
	if m.filter != "docker" || len(m.visible) != 1 || m.visible[0] != 2 {
		t.Fatalf("pasted filter = %q visible=%v", m.filter, m.visible)
	}
}

func TestMenuFilteredNavigationAndSelectionStayVisible(t *testing.T) {
	m := testMenu()
	m.filter = "docker"
	m.applyFilter()
	if m.cursor != 2 {
		t.Fatalf("cursor = %d, want Docker index", m.cursor)
	}

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyDown})
	if m.cursor != 2 {
		t.Fatalf("filtered navigation moved to hidden index %d", m.cursor)
	}

	m, _ = m.Update(tea.KeyMsg{Type: tea.KeySpace})
	if len(m.selected) != 1 || !m.selected[2] {
		t.Fatalf("filtered selection should select Docker only: %v", m.selected)
	}
}

func TestMenuFilteredSelectAllDoesNotSelectHiddenItems(t *testing.T) {
	m := testMenu()
	m.filter = "docker"
	m.applyFilter()
	m, _ = m.Update(tea.KeyMsg{Type: tea.KeyCtrlA})
	if len(m.selected) != 1 || !m.selected[2] {
		t.Fatalf("filtered Ctrl+A selected hidden items: %v", m.selected)
	}
}

func TestMenuNoFilterMatchesShowsNoModules(t *testing.T) {
	m := testMenu()
	m.width = 80
	m.filter = "does-not-exist"
	m.applyFilter()
	view := m.View()
	if strings.Contains(view, "Alpha") || strings.Contains(view, "Docker") || strings.Contains(view, "终端样式") {
		t.Fatalf("no-match filter rendered hidden modules: %s", view)
	}
}

func TestInstalledStatusDoesNotLookSelected(t *testing.T) {
	m := testMenu()
	m.items[1].Status = statusInstalled()
	line := m.renderItem(1, m.items[1])
	if !strings.Contains(line, "[ ]") || strings.Contains(line, "[✓]") {
		t.Fatalf("installed but unselected item should have an empty checkbox: %q", line)
	}
}

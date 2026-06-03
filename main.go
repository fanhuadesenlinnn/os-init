package main

import (
	"embed"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/sudo"
	"github.com/fanhuadesenlinnn/os-init/internal/tui"
)

//go:embed all:modules
var assets embed.FS

var (
	version = "dev"
	commit  = "none"
)

func main() {
	sudoCancel := sudo.Prime()

	m := tui.New(tui.Config{
		Assets:     assets,
		Version:    version,
		Commit:     commit,
		SudoCancel: sudoCancel,
	})

	p := tea.NewProgram(m, tea.WithAltScreen())
	tui.SetProgram(p)

	// Handle SIGTERM for tmpdir cleanup
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM)
	go func() {
		<-sigCh
		tui.RunCleanup()
		os.Exit(1)
	}()

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, text("错误: %v\n", "Error: %v\n"), err)
		tui.RunCleanup()
		os.Exit(1)
	}
}

func text(zh, en string) string {
	if strings.HasPrefix(strings.ToLower(os.Getenv("OS_INIT_LANG")), "en") {
		return en
	}
	return zh
}

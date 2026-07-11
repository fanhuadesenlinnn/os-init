package main

import (
	"embed"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/tui"
)

//go:embed all:modules
var assets embed.FS

var (
	version = "dev"
	commit  = "none"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, text("错误: %v\n", "Error: %v\n"), err)
		tui.RunCleanup()
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) > 0 {
		switch args[0] {
		case "-h", "--help", "help":
			fmt.Print(usageText())
			return nil
		case "-v", "--version", "version":
			fmt.Printf("os-init %s (%s)\n", version, commit)
			return nil
		default:
			return fmt.Errorf("%s\n\n%s", text("未知参数: ", "unknown argument: ")+args[0], usageText())
		}
	}

	m := tui.New(tui.Config{
		Assets:  assets,
		Version: version,
		Commit:  commit,
	})

	p := tea.NewProgram(m, tea.WithAltScreen())
	tui.SetProgram(p)

	// Handle SIGTERM for tmpdir cleanup
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM)
	go func() {
		<-sigCh
		// Route termination through the model so an active installer context is
		// canceled and its process group exits before temporary files are removed.
		p.Send(tea.KeyMsg{Type: tea.KeyCtrlC})
	}()

	if _, err := p.Run(); err != nil {
		return err
	}
	return nil
}

func usageText() string {
	return text(`用法:
  os-init
  os-init --version
  os-init --help
`, `Usage:
  os-init
  os-init --version
  os-init --help
`)
}

func text(zh, en string) string {
	if strings.HasPrefix(strings.ToLower(os.Getenv("OS_INIT_LANG")), "en") {
		return en
	}
	return zh
}

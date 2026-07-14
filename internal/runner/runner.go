package runner

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

var ansiRe = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

const (
	maxScannerTokenBytes   = 1024 * 1024
	maxCapturedOutputBytes = 1024 * 1024
)

// StripANSI removes ANSI escape codes from a string.
func StripANSI(s string) string {
	return ansiRe.ReplaceAllString(s, "")
}

// Result holds the outcome of a script execution.
type Result struct {
	Module   string
	ExitCode int
	Output   string
	Duration time.Duration
	LogFile  string
}

// Params configures a single script run.
type Params struct {
	TmpDir     string
	Script     string            // relative to modules/, e.g. "shell/install.sh"
	Components []string          // sub-components to pass as args
	Operation  string            // stable provider operation: install, update, uninstall
	Env        map[string]string // extra env vars
	OnLine     func(string)      // called per line (ANSI-stripped), may be nil
	LogDir     string            // if set, writes log file here
	Sudo       bool              // run with sudo bash
}

// Run executes a shell script and captures its output.
func Run(ctx context.Context, p Params) (Result, error) {
	providerPath := filepath.Join(p.TmpDir, "modules", "provider.sh")
	operation := p.Operation
	if operation == "" {
		operation = "install"
	}
	args := []string{}
	if p.Sudo {
		args = append(args, "bash", providerPath)
	} else {
		args = append(args, providerPath)
	}
	args = append(args, "execute", "--script", p.Script, "--operation", operation)
	for _, component := range p.Components {
		args = append(args, "--component", component)
	}

	var cmd *exec.Cmd
	if p.Sudo {
		cmd = exec.CommandContext(ctx, "sudo", args...)
	} else {
		cmd = exec.CommandContext(ctx, "bash", args...)
	}

	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	// Kill the entire process group on context cancellation so child
	// processes (e.g. sleep) don't keep pipes open and block Wait.
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}
	cmd.WaitDelay = 3 * time.Second

	// Environment
	cmd.Env = os.Environ()
	for k, v := range p.Env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}

	// Pipe stdout+stderr combined
	pr, pw := io.Pipe()
	cmd.Stdout = pw
	cmd.Stderr = pw

	// Log file setup
	var logFile *os.File
	var logPath string
	if p.LogDir != "" {
		if err := os.MkdirAll(p.LogDir, 0o700); err != nil {
			return Result{}, fmt.Errorf("create log dir: %w", err)
		}
		name := strings.ReplaceAll(p.Script, "/", "-")
		name = strings.TrimSuffix(name, ".sh")
		if len(p.Components) > 0 {
			name += "-" + strings.Join(p.Components, "-")
		}
		logPath = filepath.Join(
			p.LogDir,
			fmt.Sprintf("%s-%s.log", name, time.Now().Format("20060102-150405.000000000")),
		)
		var err error
		logFile, err = os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
		if err != nil {
			return Result{}, fmt.Errorf("create log file: %w", err)
		}
		defer logFile.Close()
	}

	start := time.Now()
	if err := cmd.Start(); err != nil {
		pw.Close()
		return Result{}, fmt.Errorf("start script: %w", err)
	}

	// Read output line by line
	var output strings.Builder
	capturedBytes := 0
	outputTruncated := false
	appendOutput := func(value string) {
		if outputTruncated {
			return
		}
		remaining := maxCapturedOutputBytes - capturedBytes
		if remaining <= 0 {
			output.WriteString("[os-init] captured output truncated; see the log file for full output\n")
			outputTruncated = true
			return
		}
		if len(value) > remaining {
			output.WriteString(value[:remaining])
			output.WriteString("\n[os-init] captured output truncated; see the log file for full output\n")
			capturedBytes += remaining
			outputTruncated = true
			return
		}
		output.WriteString(value)
		capturedBytes += len(value)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		scanner := bufio.NewScanner(pr)
		scanner.Buffer(make([]byte, 64*1024), maxScannerTokenBytes)
		for scanner.Scan() {
			raw := scanner.Text()
			appendOutput(raw + "\n")
			clean := StripANSI(raw)

			if logFile != nil {
				logFile.WriteString(clean + "\n")
			}
			if p.OnLine != nil {
				p.OnLine(clean)
			}
		}
		if err := scanner.Err(); err != nil {
			note := fmt.Sprintf("[os-init] output reader error: %v", err)
			appendOutput(note + "\n")
			if logFile != nil {
				_, _ = logFile.WriteString(note + "\n")
			}
			if p.OnLine != nil {
				p.OnLine(note)
			}
			// Continue draining the pipe so an oversized line cannot block the
			// installer process while it is trying to write more output.
			_, _ = io.Copy(io.Discard, pr)
		}
	}()

	waitErr := cmd.Wait()
	pw.Close()
	<-done

	exitCode := 0
	if waitErr != nil {
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
		}
	}

	return Result{
		Module:   p.Script,
		ExitCode: exitCode,
		Output:   output.String(),
		Duration: time.Since(start),
		LogFile:  logPath,
	}, nil
}

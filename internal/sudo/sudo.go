// Package sudo primes the sudo credential cache once at startup and
// refreshes it in the background so privileged module scripts do not
// interrupt the TUI with a mid-run password prompt.
package sudo

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Prime prompts for sudo credentials once (if needed) and starts a
// keep-alive goroutine that refreshes the cache every minute.
//
// The returned cancel function stops the keep-alive and MUST be called
// by the caller (typically via defer) on shutdown.
//
// No-op when:
//   - the sudo binary is not on PATH (e.g. macOS without sudo);
//   - the process is already root;
//   - the prime call fails (e.g. user cancels). The caller continues —
//     individual scripts that need sudo will prompt as usual.
func Prime() (cancel func()) {
	cmd, ok := PrimeCommand()
	if !ok {
		return func() {}
	}

	fmt.Println(text("正在缓存 sudo 凭据，避免安装过程中反复输入密码...", "Caching sudo credentials so installation will not repeatedly ask for a password..."))
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", PrimeError(err))
		return func() {}
	}

	return StartKeepAlive()
}

// PrimeCommand returns the sudo validation command used by the TUI. Bubble Tea
// must run this through tea.ExecProcess so the terminal leaves raw/AltScreen mode
// while the password prompt is active.
func PrimeCommand() (*exec.Cmd, bool) {
	return primeCommandForUID(os.Geteuid())
}

func primeCommandForUID(effectiveUID int) (*exec.Cmd, bool) {
	if effectiveUID == 0 {
		return nil, false
	}
	sudoPath, err := exec.LookPath("sudo")
	if err != nil {
		return nil, false
	}

	// Validate a concrete command first. Some environments (notably OrbStack)
	// grant NOPASSWD for commands while `sudo -v` still requires a password.
	if err := exec.Command(sudoPath, "-n", "true").Run(); err == nil {
		return exec.Command(sudoPath, "-n", "true"), true
	}

	return exec.Command(sudoPath, "-v", "-p", text("请输入 sudo 密码以继续: ", "Enter sudo password to continue: ")), true
}

// StartKeepAlive keeps the sudo timestamp warm after a successful PrimeCommand.
func StartKeepAlive() (cancel func()) {
	ctx, ctxCancel := context.WithCancel(context.Background())
	go keepAlive(ctx)
	return ctxCancel
}

func PrimeError(err error) string {
	return fmt.Sprintf(text("sudo 验证失败（%v），请重新确认后再执行。", "sudo validation failed (%v). Please confirm again before running."), err)
}

func text(zh, en string) string {
	if strings.HasPrefix(strings.ToLower(os.Getenv("OS_INIT_LANG")), "en") {
		return en
	}
	return zh
}

func keepAlive(ctx context.Context) {
	t := time.NewTicker(60 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			_ = exec.Command("sudo", "-n", "true").Run()
		}
	}
}

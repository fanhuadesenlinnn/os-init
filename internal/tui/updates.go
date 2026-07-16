package tui

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

type updateCheckResult struct {
	moduleID string
	status   string // "[可更新 X → Y]", "[已安装 X]", "[已安装]", ""
}

type updateCheckDoneMsg struct {
	results []updateCheckResult
}

type versionChecker struct {
	moduleID   string
	repo       string         // "owner/repo" for GitHub release check
	versionCmd []string       // command to get installed version
	versionRe  *regexp.Regexp // regex to extract semver from command output
}

// checkers defines modules that have GitHub release version tracking.
var versionCheckers = []versionChecker{
	{
		moduleID: "yazi",
		repo:     "sxyazi/yazi",
		versionCmd: []string{
			"sh",
			"-c",
			"brew list --versions yazi 2>/dev/null || pacman -Q yazi 2>/dev/null || dpkg-query -W -f='yazi ${Version}\\n' yazi 2>/dev/null || rpm -q --qf 'yazi %{VERSION}\\n' yazi 2>/dev/null",
		},
		versionRe: regexp.MustCompile(`(\d+\.\d+\.\d+)`),
	},
	{
		moduleID:   "neovim",
		repo:       "neovim/neovim",
		versionCmd: []string{"nvim", "--version"},
		versionRe:  regexp.MustCompile(`v(\d+\.\d+\.\d+)`),
	},
}

// runUpdateChecks checks both version updates (GitHub) and installed status for all modules.
func runUpdateChecks(mods []modules.Module) tea.Cmd {
	return func() tea.Msg {
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()

		// Build lookup for version checkers
		versionMap := make(map[string]*versionChecker, len(versionCheckers))
		for i := range versionCheckers {
			versionMap[versionCheckers[i].moduleID] = &versionCheckers[i]
		}

		checker := defaultInstallStatusChecker()
		results := make([]updateCheckResult, len(mods))
		var wg sync.WaitGroup

		for i, mod := range mods {
			wg.Add(1)
			go func(idx int, m modules.Module) {
				defer wg.Done()

				installed := checker.moduleInstalled(ctx, m)
				// Check if this module has a version checker (GitHub releases)
				if vc, ok := versionMap[m.ID]; ok {
					if !installed {
						results[idx] = updateCheckResult{moduleID: m.ID}
						return
					}
					checkCtx, checkCancel := context.WithTimeout(ctx, 5*time.Second)
					defer checkCancel()
					results[idx] = checkVersion(checkCtx, *vc)
					if results[idx].status == "" {
						results[idx] = updateCheckResult{moduleID: m.ID, status: statusInstalled()}
					}
					return
				}

				// Otherwise just check if installed + try to get version
				if installed {
					if command := m.PrimaryCommand(); command != "" {
						ver := tryGetVersion(ctx, command)
						if ver != "" {
							results[idx] = updateCheckResult{
								moduleID: m.ID,
								status:   statusInstalledWithVersion(ver),
							}
						} else {
							results[idx] = updateCheckResult{
								moduleID: m.ID,
								status:   statusInstalled(),
							}
						}
					} else {
						results[idx] = updateCheckResult{
							moduleID: m.ID,
							status:   statusInstalled(),
						}
					}
					return
				}

				results[idx] = updateCheckResult{moduleID: m.ID}
			}(i, mod)
		}

		wg.Wait()
		return updateCheckDoneMsg{results: results}
	}
}

func checkVersion(ctx context.Context, c versionChecker) updateCheckResult {
	installed := getInstalledVersion(ctx, c.versionCmd, c.versionRe)
	if installed == "" {
		return updateCheckResult{moduleID: c.moduleID}
	}

	var latest string
	if c.repo != "" {
		latest = getLatestGitHubVersion(ctx, c.repo)
	}
	if latest == "" || installed == latest {
		return updateCheckResult{moduleID: c.moduleID, status: statusInstalledWithVersion(installed)}
	}

	return updateCheckResult{
		moduleID: c.moduleID,
		status:   statusUpdate(installed, latest),
	}
}

// tryGetVersion runs `cmd --version` and extracts a semver from the output.
func tryGetVersion(ctx context.Context, cmd string) string {
	ctx2, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	c := exec.CommandContext(ctx2, cmd, "--version")
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	out, err := c.CombinedOutput()
	if err != nil {
		return ""
	}
	re := regexp.MustCompile(`(\d+\.\d+[\.\d]*)`)
	if m := re.FindString(string(out)); m != "" {
		return m
	}
	return ""
}

func getInstalledVersion(ctx context.Context, cmd []string, re *regexp.Regexp) string {
	if len(cmd) == 0 {
		return ""
	}

	c := exec.CommandContext(ctx, cmd[0], cmd[1:]...)
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	out, err := c.CombinedOutput()
	if err != nil {
		return ""
	}

	matches := re.FindStringSubmatch(string(out))
	if len(matches) < 2 {
		return ""
	}
	return matches[1]
}

// getLatestGitHubVersion performs an HTTP HEAD to the releases/latest
// endpoint and extracts the version from a redirect, final URL, or page body.
func getLatestGitHubVersion(ctx context.Context, repo string) string {
	rawURL := rewriteDownloadURL(fmt.Sprintf("https://github.com/%s/releases/latest", repo))

	client := &http.Client{
		Timeout: 5 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodHead, rawURL, nil)
	if err != nil {
		return ""
	}

	resp, err := client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	if version := semverFromReleaseURL(resp.Header.Get("Location")); version != "" {
		return version
	}

	getReq, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return ""
	}
	getResp, err := (&http.Client{Timeout: 5 * time.Second}).Do(getReq)
	if err != nil {
		return ""
	}
	defer getResp.Body.Close()
	if version := semverFromReleaseURL(getResp.Request.URL.String()); version != "" {
		return version
	}
	body, _ := io.ReadAll(io.LimitReader(getResp.Body, 2<<20))
	match := regexp.MustCompile(`/releases/tag/[^"?#<]+`).Find(body)
	return semverFromReleaseURL(string(match))
}

func semverFromReleaseURL(value string) string {
	re := regexp.MustCompile(`(\d+\.\d+\.\d+)`)
	return re.FindString(value)
}

func configuredURL(envKey, fallback string) string {
	if value := os.Getenv(envKey); value != "" {
		return value
	}
	return fallback
}

func rewriteDownloadURL(rawURL string) string {
	return rewriteGitHubURL(rawURL)
}

func rewriteGitHubURL(rawURL string) string {
	proxy := os.Getenv("GITHUB_PROXY")
	if proxy == "" {
		return rawURL
	}
	if isGitHubURL(rawURL) {
		return renderURLProxy(proxy, rawURL)
	}
	return rawURL
}

func isGitHubURL(rawURL string) bool {
	return strings.HasPrefix(rawURL, "https://github.com/") ||
		strings.HasPrefix(rawURL, "https://raw.githubusercontent.com/") ||
		strings.HasPrefix(rawURL, "https://objects.githubusercontent.com/") ||
		strings.HasPrefix(rawURL, "https://github-releases.githubusercontent.com/") ||
		strings.HasPrefix(rawURL, "https://release-assets.githubusercontent.com/") ||
		strings.HasPrefix(rawURL, "https://codeload.github.com/") ||
		strings.HasPrefix(rawURL, "https://api.github.com/")
}

func renderURLProxy(proxy, rawURL string) string {
	if strings.Contains(proxy, "{url_encoded}") {
		return strings.ReplaceAll(proxy, "{url_encoded}", url.QueryEscape(rawURL))
	}
	if strings.Contains(proxy, "{url}") {
		return strings.ReplaceAll(proxy, "{url}", rawURL)
	}
	return strings.TrimRight(proxy, "/") + "/" + rawURL
}

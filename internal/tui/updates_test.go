package tui

import (
	"strings"
	"testing"
)

func TestRewriteDownloadURL_GitHubProxyWins(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "https://gh.example.com/")
	t.Setenv("DOWNLOAD_URL_PROXY", "https://dl.example.com/?url={url}")

	got := rewriteDownloadURL("https://github.com/owner/repo/releases/latest")
	want := "https://gh.example.com/https://github.com/owner/repo/releases/latest"
	if got != want {
		t.Fatalf("unexpected url: got %q, want %q", got, want)
	}
}

func TestRewriteDownloadURL_IgnoresGenericProxy(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "")
	t.Setenv("DOWNLOAD_URL_PROXY", "https://dl.example.com/?url={url}")

	got := rewriteDownloadURL("https://go.dev/VERSION?m=text")
	want := "https://go.dev/VERSION?m=text"
	if got != want {
		t.Fatalf("unexpected url: got %q, want %q", got, want)
	}
}

func TestRewriteDownloadURL_GitHubAssetHosts(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "https://gh.example.com/?url={url}")
	t.Setenv("DOWNLOAD_URL_PROXY", "https://dl.example.com/?url={url}")

	got := rewriteDownloadURL("https://github-releases.githubusercontent.com/123/asset.tar.gz")
	want := "https://gh.example.com/?url=https://github-releases.githubusercontent.com/123/asset.tar.gz"
	if got != want {
		t.Fatalf("unexpected url: got %q, want %q", got, want)
	}
}

func TestYaziVersionCheckerDoesNotInvokeYaziBinary(t *testing.T) {
	for _, checker := range versionCheckers {
		if checker.moduleID != "yazi" {
			continue
		}
		cmd := strings.Join(checker.versionCmd, " ")
		if strings.Contains(cmd, "yazi --version") {
			t.Fatalf("yazi version checker should not invoke yazi itself: %q", cmd)
		}
		if !strings.Contains(cmd, "brew list --versions yazi") {
			t.Fatalf("yazi version checker should use package metadata, got %q", cmd)
		}
		return
	}
	t.Fatal("yazi version checker not found")
}

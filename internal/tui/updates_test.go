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

func TestRewriteDownloadURL_NormalizesProxyTrailingSlashes(t *testing.T) {
	rawURL := "https://github.com/owner/repo/releases/latest"
	want := "https://gh.example.com/https://github.com/owner/repo/releases/latest"
	for _, proxy := range []string{"https://gh.example.com", "https://gh.example.com/", "https://gh.example.com///"} {
		t.Run(proxy, func(t *testing.T) {
			t.Setenv("GITHUB_PROXY", proxy)
			if got := rewriteDownloadURL(rawURL); got != want {
				t.Fatalf("proxy %q produced %q, want %q", proxy, got, want)
			}
		})
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

func TestRewriteDownloadURL_EncodedTemplate(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "https://gh.example.com/?url={url_encoded}")

	got := rewriteDownloadURL("https://github.com/owner/repo?a=1&b=2")
	want := "https://gh.example.com/?url=https%3A%2F%2Fgithub.com%2Fowner%2Frepo%3Fa%3D1%26b%3D2"
	if got != want {
		t.Fatalf("unexpected encoded url: got %q, want %q", got, want)
	}
}

func TestRewriteDownloadURL_AdditionalGitHubHosts(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "https://gh.example.com/")
	for _, rawURL := range []string{
		"https://release-assets.githubusercontent.com/1/archive",
		"https://codeload.github.com/owner/repo/tar.gz/main",
		"https://api.github.com/repos/owner/repo/releases/latest",
	} {
		if got := rewriteDownloadURL(rawURL); got == rawURL {
			t.Fatalf("GitHub URL was not rewritten: %s", rawURL)
		}
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

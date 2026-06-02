package tui

import "testing"

func TestRewriteDownloadURL_GitHubProxyWins(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "https://gh.example.com/")
	t.Setenv("DOWNLOAD_URL_PROXY", "https://dl.example.com/?url={url}")

	got := rewriteDownloadURL("https://github.com/owner/repo/releases/latest")
	want := "https://gh.example.com/https://github.com/owner/repo/releases/latest"
	if got != want {
		t.Fatalf("unexpected url: got %q, want %q", got, want)
	}
}

func TestRewriteDownloadURL_GenericProxy(t *testing.T) {
	t.Setenv("GITHUB_PROXY", "")
	t.Setenv("DOWNLOAD_URL_PROXY", "https://dl.example.com/?url={url}")

	got := rewriteDownloadURL("https://go.dev/VERSION?m=text")
	want := "https://dl.example.com/?url=https://go.dev/VERSION?m=text"
	if got != want {
		t.Fatalf("unexpected url: got %q, want %q", got, want)
	}
}

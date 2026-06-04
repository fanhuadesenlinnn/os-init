package config

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"testing/fstest"
)

func TestParseEnv(t *testing.T) {
	t.Parallel()

	got := ParseEnv(strings.NewReader(`
# comment
export HTTP_PROXY="http://127.0.0.1:7890"
NO_PROXY='localhost,127.0.0.1'
GO_VERSION=go1.26.3
bad-key=value
`))

	if got["HTTP_PROXY"] != "http://127.0.0.1:7890" {
		t.Fatalf("unexpected HTTP_PROXY: %q", got["HTTP_PROXY"])
	}
	if got["NO_PROXY"] != "localhost,127.0.0.1" {
		t.Fatalf("unexpected NO_PROXY: %q", got["NO_PROXY"])
	}
	if got["GO_VERSION"] != "go1.26.3" {
		t.Fatalf("unexpected GO_VERSION: %q", got["GO_VERSION"])
	}
	if _, ok := got["bad-key"]; ok {
		t.Fatal("invalid key should be ignored")
	}
}

func TestCreateUserConfig(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	files := fstest.MapFS{
		embeddedExample: {Data: []byte("# 中文说明\nGITHUB_PROXY=\n")},
	}

	path, err := CreateUserConfig(files)
	if err != nil {
		t.Fatalf("CreateUserConfig failed: %v", err)
	}

	wantPath := filepath.Join(os.Getenv("HOME"), ".config", "os-init", "config.env")
	if path != wantPath {
		t.Fatalf("unexpected path: got %q, want %q", path, wantPath)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	if !strings.Contains(string(data), "中文说明") {
		t.Fatalf("config template was not copied: %q", string(data))
	}

	if err := os.WriteFile(path, []byte("CUSTOM=1\n"), 0o600); err != nil {
		t.Fatalf("write custom config: %v", err)
	}
	if _, err := CreateUserConfig(files); err != nil {
		t.Fatalf("second CreateUserConfig failed: %v", err)
	}
	data, err = os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config after second create: %v", err)
	}
	if string(data) != "CUSTOM=1\n" {
		t.Fatalf("existing config should not be overwritten: %q", string(data))
	}
}

func TestApplyIgnoresGenericProxyConfig(t *testing.T) {
	preserveEnv(t,
		"OS_INIT_PROXY",
		"HTTP_PROXY",
		"http_proxy",
		"HTTPS_PROXY",
		"https_proxy",
		"ALL_PROXY",
		"all_proxy",
		"NO_PROXY",
		"no_proxy",
		"DOWNLOAD_URL_PROXY",
		"GITHUB_PROXY",
	)
	resetOriginalEnvForTest()
	t.Cleanup(resetOriginalEnvForTest)

	for _, key := range []string{
		"OS_INIT_PROXY",
		"HTTP_PROXY",
		"http_proxy",
		"HTTPS_PROXY",
		"https_proxy",
		"ALL_PROXY",
		"all_proxy",
		"NO_PROXY",
		"no_proxy",
		"DOWNLOAD_URL_PROXY",
		"GITHUB_PROXY",
	} {
		os.Unsetenv(key)
	}
	t.Setenv("HOME", t.TempDir())

	files := fstest.MapFS{
		embeddedDefaults: {Data: []byte(`
OS_INIT_PROXY=http://127.0.0.1:7890
HTTP_PROXY=http://127.0.0.1:7890
DOWNLOAD_URL_PROXY=https://dl.example.com/?url={url}
GITHUB_PROXY=https://gh.example.com/
`)},
	}

	Apply(files)
	if got := os.Getenv("HTTP_PROXY"); got != "" {
		t.Fatalf("HTTP_PROXY from config should be ignored, got %q", got)
	}
	if got := os.Getenv("DOWNLOAD_URL_PROXY"); got != "" {
		t.Fatalf("DOWNLOAD_URL_PROXY from config should be ignored, got %q", got)
	}
	if got := os.Getenv("GITHUB_PROXY"); got != "https://gh.example.com/" {
		t.Fatalf("GITHUB_PROXY should be loaded, got %q", got)
	}
}

func TestApplyUsesUserConfigCreatedAfterInitialLoad(t *testing.T) {
	preserveEnv(t,
		"OS_INIT_FILES_DIR",
		"OS_INIT_PROXY",
		"HTTP_PROXY",
		"http_proxy",
		"HTTPS_PROXY",
		"https_proxy",
		"ALL_PROXY",
		"all_proxy",
		"NO_PROXY",
		"no_proxy",
	)
	resetOriginalEnvForTest()
	t.Cleanup(resetOriginalEnvForTest)
	os.Unsetenv("OS_INIT_FILES_DIR")

	home := t.TempDir()
	t.Setenv("HOME", home)
	files := fstest.MapFS{
		embeddedDefaults: {Data: []byte("OS_INIT_FILES_DIR=\nNO_PROXY=localhost\n")},
	}

	Apply(files)
	if got := os.Getenv("OS_INIT_FILES_DIR"); got != "" {
		t.Fatalf("unexpected OS_INIT_FILES_DIR after defaults: %q", got)
	}

	userConfigDir := filepath.Join(home, ".config", "os-init")
	if err := os.MkdirAll(userConfigDir, 0o700); err != nil {
		t.Fatalf("create user config dir: %v", err)
	}
	userConfig := filepath.Join(userConfigDir, "config.env")
	if err := os.WriteFile(userConfig, []byte("OS_INIT_FILES_DIR=/opt/os-init/packages\n"), 0o600); err != nil {
		t.Fatalf("write user config: %v", err)
	}

	Apply(files)
	if got := os.Getenv("OS_INIT_FILES_DIR"); got != "/opt/os-init/packages" {
		t.Fatalf("user config should win after second Apply, got %q", got)
	}
}

func TestApplyPreservesRuntimeOverride(t *testing.T) {
	preserveEnv(t, "OS_INIT_LANG")
	resetOriginalEnvForTest()
	t.Cleanup(resetOriginalEnvForTest)
	t.Cleanup(func() {
		overrideMu.Lock()
		defer overrideMu.Unlock()
		runtimeOverride = map[string]string{}
	})

	files := fstest.MapFS{
		embeddedDefaults: {Data: []byte("OS_INIT_LANG=zh_CN\n")},
	}

	Apply(files)
	if got := os.Getenv("OS_INIT_LANG"); got != "zh_CN" {
		t.Fatalf("default language = %q, want zh_CN", got)
	}

	SetRuntimeOverride("OS_INIT_LANG", "en_US")
	Apply(files)
	if got := os.Getenv("OS_INIT_LANG"); got != "en_US" {
		t.Fatalf("runtime language override = %q, want en_US", got)
	}
}

func resetOriginalEnvForTest() {
	originalEnvOnce = sync.Once{}
	originalEnv = nil
}

func preserveEnv(t *testing.T, keys ...string) {
	t.Helper()

	type envValue struct {
		value string
		ok    bool
	}
	previous := make(map[string]envValue, len(keys))
	for _, key := range keys {
		value, ok := os.LookupEnv(key)
		previous[key] = envValue{value: value, ok: ok}
	}
	t.Cleanup(func() {
		for key, item := range previous {
			if item.ok {
				_ = os.Setenv(key, item.value)
			} else {
				_ = os.Unsetenv(key)
			}
		}
	})
}

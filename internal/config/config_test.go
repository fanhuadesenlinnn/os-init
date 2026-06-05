package config

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"
	"testing/fstest"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
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
	files := fstest.MapFS{}

	path, err := createUserConfig(files, platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN")
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
	if !strings.Contains(string(data), "OS Init 启动配置") || !strings.Contains(string(data), "GITHUB_PROXY=") {
		t.Fatalf("config was not generated with expected content: %q", string(data))
	}

	if err := os.WriteFile(path, []byte("CUSTOM=1\n"), 0o600); err != nil {
		t.Fatalf("write custom config: %v", err)
	}
	if _, err := createUserConfig(files, platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN"); err != nil {
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

func TestRenderUserConfig_DarwinIncludesMacOSSections(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}, "zh_CN"))
	for _, want := range []string{"macOS / Homebrew", "HOMEBREW_API_DOMAIN=", "OH_MY_ZSH_REPO=", "GO_DOWNLOAD_BASE="} {
		if !strings.Contains(data, want) {
			t.Fatalf("darwin config should contain %q, got %q", want, data)
		}
	}
	for _, unwanted := range []string{"DOCKER_DOWNLOAD_BASE=", "MIHOMO_PACKAGE=", "OS_INIT_ARCHDEVKIT_DEFAULT_PROFILE="} {
		if strings.Contains(data, unwanted) {
			t.Fatalf("darwin config should not contain %q, got %q", unwanted, data)
		}
	}
}

func TestRenderUserConfig_LinuxIncludesServerSections(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN"))
	for _, want := range []string{"DOCKER_DOWNLOAD_BASE=", "MIHOMO_PACKAGE=", "NVIM_DOWNLOAD_BASE=", "YAZI_DOWNLOAD_BASE="} {
		if !strings.Contains(data, want) {
			t.Fatalf("linux config should contain %q, got %q", want, data)
		}
	}
	if strings.Contains(data, "HOMEBREW_API_DOMAIN=") {
		t.Fatalf("linux config should not contain Homebrew settings, got %q", data)
	}
	if strings.Contains(data, "OS_INIT_ARCHDEVKIT_DEFAULT_PROFILE=") {
		t.Fatalf("non-Arch linux config should not contain ArchDevKit settings, got %q", data)
	}
}

func TestRenderUserConfig_ArchIncludesArchDevKitBridge(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "linux", Family: platform.FamilyArch}, "zh_CN"))
	for _, want := range []string{
		"ArchDevKit 桥接配置",
		"OS_INIT_ARCHDEVKIT_DEFAULT_PROFILE=dev",
		"OS_INIT_ARCHDEVKIT_ENABLE_PROXY=1",
		"OS_INIT_ARCHDEVKIT_PROXY_CORE=mihomo",
		"OS_INIT_ARCHDEVKIT_ENABLE_METACUBEXD=1",
	} {
		if !strings.Contains(data, want) {
			t.Fatalf("arch config should contain %q, got %q", want, data)
		}
	}
}

func TestRenderUserConfig_EnglishComments(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}, "en_US"))
	for _, want := range []string{"OS Init startup configuration", "Base Settings", "OS_INIT_LANG=en_US"} {
		if !strings.Contains(data, want) {
			t.Fatalf("english config should contain %q, got %q", want, data)
		}
	}
	if strings.Contains(data, "启动配置") {
		t.Fatalf("english config should not contain Chinese header, got %q", data)
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

func TestEmbeddedConfigKeysMatchShellWhitelist(t *testing.T) {
	t.Parallel()

	defaults := readRepoFile(t, "modules/config/defaults.env")
	example := readRepoFile(t, "modules/config/config.env.example")
	lib := readRepoFile(t, "modules/lib.sh")

	defaultKeys := sortedKeys(ParseEnv(strings.NewReader(defaults)))
	exampleKeys := sortedKeys(ParseEnv(strings.NewReader(example)))
	shellKeys := parseShellConfigKeys(t, lib)

	if diff := compareKeySets("defaults", defaultKeys, "example", exampleKeys); diff != "" {
		t.Fatal(diff)
	}
	if diff := compareKeySets("defaults", defaultKeys, "shell whitelist", shellKeys); diff != "" {
		t.Fatal(diff)
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

func readRepoFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", path))
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func parseShellConfigKeys(t *testing.T, lib string) []string {
	t.Helper()
	re := regexp.MustCompile(`(?s)OS_INIT_CONFIG_KEYS=\(\n(?P<body>.*?)\n\)`)
	match := re.FindStringSubmatch(lib)
	if match == nil {
		t.Fatal("OS_INIT_CONFIG_KEYS block not found")
	}
	keys := strings.Fields(match[1])
	sort.Strings(keys)
	return keys
}

func sortedKeys(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func compareKeySets(leftName string, left []string, rightName string, right []string) string {
	leftOnly, rightOnly := diffKeys(left, right)
	if len(leftOnly) == 0 && len(rightOnly) == 0 {
		return ""
	}
	return leftName + " and " + rightName + " config keys differ; " +
		leftName + " only=" + strings.Join(leftOnly, ",") + "; " +
		rightName + " only=" + strings.Join(rightOnly, ",")
}

func diffKeys(left []string, right []string) ([]string, []string) {
	rightSet := make(map[string]bool, len(right))
	for _, key := range right {
		rightSet[key] = true
	}
	leftSet := make(map[string]bool, len(left))
	for _, key := range left {
		leftSet[key] = true
	}

	leftOnly := make([]string, 0)
	for _, key := range left {
		if !rightSet[key] {
			leftOnly = append(leftOnly, key)
		}
	}
	rightOnly := make([]string, 0)
	for _, key := range right {
		if !leftSet[key] {
			rightOnly = append(rightOnly, key)
		}
	}
	return leftOnly, rightOnly
}

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
OS_INIT_MISE_GO_VERSION=1.26
bad-key=value
`))

	if got["HTTP_PROXY"] != "http://127.0.0.1:7890" {
		t.Fatalf("unexpected HTTP_PROXY: %q", got["HTTP_PROXY"])
	}
	if got["NO_PROXY"] != "localhost,127.0.0.1" {
		t.Fatalf("unexpected NO_PROXY: %q", got["NO_PROXY"])
	}
	if got["OS_INIT_MISE_GO_VERSION"] != "1.26" {
		t.Fatalf("unexpected OS_INIT_MISE_GO_VERSION: %q", got["OS_INIT_MISE_GO_VERSION"])
	}
	if _, ok := got["bad-key"]; ok {
		t.Fatal("invalid key should be ignored")
	}
}

func TestCreateUserConfig(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	files := fstest.MapFS{}

	path, err := CreateUserConfig(files, platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN")
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
	if !strings.Contains(string(data), "OS Init 启动配置") || !strings.Contains(string(data), "GITHUB_PROXY=https://hubproxy.babadafafafafa.cn") {
		t.Fatalf("config was not generated with expected content: %q", string(data))
	}

	if err := os.WriteFile(path, []byte("CUSTOM=1\n"), 0o600); err != nil {
		t.Fatalf("write custom config: %v", err)
	}
	if _, err := CreateUserConfig(files, platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN"); err != nil {
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

func TestCreateUserConfigUsesSelectedLanguage(t *testing.T) {
	tests := []struct {
		name       string
		lang       string
		wantHeader string
		wantValue  string
		unwanted   string
	}{
		{name: "Chinese", lang: "zh_CN", wantHeader: "# OS Init 启动配置", wantValue: "OS_INIT_LANG=zh_CN", unwanted: "# Base Settings"},
		{name: "English", lang: "en_US", wantHeader: "# OS Init startup configuration", wantValue: "OS_INIT_LANG=en_US", unwanted: "# 基础设置"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("HOME", t.TempDir())
			path, err := CreateUserConfig(fstest.MapFS{}, platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}, tt.lang)
			if err != nil {
				t.Fatalf("CreateUserConfig failed: %v", err)
			}
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			content := string(data)
			for _, want := range []string{tt.wantHeader, tt.wantValue} {
				if !strings.Contains(content, want) {
					t.Fatalf("generated config should contain %q, got %q", want, content)
				}
			}
			if strings.Contains(content, tt.unwanted) {
				t.Fatalf("generated config should not contain the other language %q", tt.unwanted)
			}
		})
	}
}

func TestRenderUserConfig_DarwinIncludesMacOSSections(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}, "zh_CN"))
	assertGeneratedConfigKeys(t, data, []string{
		"OS_INIT_LANG", "OS_INIT_REGION", "OS_INIT_CONFIG_PROMPT", "OS_INIT_SCRIPT_TIMEOUT", "GITHUB_PROXY",
		"HOMEBREW_API_DOMAIN", "HOMEBREW_BOTTLE_DOMAIN",
		"OS_INIT_MISE_NODE_VERSION", "OS_INIT_MISE_PYTHON_VERSION", "OS_INIT_MISE_GO_VERSION",
		"MISE_NODE_MIRROR_URL", "MISE_GO_DOWNLOAD_MIRROR", "NPM_CONFIG_REGISTRY", "PIP_INDEX_URL", "UV_DEFAULT_INDEX", "GOPROXY", "NVIM_CONFIG_REPO",
	})
	for _, want := range []string{"macOS / Homebrew", "HOMEBREW_API_DOMAIN=", "HOMEBREW_BOTTLE_DOMAIN=", "NVIM_CONFIG_REPO=", "OS_INIT_MISE_NODE_VERSION=24", "OS_INIT_MISE_PYTHON_VERSION=3.13", "OS_INIT_MISE_GO_VERSION=1.26"} {
		if !strings.Contains(data, want) {
			t.Fatalf("darwin config should contain %q, got %q", want, data)
		}
	}
	for _, unwanted := range []string{"NVM_INSTALL_URL=", "FNM_INSTALL_URL=", "GO_DOWNLOAD_BASE=", "GO_VERSION_URL="} {
		if strings.Contains(data, unwanted) {
			t.Fatalf("darwin config should not contain retired runtime manager setting %q", unwanted)
		}
	}
	for _, unwanted := range []string{"MISE_DOWNLOAD_BASE=", "HOMEBREW_INSTALL_URL=", "DOCKER_REGISTRY_MIRRORS=", "MIHOMO_CONFIG_SOURCE=", "PACMAN_RETRY_ATTEMPTS=", "ENABLE_DNS=", "GPU_TYPE="} {
		if strings.Contains(data, unwanted) {
			t.Fatalf("darwin config should not contain %q, got %q", unwanted, data)
		}
	}
}

func TestRenderUserConfig_LinuxIncludesServerSections(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "linux", Family: platform.FamilyDebian}, "zh_CN"))
	assertGeneratedConfigKeys(t, data, []string{
		"OS_INIT_LANG", "OS_INIT_REGION", "OS_INIT_CONFIG_PROMPT", "OS_INIT_SCRIPT_TIMEOUT", "GITHUB_PROXY",
		"OS_INIT_MISE_NODE_VERSION", "OS_INIT_MISE_PYTHON_VERSION", "OS_INIT_MISE_GO_VERSION",
		"MISE_NODE_MIRROR_URL", "MISE_GO_DOWNLOAD_MIRROR", "NPM_CONFIG_REGISTRY", "PIP_INDEX_URL", "UV_DEFAULT_INDEX", "GOPROXY", "NVIM_CONFIG_REPO",
		"DOCKER_REGISTRY_MIRRORS", "DOCKER_INSECURE_REGISTRIES", "DOCKER_DATA_ROOT",
		"MIHOMO_CONFIG_SOURCE", "MIHOMO_MIXED_PORT", "MIHOMO_ALLOW_LAN", "MIHOMO_BIND_ADDRESS", "MIHOMO_CONTROLLER_HOST", "MIHOMO_CONTROLLER_PORT", "MIHOMO_DNS_LISTEN", "MIHOMO_SECRET", "MIHOMO_AUTO_ENABLE_SERVICE", "ENABLE_METACUBEXD",
	})
	for _, want := range []string{
		"DOCKER_REGISTRY_MIRRORS=https://hubproxy.babadafafafafa.cn",
		"DOCKER_INSECURE_REGISTRIES=",
		"MIHOMO_CONFIG_SOURCE=",
		"MIHOMO_ALLOW_LAN=0",
		"MIHOMO_BIND_ADDRESS=0.0.0.0",
		"MIHOMO_CONTROLLER_HOST=0.0.0.0",
		"MIHOMO_DNS_LISTEN=0.0.0.0:1053",
		"MIHOMO_SECRET=\n",
		"MIHOMO_AUTO_ENABLE_SERVICE=1",
	} {
		if !strings.Contains(data, want) {
			t.Fatalf("linux config should contain %q, got %q", want, data)
		}
	}
	for _, unwanted := range []string{"HOMEBREW_API_DOMAIN=", "DOCKER_DOWNLOAD_BASE=", "MISE_DOWNLOAD_BASE=", "NVIM_DOWNLOAD_BASE=", "PACMAN_RETRY_ATTEMPTS=", "ENABLE_DNS=", "GPU_TYPE="} {
		if strings.Contains(data, unwanted) {
			t.Fatalf("non-Arch linux config should not contain %q, got %q", unwanted, data)
		}
	}
}

func TestRenderUserConfig_ArchIncludesNativeCapabilities(t *testing.T) {
	t.Parallel()

	data := string(renderUserConfig(platform.Target{GOOS: "linux", Family: platform.FamilyArch}, "zh_CN"))
	assertGeneratedConfigKeys(t, data, []string{
		"OS_INIT_LANG", "OS_INIT_REGION", "OS_INIT_CONFIG_PROMPT", "OS_INIT_SCRIPT_TIMEOUT", "GITHUB_PROXY",
		"OS_INIT_MISE_NODE_VERSION", "OS_INIT_MISE_PYTHON_VERSION", "OS_INIT_MISE_GO_VERSION",
		"MISE_NODE_MIRROR_URL", "MISE_GO_DOWNLOAD_MIRROR", "NPM_CONFIG_REGISTRY", "PIP_INDEX_URL", "UV_DEFAULT_INDEX", "GOPROXY", "NVIM_CONFIG_REPO",
		"DOCKER_REGISTRY_MIRRORS", "DOCKER_INSECURE_REGISTRIES", "DOCKER_DATA_ROOT",
		"PACMAN_RETRY_ATTEMPTS", "ARCHLINUXARM_MIRRORS", "ENABLE_DNS", "ENABLE_OPS_TOOLKIT", "GPU_TYPE",
		"MIHOMO_CONFIG_SOURCE", "MIHOMO_MIXED_PORT", "MIHOMO_ALLOW_LAN", "MIHOMO_BIND_ADDRESS", "MIHOMO_CONTROLLER_HOST", "MIHOMO_CONTROLLER_PORT", "MIHOMO_DNS_LISTEN", "MIHOMO_SECRET", "MIHOMO_AUTO_ENABLE_SERVICE", "ENABLE_METACUBEXD",
	})
	for _, want := range []string{
		"Arch Linux 能力",
		"Arch Mihomo",
		"MIHOMO_BIND_ADDRESS=0.0.0.0",
		"MIHOMO_DNS_LISTEN=0.0.0.0:1053",
		"MIHOMO_AUTO_ENABLE_SERVICE=1",
		"GPU_TYPE=auto",
	} {
		if !strings.Contains(data, want) {
			t.Fatalf("arch config should contain %q, got %q", want, data)
		}
	}
	for _, unwanted := range []string{"PROXY_AUTO_ENABLE_SERVICE=", "MIHOMO_DOWNLOAD_BASE=", "DOCKER_DOWNLOAD_BASE=", "MISE_DOWNLOAD_BASE=", "NVIM_DOWNLOAD_BASE=", "HOMEBREW_API_DOMAIN=", "SING_BOX_PACKAGE="} {
		if strings.Contains(data, unwanted) {
			t.Fatalf("arch config should not contain %q, got %q", unwanted, data)
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

func assertGeneratedConfigKeys(t *testing.T, data string, expected []string) {
	t.Helper()
	actual := sortedKeys(ParseEnv(strings.NewReader(data)))
	want := append([]string(nil), expected...)
	sort.Strings(want)
	if diff := compareKeySets("generated", actual, "expected platform keys", want); diff != "" {
		t.Fatal(diff)
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
		"DOWNLOAD_TIMEOUT",
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
	os.Unsetenv("DOWNLOAD_TIMEOUT")

	home := t.TempDir()
	t.Setenv("HOME", home)
	files := fstest.MapFS{
		embeddedDefaults: {Data: []byte("DOWNLOAD_TIMEOUT=30\nNO_PROXY=localhost\n")},
	}

	Apply(files)
	if got := os.Getenv("DOWNLOAD_TIMEOUT"); got != "30" {
		t.Fatalf("unexpected DOWNLOAD_TIMEOUT after defaults: %q", got)
	}

	userConfigDir := filepath.Join(home, ".config", "os-init")
	if err := os.MkdirAll(userConfigDir, 0o700); err != nil {
		t.Fatalf("create user config dir: %v", err)
	}
	userConfig := filepath.Join(userConfigDir, "config.env")
	if err := os.WriteFile(userConfig, []byte("DOWNLOAD_TIMEOUT=45\n"), 0o600); err != nil {
		t.Fatalf("write user config: %v", err)
	}

	Apply(files)
	if got := os.Getenv("DOWNLOAD_TIMEOUT"); got != "45" {
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

func TestEmbeddedDefaultKeysMatchShellWhitelist(t *testing.T) {
	t.Parallel()

	defaults := readRepoFile(t, "modules/config/defaults.env")
	lib := readRepoFile(t, "modules/lib.sh")

	defaultKeys := sortedKeys(ParseEnv(strings.NewReader(defaults)))
	shellKeys := parseShellConfigKeys(t, lib)

	if diff := compareKeySets("defaults", defaultKeys, "shell whitelist", shellKeys); diff != "" {
		t.Fatal(diff)
	}
}

func TestGeneratedConfigValuesMatchEmbeddedDefaults(t *testing.T) {
	t.Parallel()

	defaults := ParseEnv(strings.NewReader(readRepoFile(t, "modules/config/defaults.env")))
	targets := []platform.Target{
		{GOOS: "darwin", Family: platform.FamilyDarwin},
		{GOOS: "linux", Family: platform.FamilyDebian},
		{GOOS: "linux", Family: platform.FamilyArch},
	}
	for _, target := range targets {
		target := target
		t.Run(target.GOOS+"/"+string(target.Family), func(t *testing.T) {
			rendered := ParseEnv(strings.NewReader(string(renderUserConfig(target, "zh_CN"))))
			for key, value := range rendered {
				if defaultValue, ok := defaults[key]; ok && value != defaultValue {
					t.Errorf("generated %s=%q, embedded default=%q", key, value, defaultValue)
				}
			}
		})
	}
}

func TestApplyIgnoresUndeclaredConfigKeys(t *testing.T) {
	preserveEnv(t, "UNDECLARED_OS_INIT_TEST")
	resetOriginalEnvForTest()
	t.Cleanup(resetOriginalEnvForTest)
	os.Unsetenv("UNDECLARED_OS_INIT_TEST")

	home := t.TempDir()
	t.Setenv("HOME", home)
	configDir := filepath.Join(home, ".config", "os-init")
	if err := os.MkdirAll(configDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(configDir, "config.env"), []byte("UNDECLARED_OS_INIT_TEST=unexpected\nDOWNLOAD_TIMEOUT=45\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	files := fstest.MapFS{embeddedDefaults: {Data: []byte("DOWNLOAD_TIMEOUT=30\n")}}
	Apply(files)
	if got := os.Getenv("UNDECLARED_OS_INIT_TEST"); got != "" {
		t.Fatalf("undeclared config key leaked into process environment: %q", got)
	}
	if got := os.Getenv("DOWNLOAD_TIMEOUT"); got != "45" {
		t.Fatalf("declared user config value = %q, want 45", got)
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

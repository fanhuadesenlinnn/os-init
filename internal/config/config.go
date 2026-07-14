package config

import (
	"bufio"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unicode"
)

const embeddedDefaults = "modules/config/defaults.env"

var (
	originalEnvOnce sync.Once
	originalEnv     map[string]string
	overrideMu      sync.Mutex
	runtimeOverride = map[string]string{}
)

// Apply loads os-init env files for Go-side network work, preserving
// environment variables as the final override just like modules/lib.sh.
func Apply(assets fs.FS) {
	originalEnvOnce.Do(func() {
		originalEnv = snapshotEnv()
	})

	allowedKeys := map[string]bool{}
	if assets != nil {
		allowedKeys = loadDefaults(assets, embeddedDefaults)
	}
	loadLocalFile("/etc/os-init/config.env", allowedKeys)
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		loadLocalFile(filepath.Join(home, ".config", "os-init", "config.env"), allowedKeys)
	}

	for key, value := range originalEnv {
		_ = os.Setenv(key, value)
	}
	applyRuntimeOverrides()
}

// SetRuntimeOverride pins a setting for this process after config files are
// loaded. It is used for choices made before config startup, such as language.
func SetRuntimeOverride(key, value string) {
	if !validKey(key) {
		return
	}
	overrideMu.Lock()
	defer overrideMu.Unlock()
	runtimeOverride[key] = value
	_ = os.Setenv(key, value)
}

func applyRuntimeOverrides() {
	overrideMu.Lock()
	defer overrideMu.Unlock()
	for key, value := range runtimeOverride {
		_ = os.Setenv(key, value)
	}
}

func snapshotEnv() map[string]string {
	env := make(map[string]string)
	for _, item := range os.Environ() {
		key, value, ok := strings.Cut(item, "=")
		if ok {
			env[key] = value
		}
	}
	return env
}

func loadDefaults(files fs.FS, path string) map[string]bool {
	allowedKeys := map[string]bool{}
	file, err := files.Open(path)
	if err != nil {
		return allowedKeys
	}
	defer file.Close()
	values := ParseEnv(file)
	for key, value := range values {
		allowedKeys[key] = true
		if ignoredProxyConfigKey(key) {
			continue
		}
		_ = os.Setenv(key, value)
	}
	return allowedKeys
}

func loadLocalFile(path string, allowedKeys map[string]bool) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer file.Close()
	loadEnv(file, allowedKeys)
}

func loadEnv(r io.Reader, allowedKeys map[string]bool) {
	for key, value := range ParseEnv(r) {
		if !allowedKeys[key] || ignoredProxyConfigKey(key) {
			continue
		}
		_ = os.Setenv(key, value)
	}
}

func ignoredProxyConfigKey(key string) bool {
	switch key {
	case "OS_INIT_PROXY", "os_init_proxy",
		"HTTP_PROXY", "http_proxy",
		"HTTPS_PROXY", "https_proxy",
		"ALL_PROXY", "all_proxy",
		"NO_PROXY", "no_proxy",
		"DOWNLOAD_URL_PROXY":
		return true
	default:
		return false
	}
}

// ParseEnv parses the simple KEY=value format used by os-init config files.
func ParseEnv(r io.Reader) map[string]string {
	values := make(map[string]string)
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if !validKey(key) {
			continue
		}
		values[key] = unquoteValue(strings.TrimSpace(value))
	}
	return values
}

func validKey(key string) bool {
	for i, r := range key {
		if i == 0 {
			if r != '_' && !unicode.IsLetter(r) {
				return false
			}
			continue
		}
		if r != '_' && !unicode.IsLetter(r) && !unicode.IsDigit(r) {
			return false
		}
	}
	return key != ""
}

func unquoteValue(value string) string {
	if len(value) < 2 {
		return value
	}
	quote := value[0]
	if (quote != '\'' && quote != '"') || value[len(value)-1] != quote {
		return value
	}
	value = value[1 : len(value)-1]
	if quote == '\'' {
		return value
	}
	value = strings.ReplaceAll(value, `\"`, `"`)
	value = strings.ReplaceAll(value, `\\`, `\`)
	return value
}

package config

import (
	"bufio"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

const embeddedDefaults = "modules/config/defaults.env"

// Apply loads os-init env files for Go-side network work, preserving
// environment variables as the final override just like modules/lib.sh.
func Apply(assets fs.FS) {
	original := snapshotEnv()

	if assets != nil {
		loadFSFile(assets, embeddedDefaults)
	}
	loadLocalFile("/etc/os-init/config.env")
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		loadLocalFile(filepath.Join(home, ".config", "os-init", "config.env"))
	}

	for key, value := range original {
		_ = os.Setenv(key, value)
	}
	exportProxyEnv()
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

func loadFSFile(files fs.FS, path string) {
	file, err := files.Open(path)
	if err != nil {
		return
	}
	defer file.Close()
	loadEnv(file)
}

func loadLocalFile(path string) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer file.Close()
	loadEnv(file)
}

func loadEnv(r io.Reader) {
	for key, value := range ParseEnv(r) {
		_ = os.Setenv(key, value)
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

func exportProxyEnv() {
	osInitProxy := firstNonempty(os.Getenv("OS_INIT_PROXY"), os.Getenv("os_init_proxy"))
	httpProxy := firstNonempty(os.Getenv("HTTP_PROXY"), os.Getenv("http_proxy"))
	httpsProxy := firstNonempty(os.Getenv("HTTPS_PROXY"), os.Getenv("https_proxy"))
	allProxy := firstNonempty(os.Getenv("ALL_PROXY"), os.Getenv("all_proxy"))
	noProxy := firstNonempty(os.Getenv("NO_PROXY"), os.Getenv("no_proxy"))

	if osInitProxy != "" {
		httpProxy = firstNonempty(httpProxy, osInitProxy)
		httpsProxy = firstNonempty(httpsProxy, osInitProxy)
		allProxy = firstNonempty(allProxy, osInitProxy)
	}

	setProxyPair("HTTP_PROXY", "http_proxy", httpProxy)
	setProxyPair("HTTPS_PROXY", "https_proxy", httpsProxy)
	setProxyPair("ALL_PROXY", "all_proxy", allProxy)
	setProxyPair("NO_PROXY", "no_proxy", noProxy)
}

func firstNonempty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func setProxyPair(upper, lower, value string) {
	_ = os.Setenv(upper, value)
	_ = os.Setenv(lower, value)
}

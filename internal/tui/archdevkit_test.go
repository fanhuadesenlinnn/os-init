package tui

import (
	"os"
	"path/filepath"
	"testing"
	"testing/fstest"
)

func TestLoadArchDevKitSettings_UsesEmbeddedDefaultsAndUserConfig(t *testing.T) {
	t.Setenv("ARCHDEVKIT_LOAD_CONFIG_FILE", "1")

	dir := t.TempDir()
	configPath := filepath.Join(dir, "config.env")
	if err := os.WriteFile(configPath, []byte(`
ARCHDEVKIT_DEFAULT_PROFILE="dev"
PROXY_CORE="sing-box"
BROWSER_PACKAGE="firefox" # user choice
`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ARCHDEVKIT_CONFIG_FILE", configPath)

	fsys := fstest.MapFS{
		"modules/archdevkit/vendor/install_vars": {Data: []byte(`
ARCHDEVKIT_DEFAULT_PROFILE="workstation"
PROXY_CORE="mihomo"
BROWSER_PACKAGE="google-chrome"
`)},
	}

	values := loadArchDevKitSettings(fsys)
	if values["ARCHDEVKIT_DEFAULT_PROFILE"] != "dev" {
		t.Fatalf("profile = %q, want dev", values["ARCHDEVKIT_DEFAULT_PROFILE"])
	}
	if values["PROXY_CORE"] != "sing-box" {
		t.Fatalf("proxy core = %q, want sing-box", values["PROXY_CORE"])
	}
	if values["BROWSER_PACKAGE"] != "firefox" {
		t.Fatalf("browser package = %q, want firefox", values["BROWSER_PACKAGE"])
	}
}

func TestLoadArchDevKitSettings_UsesOsInitBridgeEnv(t *testing.T) {
	t.Setenv("ARCHDEVKIT_LOAD_CONFIG_FILE", "0")
	t.Setenv("OS_INIT_ARCHDEVKIT_DEFAULT_PROFILE", "dev")
	t.Setenv("OS_INIT_ARCHDEVKIT_PROXY_CORE", "sing-box")
	t.Setenv("OS_INIT_ARCHDEVKIT_ENABLE_METACUBEXD", "0")

	fsys := fstest.MapFS{
		"modules/archdevkit/vendor/install_vars": {Data: []byte(`
ARCHDEVKIT_DEFAULT_PROFILE="workstation"
PROXY_CORE="mihomo"
ENABLE_METACUBEXD=1
`)},
	}

	values := loadArchDevKitSettings(fsys)
	if values["ARCHDEVKIT_DEFAULT_PROFILE"] != "dev" {
		t.Fatalf("profile = %q, want dev", values["ARCHDEVKIT_DEFAULT_PROFILE"])
	}
	if values["PROXY_CORE"] != "sing-box" {
		t.Fatalf("proxy core = %q, want sing-box", values["PROXY_CORE"])
	}
	if values["ENABLE_METACUBEXD"] != "0" {
		t.Fatalf("metacubexd = %q, want 0", values["ENABLE_METACUBEXD"])
	}
}

func TestArchDevKitExecutionEnv_FiltersStaleBranchOverrides(t *testing.T) {
	m := newArchDevKitModel(nil)
	m.target = "workstation"
	m.values["ENABLE_PROXY"] = "0"
	m.overrides["ENABLE_PROXY"] = "0"
	m.overrides["PROXY_CORE"] = "sing-box"
	m.overrides["ENABLE_METACUBEXD"] = "1"

	env := m.executionEnv()
	if env["OS_INIT_ARCHDEVKIT_ENABLE_PROXY"] != "0" {
		t.Fatalf("ENABLE_PROXY env = %q, want 0", env["OS_INIT_ARCHDEVKIT_ENABLE_PROXY"])
	}
	if _, ok := env["OS_INIT_ARCHDEVKIT_PROXY_CORE"]; ok {
		t.Fatal("stale PROXY_CORE override should not be emitted when proxy is disabled")
	}
	if _, ok := env["OS_INIT_ARCHDEVKIT_ENABLE_METACUBEXD"]; ok {
		t.Fatal("stale ENABLE_METACUBEXD override should not be emitted when proxy is disabled")
	}
}

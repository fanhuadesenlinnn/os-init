package main

import (
	"errors"
	"os"
	"os/user"
	"strings"
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestUsageTextDocumentsActualInterface(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")
	got := usageText()
	for _, want := range []string{
		"Usage:",
		"os-init [options]",
		"-h, --help",
		"-v, --version",
		"--system-info",
		"os-init module help",
		"~/.config/os-init/config.env",
		"environment > user configuration > built-in defaults",
		"OS_INIT_SCRIPT_TIMEOUT",
		"logs/",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("usage text should contain %q, got %q", want, got)
		}
	}
	for _, unsupported := range []string{"--install", "--update", "--uninstall"} {
		if strings.Contains(got, unsupported) {
			t.Fatalf("usage text should not advertise unsupported flag %q", unsupported)
		}
	}
}

func TestUsageTextHasChineseHelp(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "zh_CN")
	got := usageText()
	for _, want := range []string{"交互式系统初始化工具", "配置优先级", "常用环境变量", "系统权限"} {
		if !strings.Contains(got, want) {
			t.Fatalf("Chinese usage text should contain %q, got %q", want, got)
		}
	}
}

func TestSystemInfoTextIsMachineReadable(t *testing.T) {
	target := platform.Target{
		GOOS:        "linux",
		ID:          "rocky",
		Family:      platform.FamilyRedHat,
		VersionID:   "9.4",
		Init:        "systemd",
		Environment: platform.EnvironmentNative,
	}
	want := "goos=linux\nid=rocky\nfamily=redhat\nversion_id=9.4\ninit=systemd\nenvironment=native\nwsl_version=0\nwslg=false\n"
	if got := systemInfoText(target); got != want {
		t.Fatalf("system info = %q, want %q", got, want)
	}
}

func TestSystemInfoTextIncludesWSLCapabilities(t *testing.T) {
	target := platform.Target{
		GOOS: "linux", ID: "ubuntu", Family: platform.FamilyDebian, Init: "systemd",
		Environment: platform.EnvironmentWSL, WSLVersion: 2, WSLg: true,
	}
	got := systemInfoText(target)
	for _, want := range []string{"environment=wsl\n", "wsl_version=2\n", "wslg=true\n"} {
		if !strings.Contains(got, want) {
			t.Fatalf("system info should contain %q, got %q", want, got)
		}
	}
}

func TestNormalizeRootHome(t *testing.T) {
	oldHome, hadHome := os.LookupEnv("HOME")
	t.Cleanup(func() {
		if hadHome {
			_ = os.Setenv("HOME", oldHome)
		} else {
			_ = os.Unsetenv("HOME")
		}
	})

	_ = os.Setenv("HOME", "/home/alice")
	normalizeRootHome(0, func(string) (*user.User, error) {
		return &user.User{Uid: "0", Username: "root", HomeDir: "/root"}, nil
	})
	if got := os.Getenv("HOME"); got != "/root" {
		t.Fatalf("root HOME = %q, want /root", got)
	}

	_ = os.Setenv("HOME", "/home/alice")
	normalizeRootHome(1000, func(string) (*user.User, error) {
		return nil, errors.New("should not be called")
	})
	if got := os.Getenv("HOME"); got != "/home/alice" {
		t.Fatalf("normal user HOME changed to %q", got)
	}
}

func TestRunRejectsUnknownArgument(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")
	err := run([]string{"--bad"})
	if err == nil {
		t.Fatal("expected unknown argument error")
	}
	if !strings.Contains(err.Error(), "unknown argument") {
		t.Fatalf("unexpected error: %v", err)
	}
}

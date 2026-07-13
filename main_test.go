package main

import (
	"errors"
	"os"
	"os/user"
	"strings"
	"testing"
)

func TestUsageTextIncludesVersionFlag(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")
	if got := usageText(); !strings.Contains(got, "os-init --version") {
		t.Fatalf("usage text should mention --version, got %q", got)
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

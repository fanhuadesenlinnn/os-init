package main

import (
	"strings"
	"testing"
)

func TestUsageTextIncludesVersionFlag(t *testing.T) {
	t.Setenv("OS_INIT_LANG", "en_US")
	if got := usageText(); !strings.Contains(got, "os-init --version") {
		t.Fatalf("usage text should mention --version, got %q", got)
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

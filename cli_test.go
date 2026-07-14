package main

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestParseModuleFlags(t *testing.T) {
	flags, ids, err := parseModuleFlags("install", []string{
		"--yes", "--quiet", "--continue-on-error", "--timeout", "2m", "terminal-ncdu", "docker",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !flags.yes || !flags.quiet || !flags.continueOnError || flags.timeout.String() != "2m0s" {
		t.Fatalf("flags = %+v", flags)
	}
	if len(ids) != 2 || ids[0] != "terminal-ncdu" || ids[1] != "docker" {
		t.Fatalf("ids = %#v", ids)
	}
}

func TestMutatingModuleCommandRequiresYes(t *testing.T) {
	if err := runModuleCommand([]string{"install", "terminal-ncdu"}); err == nil {
		t.Fatal("expected --yes error")
	}
}

func TestNormalizeAllSelectionHonorsOperation(t *testing.T) {
	flags := moduleFlags{all: true, exclude: "terminal-ncdu"}
	ids := normalizeSelection(&flags, nil, platform.Target{GOOS: "darwin", Family: platform.FamilyDarwin}, modules.OperationUpdate)
	for _, id := range ids {
		if id == "terminal-ncdu" {
			t.Fatal("excluded module remained selected")
		}
	}
	if flags.all {
		t.Fatal("normalized selection should use explicit IDs")
	}
}

func TestModuleUsageDocumentsReports(t *testing.T) {
	usage := moduleUsageText()
	for _, want := range []string{"module test", "--report", "--junit", "--continue-on-error"} {
		if !containsText(usage, want) {
			t.Fatalf("usage does not contain %q", want)
		}
	}
}

func containsText(value, needle string) bool {
	for i := 0; i+len(needle) <= len(value); i++ {
		if value[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

package runtimecontext

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

func TestEnvironment(t *testing.T) {
	ctx := Context{Target: platform.Target{GOOS: "linux", ID: "ubuntu", Family: platform.FamilyDebian, Init: "systemd", Environment: platform.EnvironmentWSL, WSLVersion: 2, WSLg: true}, EffectiveUID: 1000, TargetUser: "alice", TargetHome: "/home/alice"}
	env := ctx.Environment()
	if env["HOME"] != "/home/alice" || env["OS_INIT_TARGET_FAMILY"] != "debian" || env["OS_INIT_TARGET_ENVIRONMENT"] != "wsl" || env["OS_INIT_TARGET_WSL_VERSION"] != "2" || env["OS_INIT_TARGET_WSLG"] != "true" || env["OS_INIT_TARGET_USER"] != "alice" || env["OS_INIT_CONFIG_LOADED"] != "1" {
		t.Fatalf("unexpected environment: %#v", env)
	}
}

func TestResolveTargetHome(t *testing.T) {
	for _, tc := range []struct {
		name, environmentHome, databaseHome, want string
	}{
		{name: "OrbStack Linux home", environmentHome: "/home/alice", databaseHome: "/mnt/mac/Users/alice", want: "/home/alice"},
		{name: "database fallback", databaseHome: "/home/alice", want: "/home/alice"},
		{name: "reject relative environment home", environmentHome: "relative/home", databaseHome: "/home/alice", want: "/home/alice"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := resolveTargetHome(tc.environmentHome, tc.databaseHome); got != tc.want {
				t.Fatalf("resolveTargetHome(%q, %q) = %q, want %q", tc.environmentHome, tc.databaseHome, got, tc.want)
			}
		})
	}
}

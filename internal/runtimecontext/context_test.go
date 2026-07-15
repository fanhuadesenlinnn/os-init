package runtimecontext_test

import (
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
	"github.com/fanhuadesenlinnn/os-init/internal/runtimecontext"
	"testing"
)

func TestEnvironment(t *testing.T) {
	ctx := runtimecontext.Context{Target: platform.Target{GOOS: "linux", ID: "ubuntu", Family: platform.FamilyDebian, Init: "systemd", Environment: platform.EnvironmentWSL, WSLVersion: 2, WSLg: true}, EffectiveUID: 1000, TargetUser: "alice", TargetHome: "/home/alice"}
	env := ctx.Environment()
	if env["OS_INIT_TARGET_FAMILY"] != "debian" || env["OS_INIT_TARGET_ENVIRONMENT"] != "wsl" || env["OS_INIT_TARGET_WSL_VERSION"] != "2" || env["OS_INIT_TARGET_WSLG"] != "true" || env["OS_INIT_TARGET_USER"] != "alice" || env["OS_INIT_CONFIG_LOADED"] != "1" {
		t.Fatalf("unexpected environment: %#v", env)
	}
}

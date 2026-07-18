// Package runtimecontext builds the immutable host and target-user context
// passed from the Go control plane to shell providers.
package runtimecontext

import (
	"os"
	"os/user"
	"path/filepath"
	"strconv"

	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

type Context struct {
	Target       platform.Target
	EffectiveUID int
	TargetUser   string
	TargetHome   string
}

func Detect() Context {
	ctx := Context{Target: platform.Detect(), EffectiveUID: os.Geteuid()}
	if current, err := user.Current(); err == nil {
		ctx.TargetUser = current.Username
		ctx.TargetHome = resolveTargetHome(os.Getenv("HOME"), current.HomeDir)
	}
	if ctx.EffectiveUID == 0 {
		ctx.TargetUser = "root"
		if root, err := user.LookupId("0"); err == nil {
			ctx.TargetHome = root.HomeDir
		}
	}
	if ctx.TargetHome == "" {
		ctx.TargetHome, _ = os.UserHomeDir()
	}
	return ctx
}

// resolveTargetHome prefers the effective shell home over the user database.
// Virtualized environments such as OrbStack may expose the macOS home through
// os/user while setting HOME to the Linux user's actual writable home.
func resolveTargetHome(environmentHome, databaseHome string) string {
	if filepath.IsAbs(environmentHome) {
		return environmentHome
	}
	return databaseHome
}

func (c Context) Environment() map[string]string {
	env := map[string]string{
		"OS_INIT_CONTEXT_VERSION":    "1",
		"OS_INIT_TARGET_GOOS":        c.Target.GOOS,
		"OS_INIT_TARGET_ID":          c.Target.ID,
		"OS_INIT_TARGET_FAMILY":      string(c.Target.Family),
		"OS_INIT_TARGET_INIT":        c.Target.Init,
		"OS_INIT_TARGET_ENVIRONMENT": string(c.Target.Environment),
		"OS_INIT_TARGET_WSL_VERSION": strconv.Itoa(c.Target.WSLVersion),
		"OS_INIT_TARGET_WSLG":        strconv.FormatBool(c.Target.WSLg),
		"OS_INIT_TARGET_USER":        c.TargetUser,
		"OS_INIT_TARGET_HOME":        c.TargetHome,
		"OS_INIT_EFFECTIVE_UID":      strconv.Itoa(c.EffectiveUID),
		"OS_INIT_CONFIG_LOADED":      "1",
	}
	if c.TargetHome != "" {
		env["HOME"] = c.TargetHome
	}
	return env
}

func Merge(base, extra map[string]string) map[string]string {
	merged := make(map[string]string, len(base)+len(extra))
	for key, value := range base {
		merged[key] = value
	}
	for key, value := range extra {
		merged[key] = value
	}
	return merged
}

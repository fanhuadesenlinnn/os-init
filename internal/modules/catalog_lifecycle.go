package modules

// directModuleLifecycles is deliberately exhaustive for modules declared as
// struct literals. Domain builders declare their lifecycle at construction.
var directModuleLifecycles = map[string][]Operation{
	"kernel-sysctl": fullLifecycle(), "kernel-limits": fullLifecycle(),
	"kernel-scheduler": fullLifecycle(), "kernel-autotune": fullLifecycle(),
	"network-ipv4": fullLifecycle(), "network-tune": fullLifecycle(),
	"shell-zsh": fullLifecycle(), "shell-direnv": fullLifecycle(),
	"git": fullLifecycle(), "shell-tmux": fullLifecycle(),
	"terminal-ncdu": fullLifecycle(), "yazi": fullLifecycle(),
	"mihomo": fullLifecycle(), "docker": fullLifecycle(), "mise": fullLifecycle(),
	"dev-build-deps": {OperationInstall, OperationUpdate},
	"mise-go":        fullLifecycle(), "mise-python": fullLifecycle(), "mise-node": fullLifecycle(),
	"neovim": fullLifecycle(),
}

func fullLifecycle() []Operation {
	return []Operation{OperationInstall, OperationUpdate, OperationUninstall}
}

func applyDeclaredLifecycle(module Module) Module {
	if (module.EntryKind != "" && module.EntryKind != EntryModule) || len(module.SupportedOperations) > 0 {
		return module
	}
	operations, ok := directModuleLifecycles[module.ID]
	if !ok {
		panic("module lifecycle is not explicitly declared: " + module.ID)
	}
	module.SupportedOperations = append([]Operation(nil), operations...)
	return module
}

package modules

var directModuleDeliveries = map[string]DeliveryPolicy{
	"kernel-sysctl":    {Default: DeliveryLinuxSystem},
	"kernel-limits":    {Default: DeliveryLinuxSystem},
	"kernel-scheduler": {Default: DeliveryLinuxSystem},
	"kernel-autotune":  {Default: DeliveryLinuxSystem},
	"network-ipv4":     {Default: DeliveryLinuxSystem},
	"network-tune":     {Default: DeliveryLinuxSystem},
	"shell-zsh":        {Default: DeliveryPortable},
	"shell-direnv":     {Default: DeliverySystemPackage},
	"shell-git":        {Default: DeliverySystemPackage},
	"shell-tmux":       {Default: DeliverySystemPackage, Arch: DeliveryArchNative},
	"terminal-ncdu":    {Default: DeliverySystemPackage},
	"yazi":             {Default: DeliveryPortable, Darwin: DeliveryDarwinNative, Arch: DeliveryArchNative},
	"mihomo":           {Default: DeliveryPortable},
	"docker":           {Default: DeliveryPortable, Arch: DeliveryArchNative},
	"dev-build-deps":   {Default: DeliverySystemPackage, Darwin: DeliveryDarwinNative, Arch: DeliveryArchNative},
	"mise":             {Default: DeliveryPortable, Darwin: DeliveryDarwinNative, Arch: DeliveryArchNative},
	"mise-go":          {Default: DeliveryUserRuntime},
	"mise-python":      {Default: DeliveryUserRuntime},
	"mise-node":        {Default: DeliveryUserRuntime},
	"neovim":           {Default: DeliveryPortable, Darwin: DeliveryDarwinNative, Arch: DeliveryArchNative},
}

func applyDeclaredDelivery(module Module) Module {
	if module.EntryKind != "" && module.EntryKind != EntryModule || module.Delivery.Default != "" {
		return module
	}
	policy, ok := directModuleDeliveries[module.ID]
	if !ok {
		panic("module delivery policy is not explicitly declared: " + module.ID)
	}
	module.Delivery = policy
	return module
}

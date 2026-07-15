package modules

func macOSCask(subsection, component, label, description, installedCheck string) Module {
	verify := Any(BrewCask(component), Path(installedCheck))
	affectedPaths := []string{installedCheck}
	if component == "karabiner-elements" {
		verify = All(verify,
			FileContains("$HOME/.config/karabiner/karabiner.json", `"key_code": "caps_lock"`),
			FileContains("$HOME/.config/karabiner/karabiner.json", `"key_code": "left_shift"`),
		)
		affectedPaths = append(affectedPaths, "$HOME/.config/karabiner/karabiner.json")
	}
	return Module{ID: "macos-" + component, Script: "macos/install.sh", Components: []string{component}, Label: label, Description: description, Category: "installation", Subsection: subsection, OS: "darwin", RunIndividually: true, Kind: KindInstallOnly, Activates: caskActivations(component), ManualSteps: caskManualSteps(component), Verify: verify, Phase: PhaseApplication, AffectedPaths: affectedPaths, SupportedOperations: fullLifecycle(), Delivery: DeliveryPolicy{Default: DeliveryDarwinNative}}
}

func macOSFormula(component, label, description, installedCmd string) Module {
	kind, activates, zshBlocks := KindInstallOnly, []string(nil), []string(nil)
	if component == "zoxide" {
		kind, activates, zshBlocks = KindShellIntegration, []string{ActivationZshrc}, []string{component}
	}
	module := Module{ID: "macos-cli-" + component, Script: "macos/cli.sh", Components: []string{component}, Label: label, Description: description, Category: "installation", Subsection: "macOS 命令行", OS: "darwin", RunIndividually: true, Kind: kind, Activates: activates, Verify: All(append([]Check{BrewFormula(component), Command(installedCmd)}, checksForZshBlocks(zshBlocks)...)...), Phase: PhaseApplication, SupportedOperations: fullLifecycle(), Delivery: DeliveryPolicy{Default: DeliveryDarwinNative}}
	return module
}

func checksForZshBlocks(names []string) []Check {
	checks := make([]Check, 0, len(names))
	for _, name := range names {
		checks = append(checks, ZshBlock(name))
	}
	return checks
}

func caskActivations(component string) []string {
	switch component {
	case "orbstack", "clash-party", "royal-tsx", "seafile-client", "bitwarden", "motrix-next", "karabiner-elements":
		return []string{ActivationManual}
	default:
		return nil
	}
}

func caskManualSteps(component string) []string {
	switch component {
	case "orbstack":
		return []string{"打开 OrbStack 完成首次初始化"}
	case "clash-party":
		return []string{"打开应用后导入自己的代理配置，不由 os-init 接管订阅和系统代理"}
	case "motrix-next":
		return []string{"Motrix Next 未签名；如 macOS 拒绝打开，请先核对上游说明再决定是否移除隔离属性"}
	case "karabiner-elements":
		return []string{"首次打开 Karabiner-Elements 后批准输入监控和系统扩展权限；键盘映射配置已自动部署"}
	case "royal-tsx":
		return []string{"打开 Royal TSX 后导入或创建自己的连接配置"}
	case "seafile-client":
		return []string{"打开 Seafile Client 后登录账号并选择同步目录"}
	case "bitwarden":
		return []string{"打开 Bitwarden 后登录账号或导入自己的密码库"}
	default:
		return nil
	}
}

package modules

func wslSystemdModule() Module {
	return Module{
		ID: "wsl-systemd", Script: "wsl/install.sh", Components: []string{"systemd"},
		Label: "WSL systemd", Description: "安全合并 /etc/wsl.conf 并启用 WSL2 systemd",
		Category: "installation", Subsection: "WSL 能力", OS: "linux", Requires: []string{"wsl2"},
		RunIndividually: true, Kind: KindSystemTuning, Activates: []string{ActivationManual},
		ManualSteps:   []string{"从 PowerShell 执行 wsl.exe --shutdown，重新进入发行版后再安装依赖 systemd 的服务"},
		AffectedPaths: []string{"/etc/wsl.conf"}, Privilege: PrivilegeSystem,
		PrivilegeReason: "写入 WSL 发行版级 /etc/wsl.conf", SupportedOperations: fullLifecycle(),
		Delivery: DeliveryPolicy{Default: DeliveryLinuxSystem},
		Verify:   FileContains("/etc/wsl.conf", "systemd=true"), Phase: PhaseBootstrap, Order: 5,
	}
}

func wslDoctorAction() Action {
	return Action{
		ID: "wsl-doctor", Script: "wsl/install.sh", Components: []string{"doctor"},
		Label: "WSL 环境诊断", Description: "检查 WSL 版本、systemd、WSLg、Docker 冲突和项目路径",
		Subsection: "WSL 操作", OS: "linux", Requires: []string{"wsl"}, Phase: PhaseAction,
	}
}

func wslDevelopmentPreset() Preset {
	return Preset{
		ID: "wsl-dev", Label: "WSL 开发环境",
		Description: "Shell、tmux、Git、终端工具、mise 开发运行时和 Neovim；不修改 WSL 内核、DNS或桌面",
		Subsection:  "WSL 套餐", OS: "linux", Requires: []string{"wsl"},
		Includes: []string{"shell-zsh", "shell-git", "shell-tmux", "terminal-ncdu", "yazi", "mise-dev-runtimes", "neovim"},
		Phase:    PhaseRuntime, Order: 5,
	}
}

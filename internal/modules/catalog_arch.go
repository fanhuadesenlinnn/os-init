package modules

func archLinuxModule(id, component, label, description string, kind ModuleKind, installedCmd string) Module {
	m := Module{ID: id, Script: "arch/install.sh", Components: []string{component}, Label: label, Description: description, Category: "installation", Subsection: "Arch Linux 能力", OS: "linux", Families: []string{"arch"}, RunIndividually: true, Kind: kind, Privilege: PrivilegeSystem, PrivilegeReason: "通过 pacman、systemd 或目标用户配置应用 Arch Linux 能力", SupportedOperations: []Operation{OperationInstall, OperationUpdate}, Delivery: DeliveryPolicy{Default: DeliveryArchNative}, Verify: Command(installedCmd), Phase: PhaseSystem}
	switch component {
	case "base":
		m.Phase, m.Order = PhaseBootstrap, 10
		m.AffectedPaths = []string{"pacman 最小基础工具包"}
	case "cli":
		m.Phase, m.Order = PhaseTerminal, 10
		m.DependsOn = []string{"arch-archlinuxcn"}
		m.AffectedPaths = []string{"pacman/archlinuxcn 现代 CLI 与排障工具包"}
	case "aur":
		m.Phase, m.Order = PhaseBootstrap, 30
		m.AffectedPaths = []string{"archlinuxcn 预编译 paru；保留已有 yay 作为兼容回退；普通用户可从 AUR 构建 paru"}
		m.DependsOn = []string{"arch-archlinuxcn"}
		m.Verify = Command("paru")
	case "dns":
		m.Phase, m.Order = PhaseNetwork, 10
		m.Requires = []string{"native-linux"}
		m.AffectedPaths = []string{"/etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf", "/etc/NetworkManager/conf.d/90-os-init-arch-dns.conf", "/etc/resolv.conf"}
		m.Verify = All(Path("/etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf"), SystemdService("systemd-resolved.service"))
	case "archlinuxcn":
		m.Phase, m.Order = PhaseRepository, 10
		m.AffectedPaths = []string{"/etc/pacman.conf", "archlinuxcn-keyring / archlinuxcn-mirrorlist-git"}
		m.Verify = FileContains("/etc/pacman.conf", "[archlinuxcn]")
	case "ops-toolkit":
		m.Phase, m.Order = PhaseApplication, 10
		m.AffectedPaths = []string{"$HOME/.local/share/ops-toolkit", "$HOME/.local/bin/ops 和脚本命令"}
		m.DependsOn = []string{"git"}
	case "fonts":
		m.Phase, m.Order = PhaseApplication, 30
		m.AffectedPaths = []string{"pacman/archlinuxcn 字体包", "$HOME/.config/fontconfig/fonts.conf", "$HOME/.config/gtk-{3,4}.0/settings.ini"}
		m.DependsOn = []string{"arch-archlinuxcn"}
	case "desktop":
		m.Phase, m.Order = PhaseDesktop, 10
		m.Requires = []string{"systemd", "native-linux"}
		m.AffectedPaths = []string{"pacman/AUR 桌面包（含 fcitx5-rime）", "/etc/systemd/system/display-manager.service", "$HOME/.config/hypr|waybar|rofi|dunst|yazi|btop|alacritty", "$HOME/.config/environment.d/fcitx5.conf", "$HOME/.config/fcitx5/profile", "$HOME/.local/share/fcitx5/rime", "$HOME/.local/bin"}
		m.Activates = []string{ActivationSystemd, ActivationManual}
		m.ManualSteps = []string{"安装后重新登录以加载完整 Wayland 输入法环境；Linux 默认使用 Ctrl+Space 切换，不自动接管单击 Shift"}
		m.DependsOn = []string{"arch-base", "arch-aur", "arch-archlinuxcn", "git", "arch-fonts"}
	}
	return m
}

func archMihomoVariant(module Module) Module {
	module.Script = "arch/install.sh"
	module.Components = []string{"mihomo"}
	module.RunIndividually = true
	module.DependsOn = []string{"arch-aur", "arch-archlinuxcn"}
	module.SupportedOperations = []Operation{OperationInstall, OperationUpdate}
	module.Delivery = DeliveryPolicy{Default: DeliveryArchNative}
	module.AffectedPaths = []string{"pacman/archlinuxcn: mihomo 和 metacubexd-bin", "/etc/mihomo", "/var/lib/mihomo", "mihomo.service", "$HOME/.bashrc|.zshrc"}
	module.DestructivePaths = nil
	return module
}

func archLinuxAction(id, component, label, description string) Action {
	return Action{ID: id, Script: "arch/install.sh", Components: []string{component}, Label: label, Description: description, Subsection: "Arch Linux 操作", OS: "linux", Families: []string{"arch"}, Requires: []string{"native-linux"}, Phase: PhaseAction}
}

func archPreset(id, label, description string, dependencies []string) Preset {
	return Preset{ID: id, Label: label, Description: description, Subsection: "Arch Linux 套餐", OS: "linux", Families: []string{"arch"}, Requires: []string{"native-linux"}, Includes: dependencies, Phase: PhaseSystem}
}

func orbStackArchPreset() Preset {
	return Preset{
		ID: "orbstack-arch-dev", Label: "OrbStack Arch 开发环境",
		Description: "Arch ARM 基础、可靠软件源、mise 用户运行时、Neovim、Docker、字体与 Zsh；保留 OrbStack 托管的 DNS 和内核",
		Subsection:  "OrbStack 套餐", OS: "linux", Families: []string{"arch"}, Requires: []string{"orbstack"},
		Includes: []string{"arch-base", "arch-cli", "arch-archlinuxcn", "arch-aur", "git", "arch-ops-toolkit", "mise-dev-runtimes", "neovim", "docker", "arch-fonts", "shell-zsh", "shell-tmux"},
		Phase:    PhaseSystem,
	}
}

func archDevDependencies() []string {
	return []string{"arch-base", "arch-cli", "arch-aur", "arch-archlinuxcn", "arch-dns", "git", "arch-ops-toolkit", "mise-dev-runtimes", "neovim", "docker", "arch-fonts", "shell-zsh", "shell-tmux", "mihomo"}
}

package modules

func archLinuxModule(id, component, label, description string, kind ModuleKind, installedCmd string) Module {
	m := Module{ID: id, Script: "arch/install.sh", Components: []string{component}, Label: label, Description: description, Category: "installation", Subsection: "Arch Linux 能力", OS: "linux", Families: []string{"arch"}, RunIndividually: true, Kind: kind, Privilege: PrivilegeSystem, PrivilegeReason: "通过 pacman、systemd 或目标用户配置应用 Arch Linux 能力", SupportedOperations: []Operation{OperationInstall, OperationUpdate}, Delivery: DeliveryPolicy{Default: DeliveryArchNative}, Verify: Command(installedCmd), Phase: PhaseSystem}
	switch component {
	case "base":
		m.AffectedPaths = []string{"pacman 基础工具包", "$HOME/.tmux.conf"}
	case "aur":
		m.AffectedPaths = []string{"archlinuxcn 预编译 paru / yay；普通用户的 AUR 构建回退"}
		m.DependsOn = []string{"arch-archlinuxcn"}
		m.Verify = All(Command("paru"), Command("yay"))
	case "dns":
		m.Requires = []string{"native-linux"}
		m.AffectedPaths = []string{"/etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf", "/etc/NetworkManager/conf.d/90-os-init-arch-dns.conf", "/etc/resolv.conf"}
		m.Verify = All(Path("/etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf"), SystemdService("systemd-resolved.service"))
	case "archlinuxcn":
		m.AffectedPaths = []string{"/etc/pacman.conf", "archlinuxcn-keyring / archlinuxcn-mirrorlist-git"}
		m.Verify = FileContains("/etc/pacman.conf", "[archlinuxcn]")
	case "git":
		m.AffectedPaths = []string{"pacman: git github-cli openssh", "$HOME/.gitconfig"}
		m.Verify = All(CommandRun("git", "--version"), CommandRun("gh", "--version"))
	case "ops-toolkit":
		m.AffectedPaths = []string{"$HOME/.local/share/ops-toolkit", "$HOME/.local/bin/ops 和脚本命令"}
		m.DependsOn = []string{"arch-git"}
	case "fonts":
		m.AffectedPaths = []string{"pacman/archlinuxcn 字体包", "$HOME/.config/fontconfig/fonts.conf", "$HOME/.config/gtk-{3,4}.0/settings.ini"}
		m.DependsOn = []string{"arch-archlinuxcn"}
	case "desktop":
		m.Requires = []string{"systemd", "native-linux"}
		m.AffectedPaths = []string{"pacman/AUR 桌面包（含 fcitx5-rime）", "/etc/systemd/system/display-manager.service", "$HOME/.config/hypr|waybar|rofi|dunst|yazi|btop|alacritty", "$HOME/.config/environment.d/fcitx5.conf", "$HOME/.config/fcitx5/profile", "$HOME/.local/share/fcitx5/rime", "$HOME/.local/bin"}
		m.Activates = []string{ActivationSystemd, ActivationManual}
		m.ManualSteps = []string{"安装后重新登录以加载完整 Wayland 输入法环境；Linux 默认使用 Ctrl+Space 切换，不自动接管单击 Shift"}
		m.DependsOn = []string{"arch-base", "arch-aur", "arch-archlinuxcn", "arch-git", "arch-fonts"}
	case "mihomo":
		m.AffectedPaths = []string{"pacman/archlinuxcn: mihomo 和 metacubexd-bin", "/etc/mihomo", "/var/lib/mihomo", "mihomo.service", "$HOME/.bashrc|.zshrc"}
		m.Requires = []string{"systemd", "native-linux"}
		m.Activates = []string{ActivationSystemd, ActivationShellProfile}
		m.DependsOn = []string{"arch-aur", "arch-archlinuxcn"}
		m.Verify = All(Command("mihomo"), Path("/etc/mihomo/config.yaml"), SystemdService("mihomo.service"), ShellBlock("proxy-env"))
		m.ManualSteps = []string{"替换订阅或提供 MIHOMO_CONFIG_SOURCE 后再启用服务"}
	}
	return m
}

func archLinuxAction(id, component, label, description string) Action {
	return Action{ID: id, Script: "arch/install.sh", Components: []string{component}, Label: label, Description: description, Subsection: "Arch Linux 操作", OS: "linux", Families: []string{"arch"}, Requires: []string{"native-linux"}, Phase: PhaseAction}
}

func archPreset(id, label, description string, dependencies []string) Preset {
	return Preset{ID: id, Label: label, Description: description, Subsection: "Arch Linux 套餐", OS: "linux", Families: []string{"arch"}, Requires: []string{"native-linux"}, Includes: dependencies, Phase: PhaseSystem}
}

func archDevDependencies() []string {
	return []string{"arch-base", "arch-aur", "arch-archlinuxcn", "arch-dns", "arch-git", "arch-ops-toolkit", "mise-dev-runtimes", "neovim", "docker", "arch-fonts", "shell-zsh", "arch-mihomo"}
}

# Arch Linux capabilities

This directory contains Arch-specific implementation details used by normal
OS Init modules. It is not a separate application or configuration system.

Cross-platform capabilities such as mise, Neovim, Docker, and Shell
remain in their top-level module directories. The `arch-dev` and
`arch-workstation` presets compose those modules through the Go planner.
Arch uses its own Mihomo capability to preserve the original package,
configuration validation, systemd adaptation, and MetaCubeXD behavior.

Arch-specific state is namespaced under `~/.local/state/os-init/arch`, while
configuration comes from the shared `~/.config/os-init/config.env` file.

Both root and normal users are supported. System changes run directly as root
or through sudo for a normal user. User configuration is written to the target
user's home. Both root and normal users install prebuilt paru/yay packages from
archlinuxcn with pacman. Only normal users may fall back to makepkg.

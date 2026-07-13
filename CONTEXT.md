# OS Init Context

OS Init is a China-ready initialization tool for macOS and Linux. It provides
one flat module menu, one configuration surface, and one execution planner.

## Product language

**Module**: A user-selectable unit of installation or configuration work.

**Arch Linux Capability**: A normal module available only on Arch-family
systems. It may combine pacman/systemd work with target-user configuration.

**Preset**: A dependency-only module that expands to ordinary modules. The
`arch-dev` and `arch-workstation` presets are convenience compositions; they
do not own separate implementations, configuration, or state.

**Target User**: The account receiving user configuration. A normal user is
the target when running normally; root is the target when OS Init runs as root.

**Strong Dependency**: A required module automatically added to the execution
plan. Presets are expressed entirely through strong dependencies.

**Soft Association**: A useful but optional related module shown before
execution and never installed implicitly.

**Unified Configuration**: `~/.config/os-init/config.env`, shared by every
platform and module. Generated files contain common settings plus settings for
the current platform.

## Relationships

- Arch-specific modules and cross-platform modules share the same menu,
  planner, confirmation page, executor, and summary.
- A normal Arch user runs system work through sudo and user work without sudo.
- In root mode, system work executes directly and user configuration targets
  `/root`; paru/yay use prebuilt archlinuxcn packages, while makepkg remains
  restricted to a normal build user.
- `arch-dev` composes base, repository, DNS, Git, Ops Toolkit, mise, Neovim,
  Docker, fonts, Shell, terminal styling, and Arch Mihomo/MetaCubeXD.
- `arch-workstation` adds the Hyprland desktop capability to `arch-dev`.
- Private accounts, subscriptions, and personal application data remain out of
  scope unless the user explicitly supplies them.

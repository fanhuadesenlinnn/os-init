# OS Init Context

OS Init is a China-ready initialization tool for macOS and Linux. It provides
one flat module menu, one configuration surface, and one execution planner.

## Product language

**Module**: A user-selectable unit of installation or configuration work.

**Arch Linux Capability**: A normal module available only on Arch-family
systems. It may combine pacman/systemd work with target-user configuration.

**Preset**: A dependency-only catalog entry that expands to ordinary modules. The
`arch-dev` and `arch-workstation` presets are convenience compositions; they
do not own separate implementations, configuration, or state.

**Action**: A one-shot command such as Arch diagnostics or detailed status.
Actions have no installed state and cannot be mixed with lifecycle modules.

**Lifecycle**: The install, update, and uninstall operations explicitly
supported by a module. Unsupported operations are rejected during planning.

**Provider**: The stable Shell execution boundary. Go supplies script,
operation, and components; platform-specific Shell code implements the change.
Provider protocol v2 also emits structured started/result events.

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
- TUI and headless commands share one per-module execution use case, including
  timeout, cancellation, verification, structured results, and state records.
- Go passes one versioned platform and target-user runtime context to Shell;
  standalone Shell detection remains only as a compatibility fallback.
- Presets are removed after dependency expansion, while actions remain
  separate from stateful lifecycle modules.
- A normal Arch user runs system work through sudo and user work without sudo.
- In root mode, system work executes directly and user configuration targets
  `/root`; paru/yay use prebuilt archlinuxcn packages, while makepkg remains
  restricted to a normal build user.
- WSL is an execution environment layered on top of the detected Linux family.
  WSL1 receives user-space development capabilities; WSL2 can additionally
  enable systemd and run a native, distribution-owned Docker Engine. Kernel,
  DNS, physical-network, proxy-service, display-manager, and full-desktop
  capabilities are excluded from WSL.
- `arch-dev` composes base, repository, DNS, Git, Ops Toolkit, mise-managed
  user runtimes, Neovim,
  Docker, fonts, Shell, terminal styling, and Arch Mihomo/MetaCubeXD.
- `arch-workstation` adds the Hyprland desktop capability to `arch-dev`.
- Private accounts, subscriptions, and personal application data remain out of
  scope unless the user explicitly supplies them.

# Arch workstation support uses capabilities and presets

The former nested Arch initializer has been absorbed into OS Init. Each useful
piece is now either an Arch-only capability or an existing cross-platform
module. Development and workstation flows are dependency presets.

## Decision

- Keep Arch-specific implementation in `modules/arch`.
- Reuse the shared mise, Neovim, Docker, and Shell implementations.
- Keep Mihomo as an Arch capability because its package-provided systemd unit,
  full configuration template, validation flow, and MetaCubeXD deployment are
  materially different from the generic Linux binary installer.
- Represent `arch-dev` and `arch-workstation` as planner dependencies.
- Install prebuilt paru/yay from archlinuxcn for root and normal users; only a
  normal user may fall back to AUR builds.
- Keep Arch diagnostics and detailed state as one-shot actions rather than
  modules with synthetic installed state.
- Do not maintain a separate menu, configuration file, executor, or summary.

## Consequences

- A capability installed alone and through a preset has identical behavior.
- Normal modules and Arch capabilities can run in one execution plan.
- There is no duplicated runtime or application installer to drift over time.

# Arch workstation support uses capabilities and presets

The former nested Arch initializer has been absorbed into OS Init. Each useful
piece is now either an Arch-only capability or an existing cross-platform
module. Development and workstation flows are dependency presets.

## Decision

- Keep Arch-specific implementation in `modules/arch`.
- Reuse the shared mise, Neovim, Docker, Mihomo, and Shell implementations.
- Represent `arch-dev` and `arch-workstation` as planner dependencies.
- Support root and normal users in every Arch entrypoint; safely skip AUR
  builds in root mode.
- Keep Arch diagnostics and detailed state actions as ordinary modules.
- Do not maintain a separate menu, configuration file, executor, or summary.

## Consequences

- A capability installed alone and through a preset has identical behavior.
- Normal modules and Arch capabilities can run in one execution plan.
- There is no duplicated runtime or application installer to drift over time.

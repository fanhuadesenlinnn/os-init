# ArchDevKit is an independent Arch Linux flow

ArchDevKit is accepted as an independent large module for minimal Arch Linux initialization, not as a set of normal OS Init modules. Its install menu, internal plan, state, diagnostics, and recovery remain owned by ArchDevKit; OS Init provides the entrypoint, platform detection, TUI integration, sudo handling, logging, timeout, summary, and release checks around it.

**Considered Options**

- Split ArchDevKit into ordinary OS Init modules such as shell, proxy, runtime, desktop, and docker.
- Merge ArchDevKit configuration and state directly into the normal OS Init module system.
- Keep ArchDevKit logic independent and only adapt the outer execution experience.

**Consequences**

- ArchDevKit install actions must not execute in the same batch as normal OS Init modules.
- ArchDevKit should appear first on Arch Linux because it is the main path from minimal Arch to a complete development environment.
- Shared code should focus on outer capabilities such as TUI, logging, sudo, timeout, configuration bridging, and release checks.

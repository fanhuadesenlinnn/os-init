# Unified configuration with current-system sections

OS Init uses `~/.config/os-init/config.env` across macOS, general Linux, and
Arch Linux. Default generation includes common settings and settings relevant
to the detected platform.

## Consequences

- Users edit one configuration file.
- Arch modules ignore unrelated keys in that shared file.
- Arch-specific execution state is namespaced at
  `~/.local/state/os-init/arch`, while shared modules keep their normal OS Init
  ownership and status records.
- Environment variables remain the final override.

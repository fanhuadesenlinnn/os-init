# Unified configuration with current-system sections

OS Init uses one user-facing configuration surface across macOS, general Linux, and ArchDevKit initialization. Default config creation should generate common settings plus sections relevant to the current system; on Arch Linux that includes common ArchDevKit settings, while macOS and non-Arch Linux should not be cluttered with ArchDevKit defaults.

**Considered Options**

- Keep separate user-facing configuration files for OS Init and ArchDevKit.
- Generate every possible setting for every platform in one large config file.
- Use one config file, but generate common settings plus current-system sections by default.

**Consequences**

- Users should usually edit `~/.config/os-init/config.env` instead of learning several config files.
- Default config should stay small and focus on commonly changed settings.
- ArchDevKit can still receive a generated temporary config behind its independent flow so its internal logic stays separate.

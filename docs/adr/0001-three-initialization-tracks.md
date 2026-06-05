# Three initialization tracks with different takeover depth

OS Init is accepted as one tool with three initialization tracks: macOS initialization, general Linux initialization, and ArchDevKit initialization. macOS is treated as both a development machine and a daily-use personal computer, so it should be lightly managed; general Linux is treated as server and development infrastructure, so it may manage system services and `/etc`; ArchDevKit is treated as the main path for turning a minimal Arch Linux installation into a complete development environment, so it may take deeper control while making that scope explicit.

**Considered Options**

- Treat every platform as the same kind of package installer.
- Split macOS, general Linux, and Arch Linux into separate tools.
- Keep one tool but give each platform track its own scope and takeover depth.

**Consequences**

- macOS GUI and account-based apps should usually be installed but not privately configured.
- General Linux modules may manage systemd, binaries, and system configuration when needed.
- ArchDevKit can remain a deeper full-system initializer without forcing that depth onto macOS or general Linux.

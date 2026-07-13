# Platform tracks have different takeover depth

OS Init remains one tool for macOS, general Linux, and Arch Linux. macOS is
lightly managed as a daily-use development machine. General Linux may manage
services and `/etc`. Arch Linux additionally exposes full workstation
capabilities, but those capabilities are normal modules rather than a nested
application.

## Consequences

- macOS applications are installed without taking over private configuration.
- Linux modules may manage systemd and system configuration when declared.
- Arch workstation features can be selected independently or through presets.
- Every track uses the same planner, confirmation, execution, and summary.

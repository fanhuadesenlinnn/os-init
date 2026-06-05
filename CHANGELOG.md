# Changelog

## Unreleased

### Fixed

- Do not abort ArchDevKit Docker or Mihomo installs when systemd cannot start the service immediately; keep the installed files and continue, with reboot/status follow-up guidance.

## v0.11.0 - 2026-06-05

### Added

- Add a module execution planner with strong dependency auto-fill, soft association hints, ArchDevKit batch isolation, and execution order preview.
- Generate a smaller platform-aware startup config for the current system while keeping the same `~/.config/os-init/config.env` path.
- Add Arch Linux-only os-init config keys that bridge into ArchDevKit defaults.
- Show post-install next steps in the summary page, including relogin, shell refresh, proxy config, and macOS app first-run reminders.
- Document the product language in `CONTEXT.md`.
- Record architecture decisions for initialization tracks, ArchDevKit independence, flat module selection, planned execution, and unified configuration.

### Changed

- Replace the flat ArchDevKit install-target list with a native os-init ArchDevKit wizard that follows the original ArchDevKit menu flow.
- Pass ArchDevKit wizard choices through a temporary override config so the embedded ArchDevKit installer keeps its own config and execution logic.
- Default ArchDevKit to the `dev` profile, with proxy enabled through Mihomo, auto-enabled service, and MetaCubeXD.
- Preserve the user's ArchDevKit config when os-init bridge overrides are present by appending bridge values after the existing config.

## v0.10.0 - 2026-06-05

### Added

- Embed ArchDevKit as an independent Arch Linux-only subsystem with its original modules, config, status, doctor, and profiles.
- Add an ArchDevKit top-level TUI menu that appears only on Arch-family Linux targets.
- Run embedded ArchDevKit self-checks in local `make check` and GitHub release workflow.

## v0.9.2 - 2026-06-05

### Changed

- Clean unused startup configuration keys and align defaults, examples, and shell whitelist.

### Fixed

- Classify Kylin Linux Advanced Server as a RedHat-family Linux distribution.

## v0.9.1 - 2026-06-05

### Fixed

- Fix shell module component normalization on macOS `/bin/bash` 3.2 with `set -u`.

## v0.9.0 - 2026-06-05

### Added

- Add platform-aware privilege metadata for modules.
- Add module execution timeout via `OS_INIT_SCRIPT_TIMEOUT`.
- Add Homebrew mirror environment support for API, bottles, brew/core remotes, artifacts, and PyPI index.
- Add ShellCheck and Bash syntax checks to the release workflow.
- Add registry/script drift tests for macOS Homebrew components.

### Changed

- Only prime sudo when selected modules need system privileges.
- Run Homebrew formula/cask installs without wrapping them in sudo.
- Run Homebrew commands through shared helpers so mirror and no-auto-update behavior is consistent.
- Move Git operations to non-interactive mode to avoid hidden credential prompts.
- Update GitHub Actions official actions to Node 24-compatible major versions.

### Fixed

- Prevent macOS Yazi and other Homebrew-only modules from asking for sudo before install.
- Prevent long-running module installs from hanging the TUI indefinitely.
- Add timeout handling to GitHub latest-version checks.
- Clean ShellCheck warnings across module scripts.

# Changelog

## v0.25.0 - 2026-07-13

### Changed

- Replace the Arch sing-box capability with Arch Mihomo using the former Arch configuration validation, systemd adaptation, complete template, and MetaCubeXD deployment behavior.
- Make Arch capability dependencies explicit so standalone AUR, Mihomo, fonts, Ops Toolkit, and desktop selections automatically include their prerequisites.
- Show the complete module composition in the Arch development and workstation preset descriptions.
- Install paru and yay from archlinuxcn with pacman for root and normal users; only normal users may fall back to makepkg.

### Removed

- Remove the Arch sing-box module, service, configuration, and template.

## v0.24.0 - 2026-07-13

### Added

- Add first-class Arch Linux capabilities for base tools, AUR helpers, archlinuxcn, DNS, Git/GitHub CLI, Ops Toolkit, fonts, sing-box, diagnostics, status, and the complete Hyprland desktop stack.
- Add `arch-dev` and `arch-workstation` presets that expand through normal planner dependencies.

### Changed

- Make the shared Arch mise module available to root and normal users, with only pacman operations elevated for normal users.
- Reuse the normal mise, Neovim, Docker, Shell, terminal-style, and Mihomo modules in Arch presets instead of maintaining duplicate implementations.
- Move Arch settings into `~/.config/os-init/config.env` and namespace Arch-specific execution state under `~/.local/state/os-init/arch`.
- Support Arch capabilities in root mode while safely skipping AUR builds that require a normal makepkg user.

### Removed

- Remove the nested ArchDevKit application, vendor wrapper, independent TUI wizard, isolated configuration, and mixed-batch restriction after absorbing its capabilities.

## v0.23.0 - 2026-07-13

### Added

- Add a root-only Arch Linux mise module that installs mise from pacman and manages Node.js 24, Python 3.13, and Go 1.24 under `/root`.
- Configure zsh and bash login/interactive shells with mise shims, full activation, and mainland China npm, pip, uv, and Go mirrors.

### Changed

- Extract the macOS mise runtime behavior into a shared macOS/Arch installer with official-source fallback and post-install verification.
- Hide the separate system Go module in Arch root mode so mise remains the single runtime-management path.
- Remove OS Init-managed nvm, fnm, pyenv, and asdf shell blocks when adopting mise.
- Preserve pre-existing mise packages, configuration, and runtime data during uninstall unless `PURGE_CONFIG=1` explicitly requests cleanup.

## v0.22.0 - 2026-07-13

### Added

- Support running OS Init directly as root on Linux, with `/root` as the target home and no dependency on the sudo package.
- Track ownership and original backups for system paths and packages managed by OS Init, so uninstall restores pre-existing resources and preserves unknown ones.
- Require an expected SHA-256 for executable downloads routed through `GITHUB_PROXY`, with an explicit legacy compatibility override.
- Show important affected paths and purge-only destructive paths on the confirmation page.

### Changed

- Hide and defensively block ArchDevKit in root mode because its AUR, desktop, and user-service flows require a normal user.
- Skip Docker group membership and relogin guidance when root is the target user.
- Cancel the active installer process group and wait for it to stop before cleaning temporary files or exiting the TUI.
- Preserve Neovim, Yazi, Byobu, Mihomo, Docker, Go, shell-tool, Homebrew cask/formula, and other pre-existing user/system resources during uninstall.
- Snapshot network queue, ring-buffer, sysctl, and MSS state before tuning and restore that snapshot on uninstall.

### Fixed

- Keep filtered navigation and selection inside visible results, accept pasted and Unicode search text, and make the first Space key select immediately.
- Distinguish installed status from current selection and report remaining module counts accurately.
- Report embedded-asset extraction failures instead of showing an empty successful summary.
- Bound captured installer output, handle oversized lines without deadlock, and write private logs with mode `0600`.
- Remove the PAM lines added by the limits module when reverting it.

## v0.13.0 - 2026-06-06

### Added

- Add package strategy checks for macOS Homebrew removal behavior and Arch pacman/AUR routing.

### Changed

- Align software installation sources by platform: macOS uses Homebrew, Arch Linux uses pacman with paru/yay AUR fallback, and Debian/RedHat-family Linux keeps binary installs for version-sensitive tools.
- Install Arch Docker components through pacman/AUR while keeping static Docker binaries for Debian/RedHat-family Linux.
- Remove offline package mode and keep the product positioned as an online initialization tool with GitHub proxy and configurable resource URLs.
- Update generated config comments, README, implementation plan, and release notes for the new package-source strategy.

### Fixed

- Detect Yazi installation status through package metadata instead of invoking the interactive `yazi` binary from the TUI.
- Avoid installing Homebrew during uninstall/status-style package removal paths.

## v0.12.0 - 2026-06-05

### Added

- Add a Terminal Style module with rich/simple/plain Starship templates and shell aliases for local, SSH, and TTY sessions.

### Changed

- Let starship work with bash and zsh without forcing zsh as a dependency.
- Default ArchDevKit shell initialization to Starship terminal styling while keeping Powerlevel10k available through configuration.

## v0.11.1 - 2026-06-05

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

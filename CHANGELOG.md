# Changelog

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

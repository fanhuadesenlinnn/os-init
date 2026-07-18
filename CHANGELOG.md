# Changelog

## v1.3.9 - 2026-07-18

### 修复

- TUI 提权验证优先执行具体的 `sudo -n true`，避免 OrbStack 等环境已授予命令级 `NOPASSWD` 时仍因 `sudo -v` 索要不存在的 Linux 密码而无法继续。

## v1.3.8 - 2026-07-18

### 修复

- 隔离 mise 运行时的安装后验证环境，避免验证器从 OrbStack 宿主机挂载目录启动时误读 macOS 配置并将成功安装误报为失败。

## v1.3.7 - 2026-07-18

### 修复

- 固定 mise 子命令在 Linux 目标 HOME 中运行并限制配置向上扫描，避免从 OrbStack 宿主机挂载目录启动时误读 macOS 的 `.config/mise/config.toml`。

## v1.3.6 - 2026-07-18

### 修复

- 显式设置 mise 的 Linux 目标配置目录，避免 OrbStack 中 mise 仍通过用户数据库扫描 `/mnt/mac/Users/.../.config/mise`。

## v1.3.5 - 2026-07-18

### 修复

- OrbStack 中优先使用 Linux 会话的 `HOME` 作为目标用户目录，并显式传给安装 Provider，避免 `os/user` 返回 macOS 挂载目录。
- 隔离 mise 的全局配置和数据目录，忽略继承的宿主机配置与信任路径，避免 Linux 运行时安装误读 `/mnt/mac/Users/...`。
- 将 Ops Toolkit 的用户命令目录加入 Shell `PATH`，并直接验证命令入口文件，避免安装成功后因控制进程尚未刷新 `PATH` 而误报失败。

## v1.3.3 - 2026-07-17

### 修复

- 补充通用安装模块缺失的命令检查函数，避免 Git 软件包安装成功后因 `require_cmd` 未定义而中止配置。
- 验证 mise 管理的 npm 和 Corepack 时临时加入对应 Node.js 目录，避免非交互安装环境尚未激活 mise 时误报找不到 `node`。
- 为共享命令检查和 mise Node.js 启动器路径增加回归测试。

## v1.3.2 - 2026-07-17

### 调整

- Arch 软件仓库不提供 mise 时，改用 `curl https://mise.run | sh` 对应的官方安装脚本，并继续支持 `MISE_INSTALL_PATH` 和 `MISE_VERSION`。
- 移除不再使用的 mise GitHub Release 下载地址、校验值和手动架构映射配置。

### 修复

- 避免安装 mise 前必须查询 `jdx/mise` 最新 GitHub Release，解决该查询失败时无法安装的问题。

## v1.3.1 - 2026-07-17

### 修复

- 模块菜单只在分类实际包含可选模块时显示“系统优化”或“软件安装”标题，避免单一分类和空目录场景出现空标题及多余间距。
- 软件安装子分组继续按实际内容生成，不显示当前系统不适用的空分组。
- 发布说明改用中文分类和中文内容，并补正 v1.3.0 的发布说明。

## v1.3.0 - 2026-07-17

### 新增

- 新增独立的 `arch-cli` 能力，用于安装现代命令行和诊断工具，不再把它们隐藏在 Arch 基础模块中。
- 为 TUI 和无界面执行统一批次级软件源刷新与依赖失败跳过策略。
- 增加旧版 OS Init 生成的 tmux 配置迁移逻辑。

### 调整

- 将 `arch-base` 收敛为官方仓库中的最小下载、解压和诊断工具；Git、tmux、编译依赖与现代 CLI 改由独立模块管理。
- 使用跨平台稳定模块 ID `git` 和跨 Linux 稳定模块 ID `mihomo`，同时把旧 ID `shell-git`、`arch-git`、`arch-mihomo` 作为兼容别名。
- 仅主动管理 paru；系统已有 yay 时只将其保留为回退，不再重复安装两个 AUR Helper。
- 将 `modules/config/defaults.env` 作为配置生成、Go 运行时加载和 Arch Provider 的唯一默认值来源。
- 将执行顺序拆分为软件源、引导、网络、运行时、服务、桌面等阶段；卸载时反转依赖顺序，并拒绝存在依赖环的计划。
- 将 macOS Cask 与 Formula 目录改为数据驱动声明。

### 修复

- Mihomo 代理、控制接口与 DNS 默认只监听本机回环地址；未明确启用局域网访问时拒绝通配监听，公开控制接口时必须设置密钥。
- 交互和无界面执行在模块失败后继续运行无关模块，只跳过依赖已失败模块的后续模块。
- 每个执行批次只刷新一次软件包元数据，不再为每个模块重复刷新软件源。
- 旧版本缺少足够所有权记录时，迁移过程保留原有软件包，避免不安全卸载。

## v1.2.0 - 2026-07-16

### Added

- Detect OrbStack Linux machines as a distinct environment and provide an OrbStack Arch development preset that preserves host-managed DNS and kernel behavior.
- Prioritize official Taiwan Arch Linux ARM mirrors for mainland-China ARM installations while preserving the original GeoIP mirror as a fallback.

### Changed

- Generate one user configuration file containing only settings used by the detected platform, and keep advanced implementation defaults internal.
- Pass the language selected in the startup UI directly to configuration generation so new files consistently use matching Chinese or English comments and `OS_INIT_LANG` values.
- Remove the separate full configuration example and the optional `/etc/os-init/config.env` layer so `~/.config/os-init/config.env` is the single user-facing configuration source.
- Use `MIHOMO_AUTO_ENABLE_SERVICE` consistently on Arch and other Linux families while accepting the former Arch-only key during migration.
- Retry transient pacman downloads while reusing the package cache, and perform a full Arch upgrade before shared package resolution to avoid partial upgrades.
- Update and populate official Arch/Arch Linux ARM keyrings before installing the archlinuxcn keyring.
- Use Chromium instead of the unavailable Google Chrome package by default on Arch Linux ARM desktops.

### Fixed

- Make `GITHUB_PROXY` immediately apply to OS Init-managed downloads, clones, updates, and child Git processes without persisting proxied repository origins.
- Remove the conflicting global GitHub HTTPS-to-SSH rewrite and the redundant Arch proxy enable switch.
- Namespace OS Init's mise runtime selections so they no longer collide with mise's own `MISE_*_VERSION` environment variables, while migrating legacy config keys during loading.
- Support prefix, `{url}`, and `{url_encoded}` GitHub proxy formats and make latest-release detection work when proxies do not preserve GitHub's HEAD redirect.
- Normalize trailing slashes in GitHub proxy prefixes so equivalent forms produce identical download and Git URLs.
- Use `https://hubproxy.babadafafafafa.cn` as the generated and built-in default GitHub proxy, while allowing an empty value to disable it.
- Configure Docker's `registry-mirrors` by default with `https://hubproxy.babadafafafafa.cn`; users can provide comma-separated alternatives or leave it empty.
- Fall back to the official ARM64 user binary when the current Arch repository does not provide mise.
- Stop dependent TUI modules after an upstream failure instead of producing cascading mise runtime errors.
- Do not append the same ANSI-formatted provider failure twice to module logs.
- Distinguish command failures from missing sudo authorization in package-manager diagnostics.
- Refuse to continue archlinuxcn setup when its signing keyring was not installed successfully.

## v1.1.0 - 2026-07-15

### Added

- Split the cross-platform mise capability into mise core plus user-level Go, Python, and Node.js runtime modules, with a combined development-runtime preset.
- Add native development build prerequisites for mise-managed Python without installing a system Python.
- Deploy the managed Karabiner-Elements key mappings automatically on macOS while backing up and restoring any pre-existing configuration across uninstall.
- Safely merge the Arch Fcitx5/Rime configuration without replacing learned dictionaries, sync state, or private phrases, and reload the active input method when possible.
- Detect WSL1, WSL2, and WSLg; add safe systemd configuration, WSL diagnostics, and a user-space development preset.

### Changed

- Preserve full mise development runtimes for both normal users and root while isolating them in each target user's HOME.
- Use Homebrew for the mise binary on macOS, pacman on Arch, and a portable user binary on Debian/RedHat.
- Align the default mise-managed Go series with the repository's Go 1.26 toolchain.
- Filter kernel, DNS, physical-network, proxy-service, display-manager, and full-desktop capabilities from WSL; use only a distribution-owned native Docker Engine on WSL2.

### Fixed

- Make archlinuxcn inherit pacman's global signature policy, migrate legacy repository-level `SigLevel` entries, and retry repository synchronization with USTC, TUNA, and the official server.

### Removed

- Remove the standalone system Go module, `/usr/local/go` management, system Go packages, and the legacy `GO_*` download settings.

## v1.0.0 - 2026-07-14

### Added

- Add stable non-interactive `module list`, `plan`, `install`, `update`, `uninstall`, `verify`, and `test` commands for unattended provisioning and CI.
- Add per-module JSON and JUnit reports, private logs, configurable timeouts, explicit `--yes` approval, quiet output, dependency planning, and continue-on-error execution.
- Add declarative GitHub automation scope and lifecycle metadata to the machine-readable module catalog.
- Add a pure GitHub-hosted module validation workflow that dynamically tests modules one at a time on fresh Ubuntu and macOS VMs and Ubuntu, Debian, Fedora, Rocky, Arch, and Manjaro containers.
- Add a reusable live-system verification package and non-interactive CLI contract tests.

### Changed

- Treat a non-interactive module as successful only when its provider exits successfully and its declarative post-operation verification reaches the expected state.
- Preserve and verify the pre-test installed state after lifecycle uninstall, so pre-existing resources are not mistaken for uninstall failures.
- Classify disruptive network and graphical desktop checks as explicit manual coverage instead of claiming ordinary containers validated them.

## v0.28.0 - 2026-07-14

### Changed

- Align generated, embedded, and example Mihomo network defaults on `0.0.0.0` listeners while preserving `MIHOMO_ALLOW_LAN=0` and an empty default controller secret.
- Restrict Go and Shell configuration loading to declared OS Init keys.
- Validate shared script components against the Go registry and reject unknown component names before execution.
- Run the complete local check target on Ubuntu and macOS CI, with an additional Arch Linux provider contract run.
- Run native contracts across Ubuntu, Debian, Fedora, Rocky, Arch, and Manjaro, including Linux ARM64 and both macOS architectures.
- Add scheduled root/non-root package lifecycle, Linux system-file lifecycle, and macOS Homebrew lifecycle tests.
- Expand `--help` with the interactive workflow, real options, examples, configuration precedence, common environment variables, logs, and privilege behavior.
- Publish releases only from existing `v*` tags and generate release notes from the matching changelog section.

### Fixed

- Keep the generated mise Go download mirror consistent with the embedded and example defaults.
- Make `make check` include mise and release-strategy regression tests and remain usable with the macOS system Bash.
- Ensure root-mode privileged commands bypass same-named logging functions such as `install`.
- Sync the Arch package database before deciding whether a package requires AUR, and use EPEL as a RedHat-family fallback for missing packages.
- Make the terminal-tool update operation actually refresh `ncdu` through the platform package manager.

## v0.27.2 - 2026-07-14

### Fixed

- Replace the incompatible mise Go mirror default with `https://dl.google.com/go`, which provides the archive checksum sidecars required by mise.
- Normalize legacy `https://golang.google.cn/dl/` configuration before the first runtime installation attempt.
- Make the official-source retry override inherited Node and Go mirror environment variables for the actual `mise use` command.

### Changed

- Add an executable mise mirror fallback test covering custom mirror failure, official retry, and legacy Go mirror normalization.

## v0.27.1 - 2026-07-14

### Fixed

- Restore the Arch provider preflight check after removing the legacy Arch runner, preventing all Arch capability executions from failing with `preflight_install: command not found`.
- Normalize the Go control-plane `mihomo` component to the Shell provider's `proxy` module.
- Remove the Arch status action's stale dependency on the deleted `modules_for_target` planner function.

### Changed

- Add executable Arch provider contract tests for entrypoint loading, Go-to-Shell component dispatch, and doctor/status actions.
- Run validation on pull requests and main-branch pushes, and support controlled `release/v*` branches for automated tagged releases.

## v0.27.0 - 2026-07-13

### Changed

- Fold Powerlevel10k, zsh-autosuggestions, and zsh-syntax-highlighting into the single Zsh + Oh My Zsh lifecycle and menu entry.

### Removed

- Remove Starship and the Starship-based terminal-style module, templates, configuration, update tracking, and preset dependencies.
- Clean up shell blocks, templates, and installations owned by the former Starship modules when the Zsh module next runs.

## v0.26.0 - 2026-07-13

### Changed

- Separate stateful modules, dependency-only presets, and one-shot actions while preserving the flat TUI selection surface.
- Declare supported lifecycle operations per module and reject unsupported or mixed action/module plans before execution.
- Replace the expanding installed-status field matrix with composable `All`/`Any` verification checks.
- Use explicit, language-independent execution phases and order hints instead of localized subsection names and module-ID ranking.
- Move root and target-user module resolution out of the TUI and into the catalog layer.
- Route every Shell invocation through a stable provider protocol carrying script, operation, and components.
- Make Go the only Arch control plane by removing the duplicate Arch menu, planner, confirmation, runner, recovery, summary, and preset acknowledgement script.
- Align Arch configuration precedence with the shared defaults, system/user config, environment, and runtime override contract.

### Fixed

- Prevent Arch capabilities from presenting an uninstall path that could only fail inside the Shell implementation.
- Keep Arch configuration-fingerprint state updated when capabilities execute through the unified provider.

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

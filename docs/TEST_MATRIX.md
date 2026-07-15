# Test Matrix

OS Init uses three test levels. Passing a lower level must not be described as
a successful real installation.

## Non-interactive module acceptance

The public `os-init module` command is the single automation entry point. It
uses the same target catalog, dependency planner, embedded provider, timeout,
logs and declarative `Verify` expressions as the product. Mutating commands
require `--yes`; JSON and JUnit reports preserve individual module failures.

The `Module Install Validation` workflow is scheduled weekly and can be
manually dispatched for `all` modules or one stable module ID. Each module gets
its own fresh GitHub-hosted VM or distribution container. Matrix jobs use
`fail-fast: false`, and every job uploads its report and private provider logs.

Automation policies exported by `module list --format json` mean:

| Scope | Meaning |
| --- | --- |
| `container` | Full lifecycle is safe in a fresh distribution container and also runs on native Ubuntu/macOS where available. |
| `hosted` | Requires a disposable native GitHub-hosted Ubuntu/macOS VM; this includes macOS-specific formula and cask modules. |
| `manual` | Would disrupt runner networking or requires a graphical/hardware session; catalogued but not falsely reported as automated. |

| Lifecycle | Meaning |
| --- | --- |
| `full` | Install, verify, reinstall, update, uninstall, and verify restoration of the pre-test state. |
| `install-only` | Provider installation smoke test; runtime activation requires external configuration or hardware. |
| `plan-only` | Dependency-only preset with no provider of its own. |

## Required on pull requests and main

| Platform | Architecture | Coverage |
| --- | --- | --- |
| macOS 15 | Apple Silicon | Go tests, shell syntax, ShellCheck, strategy and release contracts |
| macOS 15 | Intel | Same checks executed natively on Intel |
| Ubuntu 24.04 | AMD64 and ARM64 | Native binary execution, platform detection, package-manager routing, provider rejection contracts |
| Debian 12 | AMD64 | Native binary and Debian-family contracts |
| Fedora 42 | AMD64 | Native binary and RedHat-family contracts |
| Rocky Linux 9 | AMD64 | Native binary and RedHat-family contracts |
| Arch Linux | AMD64 | Native binary, Arch-family and Arch provider contracts |
| Manjaro | AMD64 | Native binary and Arch-family contracts |

OrbStack Arch Linux ARM64 is additionally checked in a disposable local VM
when platform boundaries, pacman routing, mirrors, DNS handling, or the mise
installation strategy change. The check must confirm `environment=orbstack`,
hide host-managed DNS/kernel/desktop modules, and preserve the OrbStack-owned
`/etc/resolv.conf` target.

The release build is blocked until all required jobs pass. Release packages are
also built for Linux and macOS on AMD64 and ARM64.

## Scheduled and manually dispatched integration

The `System Integration` workflow runs in disposable environments:

- Ubuntu, Debian, Fedora, Rocky, Arch, and Manjaro install `ncdu`, repeat the
  installation, run the update route, uninstall it, and verify ownership state.
- The same lifecycle runs once as root and once as a normal passwordless-sudo
  user.
- Linux containers apply, repeat, and remove the limits, scheduler, and IPv4
  system-file modules.
- macOS Apple Silicon and Intel runners install, repeat, update, and uninstall a
  Homebrew formula through the OS Init provider.

These jobs intentionally run on a schedule or by manual dispatch because they
modify package databases and depend on external repositories.

In addition, `.github/workflows/module-install.yml` dynamically discovers the
catalog instead of maintaining a second hard-coded module list:

- Ubuntu 24.04 runs each eligible module in a fresh GitHub-hosted VM.
- macOS 15 runs each eligible module independently on Apple Silicon and Intel.
- Ubuntu, Debian, Fedora, Rocky, Arch, and Manjaro run every container-safe
  module in a fresh family-native container.
- machine-readable catalog, JSON results, JUnit results, and logs are retained
  as workflow artifacts.

## Dedicated environment tests

The following cannot be made reliable in an ordinary unprivileged container and
must run in a disposable VM or hardware lab before a release that changes the
corresponding module:

- sysctl, network queue/MSS and autotune effects on a booted Linux kernel;
- Docker and Mihomo service enablement, restart and reboot persistence under a
  real systemd PID 1;
- Hyprland, SDDM, GPU, virtual-machine and input-method behavior in a graphical
  Arch/Manjaro session;
- package downloads, Docker service behavior and host integration in an
  OrbStack Arch Linux ARM64 machine;
- launching and completing first-run setup for macOS GUI applications;
- destructive purge options against prepared user data snapshots.

The GitHub-only workflow explicitly marks network queue/MSS tuning, Arch DNS,
and the Arch graphical desktop as manual coverage. No user-owned runner or VM
is required for the automated levels above.

Results from this level should be attached to the release or pull request. The
regular workflows do not claim these behaviors were exercised.

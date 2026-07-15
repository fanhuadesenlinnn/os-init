#!/usr/bin/env bash
# Test doubles override functions loaded dynamically from split library files.
# ShellCheck renamed this indirect-test-double diagnostic across supported releases.
# shellcheck disable=SC2016,SC2034,SC2317,SC2329
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/os-init-lib-home.XXXXXX")"
TEST_BIN="$(mktemp -d "${TMPDIR:-/tmp}/os-init-lib-bin.XXXXXX")"

cleanup() {
    rm -rf "$TEST_HOME" "$TEST_BIN"
}
trap cleanup EXIT

export HOME="$TEST_HOME"
export REPO_DIR="$ROOT_DIR/modules"
export PATH="$TEST_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

# shellcheck disable=SC1091
source "$ROOT_DIR/modules/lib.sh"

fail() {
    printf 'test-lib-strategy: %s\n' "$*" >&2
    exit 1
}

assert_call() {
    local expected="$1" call
    for call in "${calls[@]}"; do
        [[ "$call" == "$expected" ]] && return 0
    done
    fail "missing call: $expected; got: ${calls[*]:-<none>}"
}

create_fake_command() {
    local name="$1"
    printf '#!/usr/bin/env sh\nexit 0\n' > "$TEST_BIN/$name"
    chmod +x "$TEST_BIN/$name"
}

test_macos_pkg_remove_does_not_install_homebrew() (
    OS=macos
    OS_FAMILY=macos
    local -a calls=()

    brew_uninstall() {
        calls+=("brew_uninstall:$*")
    }

    pkg_remove imaginary-formula
    [[ ${#calls[@]} -eq 0 ]] || fail "pkg_remove should not call brew_uninstall when brew is absent"
)

test_pkg_install_uses_arch_strategy() (
    OS=linux
    OS_FAMILY=arch
    local -a calls=()

    arch_install_packages_or_aur() {
        calls+=("arch_install:$*")
    }

    pkg_install neovim yazi
    assert_call "arch_install:neovim yazi"
)

test_redhat_install_retries_with_epel() (
    OS=linux
    OS_FAMILY=redhat
    local attempt=0
    local -a calls=()
    create_fake_command dnf

    sudo_env() {
        calls+=("sudo:$*")
        if [[ "$*" == "dnf install -y ncdu" ]]; then
            attempt=$((attempt + 1))
            [[ "$attempt" -gt 1 ]]
            return
        fi
        return 0
    }
    enable_redhat_epel() { calls+=("epel:$1"); }

    pkg_install ncdu
    [[ "$attempt" == 2 ]] || fail "RedHat package was not retried after EPEL"
    assert_call "epel:dnf"
)

test_arch_packages_split_between_pacman_and_aur() (
    OS=linux
    OS_FAMILY=arch
    local -a calls=()

    arch_package_installed() {
        [[ "$1" == "already-there" ]]
    }
    arch_package_available() {
        [[ "$1" == "repo-tool" ]]
    }
    arch_pacman_install() {
        calls+=("pacman:$*")
    }
    ensure_arch_aur_helpers() {
        calls+=("ensure-aur")
    }
    arch_aur_helper_command() {
        printf 'paru\n'
    }
    arch_install_with_current_aur_helper() {
        calls+=("aur:$*")
    }
    arch_install_aur_via_makepkg() {
        calls+=("makepkg:$*")
    }

    arch_install_packages_or_aur already-there repo-tool aur-tool
    assert_call "pacman:repo-tool"
    assert_call "ensure-aur"
    assert_call "aur:aur-tool"
)

test_arch_repository_lookup_syncs_database_first() (
    OS=linux
    OS_FAMILY=arch
    _ARCH_PACKAGE_DATABASE_SYNCED=false
    local -a calls=()
    sudo_env() { calls+=("sudo:$*"); }
    pacman() { calls+=("pacman:$*"); return 0; }

    arch_package_available ncdu
    arch_package_available tmux
    assert_call "sudo:pacman -Syu --noconfirm"
    [[ "${calls[0]}" == "sudo:pacman -Syu --noconfirm" ]] || fail "Arch lookup queried before database sync"
    [[ "$(printf '%s\n' "${calls[@]}" | grep -Fc 'sudo:pacman -Syu --noconfirm')" == 1 ]] || fail "Arch database synced more than once"
)

test_arch_pacman_retries_and_prioritizes_arm_mirrors() (
    OS=linux
    OS_FAMILY=arch
    OS_INIT_REGION=cn
    PACMAN_RETRY_ATTEMPTS=3
    _ARCHLINUXARM_MIRRORS_PREPARED=false
    local mirror_file="$TEST_HOME/arm-mirrorlist"
    ARCHLINUXARM_MIRRORLIST_FILE="$mirror_file"
    ARCHLINUXARM_MIRRORS="http://tw.example/\$arch/\$repo,http://tw2.example/\$arch/\$repo"
    local pacman_attempts=0

    printf 'Server = http://original.example/%s/%s\n' '$arch' '$repo' > "$mirror_file"
    uname() { printf 'aarch64\n'; }
    sudo_env() {
        if [[ "$1" == install ]]; then
            command "$@"
            return
        fi
        pacman_attempts=$((pacman_attempts + 1))
        [[ "$pacman_attempts" -ge 3 ]]
    }

    arch_run_pacman -Sy --noconfirm
    [[ "$pacman_attempts" -eq 3 ]] || fail "pacman retry count = $pacman_attempts, want 3"
    [[ "$(sed -n '2p' "$mirror_file")" == "Server = http://tw.example/\$arch/\$repo" ]] || \
        fail "Arch Linux ARM preferred mirror was not placed first"
    grep -Fq "Server = http://original.example/\$arch/\$repo" "$mirror_file" || \
        fail "original Arch Linux ARM mirror was not preserved"
)

test_arch_helper_bootstrap_prefers_paru_and_adds_yay() (
    OS=linux
    OS_FAMILY=arch
    local -a calls=()

    rm -f "$TEST_BIN/paru" "$TEST_BIN/yay"

    arch_package_available() {
        return 1
    }
    arch_pacman_install() {
        calls+=("pacman:$*")
    }
    arch_install_aur_via_makepkg() {
        calls+=("makepkg:$1")
        create_fake_command "$1"
    }
    arch_install_with_current_aur_helper() {
        calls+=("aur:$*")
        local package
        for package in "$@"; do
            create_fake_command "$package"
        done
    }

    ensure_arch_aur_helpers
    command -v paru >/dev/null || fail "paru should be available after helper bootstrap"
    command -v yay >/dev/null || fail "yay should be available after companion install"
    assert_call "makepkg:paru"
    assert_call "aur:yay"
)

test_owned_path_restores_preexisting_content() (
    local state_dir="$TEST_HOME/system-state"
    local target="$TEST_HOME/owned-target"
    OS_INIT_SYSTEM_STATE_DIR="$state_dir"
    sudo() { command "$@"; }

    printf 'before\n' > "$target"
    os_init_prepare_owned_path test-resource "$target"
    printf 'after\n' > "$target"
    os_init_restore_owned_path test-resource "$target"
    [[ "$(cat "$target")" == "before" ]] || fail "owned path did not restore original content"
)

test_unknown_owned_path_is_preserved() (
    local state_dir="$TEST_HOME/unknown-state"
    local target="$TEST_HOME/unknown-target"
    OS_INIT_SYSTEM_STATE_DIR="$state_dir"
    sudo() { command "$@"; }

    printf 'user-data\n' > "$target"
    os_init_restore_owned_path missing-resource "$target" >/dev/null 2>&1 && fail "unknown path should not report removal"
    [[ "$(cat "$target")" == "user-data" ]] || fail "unknown path was modified"
)

test_verified_download_rejects_unchecked_proxy() (
    local source_file="$TEST_HOME/download-source"
    local target="$TEST_HOME/download-target"
    printf 'payload\n' > "$source_file"
    GITHUB_PROXY="https://proxy.invalid/"
    OS_INIT_ALLOW_UNVERIFIED_PROXY=0
    download_file() { cp "$source_file" "$2"; }

    if (download_file_verified "https://github.com/example/tool/releases/download/v1/tool" "$target" "" >/dev/null 2>&1); then
        fail "unchecked proxied executable download should be rejected"
    fi
    [[ ! -e "$target" ]] || fail "rejected download should not create a target"
)

test_verified_download_accepts_expected_digest() (
    local source_file="$TEST_HOME/digest-source"
    local target="$TEST_HOME/digest-target"
    local digest
    printf 'payload\n' > "$source_file"
    GITHUB_PROXY="https://proxy.invalid/"
    OS_INIT_ALLOW_UNVERIFIED_PROXY=0
    download_file() { cp "$source_file" "$2"; }
    digest="$(sha256_file "$source_file")"

    download_file_verified "https://github.com/example/tool/releases/download/v1/tool" "$target" "$digest"
    cmp -s "$source_file" "$target" || fail "verified payload was not preserved"
)

test_verified_download_rejects_wrong_digest() (
    local source_file="$TEST_HOME/wrong-digest-source"
    local target="$TEST_HOME/wrong-digest-target"
    printf 'tampered\n' > "$source_file"
    GITHUB_PROXY="https://proxy.invalid/"
    OS_INIT_ALLOW_UNVERIFIED_PROXY=0
    download_file() { cp "$source_file" "$2"; }

    if (download_file_verified "https://github.com/example/tool/releases/download/v1/tool" "$target" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >/dev/null 2>&1); then
        fail "wrong executable digest should be rejected"
    fi
    [[ ! -e "$target" ]] || fail "digest mismatch should remove the downloaded target"
)

test_root_sudo_wrapper_runs_without_sudo_binary() (
    local target="$TEST_HOME/root-sudo-wrapper"
    id() {
        if [[ "${1:-}" == "-u" ]]; then
            printf '0\n'
            return
        fi
        command id "$@"
    }

    sudo -n -E sh -c 'printf "root-mode\n" > "$1"' sh "$target"
    [[ "$(cat "$target")" == "root-mode" ]] || fail "root sudo wrapper did not execute the command directly"
)

test_root_sudo_wrapper_bypasses_logging_function() (
    local tmp
    id() {
        if [[ "${1:-}" == "-u" ]]; then
            printf '0\n'
            return
        fi
        command id "$@"
    }
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/os-init-root-install.XXXXXX")"
    trap 'rm -rf "${tmp}"' EXIT
    # shellcheck disable=SC2033
    sudo install -m 0600 /dev/null "${tmp}/marker"
    [[ -f "${tmp}/marker" ]] || fail "root sudo wrapper called the install logging function"
)

test_root_is_always_the_target_user() (
    id() {
        case "${1:-}" in
            -u) printf '0\n' ;;
            -un) printf 'root\n' ;;
            *) command id "$@" ;;
        esac
    }
    getent() {
        printf 'root:x:0:0:root:/root:/bin/bash\n'
    }
    SUDO_USER=alice
    HOME=/home/alice

    [[ "$(real_user)" == "root" ]] || fail "root mode inherited SUDO_USER as its target"
    [[ "$(real_home)" == "/root" ]] || fail "root mode inherited a non-root HOME"
)

test_config_loader_ignores_undeclared_keys() (
    local config_file="$TEST_HOME/config-allowlist.env"
    DOWNLOAD_TIMEOUT=30
    unset UNDECLARED_OS_INIT_TEST || true
    printf 'DOWNLOAD_TIMEOUT=45\nUNDECLARED_OS_INIT_TEST=unexpected\n' > "$config_file"

    source_config_file "$config_file"
    [[ "$DOWNLOAD_TIMEOUT" == "45" ]] || fail "declared config key was not loaded"
    [[ -z "${UNDECLARED_OS_INIT_TEST:-}" ]] || fail "undeclared config key leaked into shell environment"
)

test_macos_pkg_remove_does_not_install_homebrew
test_pkg_install_uses_arch_strategy
test_redhat_install_retries_with_epel
test_arch_packages_split_between_pacman_and_aur
test_arch_repository_lookup_syncs_database_first
test_arch_pacman_retries_and_prioritizes_arm_mirrors
test_arch_helper_bootstrap_prefers_paru_and_adds_yay
test_owned_path_restores_preexisting_content
test_unknown_owned_path_is_preserved
test_verified_download_rejects_unchecked_proxy
test_verified_download_accepts_expected_digest
test_verified_download_rejects_wrong_digest
test_root_sudo_wrapper_runs_without_sudo_binary
test_root_sudo_wrapper_bypasses_logging_function
test_root_is_always_the_target_user
test_config_loader_ignores_undeclared_keys

printf 'os-init lib strategy checks passed\n'

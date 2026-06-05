#!/usr/bin/env bash
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

test_macos_pkg_remove_does_not_install_homebrew
test_pkg_install_uses_arch_strategy
test_arch_packages_split_between_pacman_and_aur
test_arch_helper_bootstrap_prefers_paru_and_adds_yay

printf 'os-init lib strategy checks passed\n'

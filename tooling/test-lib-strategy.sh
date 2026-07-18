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

test_legacy_user_path_adoption_is_explicit() (
	local target="$TEST_HOME/legacy-tmux.conf"
	local state_dir="$TEST_HOME/legacy-state"
	local normalized_target
	OS_INIT_USER_STATE_DIR="$state_dir"
	printf '# OS Init Arch generated tmux config\n' > "$target"

	os_init_adopt_created_user_path tmux-config "$target"
	normalized_target="$(os_init_normalize_absolute_path "$target")"
	grep -Fqx 'state=created' "$state_dir/ownership/user-path-tmux-config" || fail "legacy path was not adopted as OS Init-created"
	grep -Fqx "target=$normalized_target" "$state_dir/ownership/user-path-tmux-config" || fail "adopted marker did not bind its target"
	[[ ! -e "$state_dir/backups/tmux-config" ]] || fail "adopted legacy path must not be backed up as user content"
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
	OS_INIT_PACKAGE_METADATA_STAMP="$TEST_HOME/package-metadata-ready"
	rm -f "$OS_INIT_PACKAGE_METADATA_STAMP"
    local -a calls=()
    sudo_env() { calls+=("sudo:$*"); }
    pacman() { calls+=("pacman:$*"); return 0; }

    arch_package_available ncdu
	_ARCH_PACKAGE_DATABASE_SYNCED=false
    arch_package_available tmux
    assert_call "sudo:pacman -Syu --noconfirm"
    [[ "${calls[0]}" == "sudo:pacman -Syu --noconfirm" ]] || fail "Arch lookup queried before database sync"
    [[ "$(printf '%s\n' "${calls[@]}" | grep -Fc 'sudo:pacman -Syu --noconfirm')" == 1 ]] || fail "Arch database synced more than once"
	[[ -f "$OS_INIT_PACKAGE_METADATA_STAMP" ]] || fail "Arch database sync did not publish the batch stamp"
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

test_arch_helper_bootstrap_installs_only_paru() (
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
	command -v yay >/dev/null && fail "yay should not be installed as a redundant companion"
    assert_call "makepkg:paru"
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

test_owned_path_rejects_target_rebinding() (
    local state_dir="$TEST_HOME/rebind-state"
    local original="$TEST_HOME/rebind-original"
    local rebound="$TEST_HOME/rebind-target"
    OS_INIT_SYSTEM_STATE_DIR="$state_dir"
    sudo() { command "$@"; }

    printf 'managed\n' > "$original"
    printf 'must-survive\n' > "$rebound"
    os_init_prepare_owned_path same-key "$original"
    if os_init_restore_owned_path same-key "$rebound" >/dev/null 2>&1; then
        fail "ownership marker should not authorize a rebound target"
    fi
    [[ "$(cat "$rebound")" == "must-survive" ]] || fail "rebound target was modified"
)

test_owned_path_rejects_legacy_unbound_marker() (
    local state_dir="$TEST_HOME/legacy-marker-state"
    local target="$TEST_HOME/legacy-marker-target"
    OS_INIT_SYSTEM_STATE_DIR="$state_dir"
    sudo() { command "$@"; }

    mkdir -p "$state_dir/ownership"
    printf 'created\n' > "$state_dir/ownership/legacy-key"
    printf 'must-survive\n' > "$target"
    if os_init_restore_owned_path legacy-key "$target" >/dev/null 2>&1; then
        fail "legacy unbound marker should not authorize deletion"
    fi
    [[ "$(cat "$target")" == "must-survive" ]] || fail "legacy marker modified its target"
)

test_safe_remove_tree_enforces_scope() (
    local allowed="$TEST_HOME/safe-remove" target="$TEST_HOME/safe-remove/child" outside="$TEST_HOME/outside-remove"
    sudo() { command "$@"; }
    findmnt() { printf '/\n'; }
    mkdir -p "$target" "$outside"
    printf 'inside\n' > "$target/data"
    printf 'outside\n' > "$outside/data"

    os_init_safe_remove_tree "$target" "$allowed" test-target
    [[ ! -e "$target" ]] || fail "safe in-scope tree was not removed"
    if os_init_safe_remove_tree "$outside" "$allowed" test-target >/dev/null 2>&1; then
        fail "out-of-scope recursive target should be rejected"
    fi
    [[ "$(cat "$outside/data")" == "outside" ]] || fail "out-of-scope data was modified"
)

test_safe_remove_tree_rejects_mount_boundaries() (
    local allowed="$TEST_HOME/safe-remove-mounts" target="$TEST_HOME/safe-remove-mounts/child"
    local nested="$TEST_HOME/safe-remove-mounts/child/cache" canonical_target canonical_nested
    sudo() { command "$@"; }
    mkdir -p "$target"
    printf 'must-survive\n' > "$target/data"
    canonical_target="$(os_init_normalize_absolute_path "$target")"
    canonical_nested="$(os_init_normalize_absolute_path "$nested")"

    findmnt() { printf '/\n%s\n' "$canonical_target"; }
    if (os_init_safe_remove_tree "$target" "$allowed" exact-mount >/dev/null 2>&1); then
        fail "recursive removal accepted an exact mountpoint"
    fi
    [[ "$(cat "$target/data")" == "must-survive" ]] || fail "exact mountpoint data was modified"

    findmnt() { printf '/\n%s\n' "$canonical_nested"; }
    if (os_init_safe_remove_tree "$target" "$allowed" nested-mount >/dev/null 2>&1); then
        fail "recursive removal accepted a directory containing a nested mount"
    fi
    [[ "$(cat "$target/data")" == "must-survive" ]] || fail "nested mount parent data was modified"

    findmnt() { return 1; }
    if (os_init_safe_remove_tree "$target" "$allowed" unreadable-mount-table >/dev/null 2>&1); then
        fail "recursive removal proceeded when the mount table was unavailable"
    fi
    [[ "$(cat "$target/data")" == "must-survive" ]] || fail "mount-query failure modified data"
)

test_systemd_service_name_rejects_paths_and_options() (
    os_init_validate_systemd_service_name mihomo.service
    for unsafe in '../host.service' '--all.service' $'mihomo.service\nExecStart=/bin/true'; do
        if (os_init_validate_systemd_service_name "$unsafe" >/dev/null 2>&1); then
            fail "unsafe systemd service name was accepted: $unsafe"
        fi
    done
)

test_container_home_mount_is_rejected() (
    is_container() { return 0; }
    real_home() { printf '/home/alice\n'; }
    findmnt() { printf '/home\n'; }
    unset OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER
    if (os_init_assert_safe_user_home >/dev/null 2>&1); then
        fail "container HOME on a separate mount should be rejected"
    fi
    OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER=1 os_init_assert_safe_user_home
)

test_provider_rejects_shared_container_home() (
    local provider_findmnt="$TEST_BIN/findmnt" output
    printf '#!/usr/bin/env sh\nprintf "/home\\n"\n' > "$provider_findmnt"
    chmod +x "$provider_findmnt"
    if output="$(HOME=/home/alice OS_INIT_TARGET_ENVIRONMENT=container OS_INIT_PROVIDER_PROTOCOL_REQUEST=1 \
        bash "$REPO_DIR/provider.sh" execute --script lib.sh 2>&1)"; then
        fail "provider accepted a separately mounted container HOME"
    fi
    [[ "$output" == *'container HOME is on a separate mount'* ]] || fail "provider did not explain the HOME boundary rejection"
)

test_executable_download_rejects_missing_digest() (
    local source_file="$TEST_HOME/download-source"
    local target="$TEST_HOME/download-target"
    printf 'payload\n' > "$source_file"
    GITHUB_PROXY="https://proxy.invalid/"
    download_file() { cp "$source_file" "$2"; }

    if (download_executable_verified "https://github.com/example/tool/releases/download/v1/tool" "$target" "" >/dev/null 2>&1); then
        fail "network executable without a digest should be rejected"
    fi
    [[ ! -e "$target" ]] || fail "rejected executable download should not create a target"
)

test_verified_download_accepts_expected_digest() (
    local source_file="$TEST_HOME/digest-source"
    local target="$TEST_HOME/digest-target"
    local digest
    printf 'payload\n' > "$source_file"
    GITHUB_PROXY="https://proxy.invalid/"
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
    download_file() { cp "$source_file" "$2"; }

    if (download_file_verified "https://github.com/example/tool/releases/download/v1/tool" "$target" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" >/dev/null 2>&1); then
        fail "wrong executable digest should be rejected"
    fi
    [[ ! -e "$target" ]] || fail "digest mismatch should remove the downloaded target"
)

test_github_proxy_formats_and_git_environment() (
    local target="$TEST_HOME/github-proxy-env"
    local rewritten without_slash with_slash many_slashes

    GITHUB_PROXY='https://proxy.invalid'
    without_slash="$(rewrite_github_url 'https://github.com/owner/repo')"
    GITHUB_PROXY='https://proxy.invalid/'
    with_slash="$(rewrite_github_url 'https://github.com/owner/repo')"
    GITHUB_PROXY='https://proxy.invalid///'
    many_slashes="$(rewrite_github_url 'https://github.com/owner/repo')"
    [[ "$without_slash" == "$with_slash" && "$with_slash" == "$many_slashes" ]] || \
        fail "GitHub proxy trailing slashes changed the rewritten URL"
    [[ "$without_slash" == 'https://proxy.invalid/https://github.com/owner/repo' ]] || \
        fail "GitHub proxy prefix was joined incorrectly: $without_slash"

    GITHUB_PROXY='https://proxy.invalid/?target={url_encoded}'
    rewritten="$(rewrite_github_url 'https://github.com/owner/repo?a=1&b=2')"
    [[ "$rewritten" == 'https://proxy.invalid/?target=https%3A%2F%2Fgithub.com%2Fowner%2Frepo%3Fa%3D1%26b%3D2' ]] || \
        fail "encoded GitHub proxy template was rendered incorrectly: $rewritten"

    GITHUB_PROXY='https://proxy.invalid/{url}'
    capture_proxy_env() {
        printf '%s\n%s\n' "${GIT_CONFIG_KEY_0:-}" "${GIT_CONFIG_VALUE_0:-}" > "$target"
    }
    run_with_github_git_proxy capture_proxy_env
    grep -Fq 'url.https://proxy.invalid/https://github.com/.insteadOf' "$target" || \
        fail "Git proxy did not inject a temporary insteadOf mapping"
    grep -Fq 'https://github.com/' "$target" || fail "Git proxy mapping has the wrong source URL"

    GIT_CONFIG_COUNT=1
    GIT_CONFIG_KEY_0='existing.key'
    GIT_CONFIG_VALUE_0='existing-value'
    capture_proxy_env() {
        printf '%s\n%s\n%s\n' "${GIT_CONFIG_KEY_0:-}" "${GIT_CONFIG_KEY_1:-}" "${GIT_CONFIG_VALUE_1:-}" > "$target"
    }
    run_with_github_git_proxy capture_proxy_env
    grep -Fq 'existing.key' "$target" || fail "Git proxy overwrote an existing temporary Git configuration"
    grep -Fq 'url.https://proxy.invalid/https://github.com/.insteadOf' "$target" || \
        fail "Git proxy did not append to an existing temporary Git configuration"
)

test_legacy_mise_config_is_namespaced() (
    local config_file="$TEST_HOME/legacy-mise.env"
    printf 'MISE_NODE_VERSION=22\nMISE_PYTHON_VERSION=3.12\nMISE_GO_VERSION=1.25\n' > "$config_file"
    unset MISE_NODE_VERSION MISE_PYTHON_VERSION MISE_GO_VERSION
    unset OS_INIT_MISE_NODE_VERSION OS_INIT_MISE_PYTHON_VERSION OS_INIT_MISE_GO_VERSION

    source_config_file "$config_file"

    [[ "${OS_INIT_MISE_NODE_VERSION:-}" == "22" ]] || fail "legacy Node.js selection was not migrated"
    [[ "${OS_INIT_MISE_PYTHON_VERSION:-}" == "3.12" ]] || fail "legacy Python selection was not migrated"
    [[ "${OS_INIT_MISE_GO_VERSION:-}" == "1.25" ]] || fail "legacy Go selection was not migrated"
    [[ -z "${MISE_NODE_VERSION:-}${MISE_PYTHON_VERSION:-}${MISE_GO_VERSION:-}" ]] || \
        fail "legacy mise variables leaked into the mise environment"
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

test_shared_command_guards_are_available() (
    create_fake_command available-command
    require_cmd available-command
    if (require_cmd missing-command-for-os-init-test) >/dev/null 2>&1; then
        fail "require_cmd accepted a missing command"
    fi
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
test_arch_helper_bootstrap_installs_only_paru
test_owned_path_restores_preexisting_content
test_unknown_owned_path_is_preserved
test_owned_path_rejects_target_rebinding
test_owned_path_rejects_legacy_unbound_marker
test_safe_remove_tree_enforces_scope
test_safe_remove_tree_rejects_mount_boundaries
test_systemd_service_name_rejects_paths_and_options
test_container_home_mount_is_rejected
test_provider_rejects_shared_container_home
test_executable_download_rejects_missing_digest
test_verified_download_accepts_expected_digest
test_verified_download_rejects_wrong_digest
test_github_proxy_formats_and_git_environment
test_legacy_mise_config_is_namespaced
test_legacy_user_path_adoption_is_explicit
test_root_sudo_wrapper_runs_without_sudo_binary
test_root_sudo_wrapper_bypasses_logging_function
test_shared_command_guards_are_available
test_root_is_always_the_target_user
test_config_loader_ignores_undeclared_keys

printf 'os-init lib strategy checks passed\n'

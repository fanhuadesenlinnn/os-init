#!/usr/bin/env bash
# The test sources the real installer dynamically. Variables assigned below are
# consumed by functions defined in that sourced file.
# shellcheck disable=SC1091,SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/os-init-mise-home.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export REPO_DIR="$ROOT_DIR/modules"

source "$ROOT_DIR/modules/mise/install.sh"

fail() {
    printf 'test-mise-strategy: %s\n' "$*" >&2
    exit 1
}

home="$TEST_HOME"
env_file="$home/.config/os-init/mise-china.env"
mise_config="$home/.config/mise/config.toml"
mise_data="$home/.local/share/mise"
mkdir -p "$(dirname "$mise_config")"

OS_INIT_MISE_NODE_VERSION=24
OS_INIT_MISE_PYTHON_VERSION=3.13
OS_INIT_MISE_GO_VERSION=1.26
MISE_NODE_MIRROR_URL=https://invalid.example/node/
MISE_GO_DOWNLOAD_MIRROR=https://invalid.example/go

attempt=0
declare -a mirror_calls=()

fake_runtime_dir="$TEST_HOME/fake-runtime/bin"
mkdir -p "$fake_runtime_dir"
for tool in go python node npm corepack; do
    # shellcheck disable=SC2016
    printf '#!/usr/bin/env bash\ncase "$(basename "$0")" in go) echo "go version go1.26.1 linux/amd64" ;; python) echo "Python 3.13.0" ;; node) echo "v24.0.0" ;; *) echo "1.0.0" ;; esac\n' > "$fake_runtime_dir/$tool"
    chmod +x "$fake_runtime_dir/$tool"
done

mise_exec() {
    case "${1:-}" in
        use)
            attempt=$((attempt + 1))
            mirror_calls+=("${MISE_NODE_MIRROR_URL:-}|${MISE_GO_DOWNLOAD_MIRROR:-}")
            [[ "$attempt" -ge 2 ]]
            ;;
        settings)
            return 0
            ;;
        which)
            printf '%s/%s\n' "$fake_runtime_dir" "$2"
            ;;
        *)
            return 0
            ;;
    esac
}

install() { :; }
warn() { :; }
os_init_prepare_owned_user_path() { :; }
os_init_mark_user_ownership() { :; }

install_mise_runtime go

[[ "$attempt" -eq 2 ]] || fail "expected one mirror attempt and one official retry, got $attempt"
[[ "${mirror_calls[0]}" == "https://invalid.example/node/|https://invalid.example/go" ]] || \
    fail "first attempt did not preserve the custom mirrors: ${mirror_calls[0]}"
[[ "${mirror_calls[1]}" == "https://nodejs.org/dist/|https://dl.google.com/go" ]] || \
    fail "official retry did not override inherited mirror environment: ${mirror_calls[1]}"

MISE_GO_DOWNLOAD_MIRROR=https://golang.google.cn/dl/
[[ "$(resolve_mise_go_download_mirror)" == "https://dl.google.com/go" ]] || \
    fail "legacy golang.google.cn mirror was not normalized before use"
grep -Fxq 'MISE_GO_DOWNLOAD_MIRROR=https://dl.google.com/go' "$ROOT_DIR/modules/config/defaults.env" || \
    fail "defaults.env does not use the mise-compatible Go mirror"
grep -Fxq 'OS_INIT_MISE_GO_VERSION=1.26' "$ROOT_DIR/modules/config/defaults.env" || \
    fail "defaults.env does not align mise Go with the repository toolchain series"

OS_INIT_CONTEXT_VERSION=1
OS_INIT_TARGET_USER=root
OS_INIT_TARGET_HOME=/root
[[ "$(real_user)" == "root" && "$(real_home)" == "/root" ]] || \
    fail "root target context was not preserved"
OS_INIT_TARGET_USER=alice
OS_INIT_TARGET_HOME=/home/alice
[[ "$(real_user)" == "alice" && "$(real_home)" == "/home/alice" ]] || \
    fail "normal target-user context was not preserved"

OS=linux
OS_FAMILY=arch
pkg_is_installed() { return 1; }
pacman() { return 1; }
if mise_uses_native_package; then
    fail "Arch must use the official mise installer when the architecture repository lacks the package"
fi
pacman() { [[ "$1 $2" == "-Si mise" ]]; }
mise_uses_native_package || fail "Arch should prefer pacman when mise is available"

(
    mise_binary="$TEST_HOME/.local/bin/mise"
    UPDATE=false
    MISE_VERSION=2026.7.0
    mkdir -p "$(dirname "$mise_binary")"
    printf 'incomplete previous install\n' > "$mise_binary"
    chmod 0644 "$mise_binary"
    mise_binary_owned() { return 0; }
    curl() {
        [[ "$*" == "--fail --silent --show-error --location https://mise.run" ]] || \
            fail "unexpected mise installer request: $*"
        cat <<'INSTALLER'
#!/bin/sh
printf '%s|%s\n' "$MISE_INSTALL_PATH" "${MISE_VERSION:-}" > "$HOME/mise-installer-env"
mkdir -p "$(dirname "$MISE_INSTALL_PATH")"
printf '#!/bin/sh\nexit 0\n' > "$MISE_INSTALL_PATH"
chmod 0755 "$MISE_INSTALL_PATH"
INSTALLER
    }
    install_mise_binary
    [[ -x "$mise_binary" ]] || fail "official installer did not create the configured mise binary"
    [[ "$(cat "$TEST_HOME/mise-installer-env")" == "$mise_binary|v2026.7.0" ]] || \
        fail "official installer did not receive the normalized path and version"
)

printf 'mise installer, runtime, mirror fallback, and target-home checks passed\n'

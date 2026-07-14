#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/os-init-mise-home.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME"
export REPO_DIR="$ROOT_DIR/modules"

# shellcheck source=../modules/mise/install.sh
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

MISE_NODE_VERSION=24
MISE_PYTHON_VERSION=3.13
MISE_GO_VERSION=1.24
MISE_NODE_MIRROR_URL=https://invalid.example/node/
MISE_GO_DOWNLOAD_MIRROR=https://golang.google.cn/dl/

attempt=0
declare -a mirror_calls=()

mise() {
    case "${1:-}" in
        use)
            attempt=$((attempt + 1))
            mirror_calls+=("${MISE_NODE_MIRROR_URL:-}|${MISE_GO_DOWNLOAD_MIRROR:-}")
            [[ "$attempt" -ge 2 ]]
            ;;
        settings)
            return 0
            ;;
        exec)
            case "${3:-}" in
                node) printf 'v24.0.0\n' ;;
                python) printf 'Python 3.13.0\n' ;;
                go) printf 'go version go1.24.13 linux/amd64\n' ;;
                npm|corepack) printf '1.0.0\n' ;;
                *) return 1 ;;
            esac
            ;;
        which)
            return 0
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

install_mise_runtimes

[[ "$attempt" -eq 2 ]] || fail "expected one mirror attempt and one official retry, got $attempt"
[[ "${mirror_calls[0]}" == "https://invalid.example/node/|https://golang.google.cn/dl/" ]] || \
    fail "first attempt did not preserve configured mirrors: ${mirror_calls[0]}"
[[ "${mirror_calls[1]}" == "https://nodejs.org/dist/|https://dl.google.com/go" ]] || \
    fail "official retry did not override inherited mirror environment: ${mirror_calls[1]}"
[[ "$(resolve_mise_go_download_mirror)" == "https://dl.google.com/go" ]] || \
    fail "legacy golang.google.cn mirror was not normalized"
grep -Fxq 'MISE_GO_DOWNLOAD_MIRROR=https://dl.google.com/go' "$ROOT_DIR/modules/config/defaults.env" || \
    fail "defaults.env does not use the mise-compatible Go mirror"

printf 'mise mirror fallback checks passed\n'

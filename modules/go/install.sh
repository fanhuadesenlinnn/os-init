#!/bin/bash
set -euo pipefail

# Install Go programming language through the native package manager or go.dev tarball
# Author: Dusan Panic <dpanic@gmail.com>
# Safe to re-run -- idempotent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

GO_INSTALL_DIR="/usr/local/go"

TITLE="Install"
[[ "$UNINSTALL" == true ]] && TITLE="Uninstall"
echo "=== Go Programming Language ($TITLE) ==="
echo ""

if [[ "$UNINSTALL" == true ]]; then
    if is_macos || is_arch; then
        if pkg_is_installed go; then
            remove "通过系统包管理器卸载 Go"
            pkg_remove go 2>/dev/null || true
        fi
    fi
    if [[ -d "$GO_INSTALL_DIR" ]]; then
        remove "removing $GO_INSTALL_DIR"
        sudo rm -rf "$GO_INSTALL_DIR"
    else
        skip "Go not installed at $GO_INSTALL_DIR"
    fi
    os_init_remove_shell_block "go"
    echo ""
    echo "=== Go uninstall complete ==="
    exit 0
fi

go_prefers_package_manager() {
    is_macos || is_arch
}

install_go_package() {
    local label="$1"
    if is_macos; then
        $label "通过 Homebrew 安装 Go"
    else
        $label "通过 pacman/AUR 安装 Go"
    fi
    pkg_install go
}

install_go_binary() {
    local label="$1"
    local version_file go_os go_arch go_url

    if [[ -z "${GO_VERSION:-}" ]]; then
        version_file="$(mktemp "${TMPDIR:-/tmp}/go-version.XXXXXX")"
        download_file "${GO_VERSION_URL:-https://go.dev/VERSION?m=text}" "$version_file"
        GO_VERSION="$(head -1 "$version_file")"
        rm -f "$version_file"
    fi

    if [[ -z "$GO_VERSION" ]]; then
        die "无法确定 Go 版本"
    fi
    [[ "$GO_VERSION" == go* ]] || GO_VERSION="go$GO_VERSION"

    $label "准备安装 $GO_VERSION"

    if is_linux; then
        go_os="linux"
    elif is_macos; then
        go_os="darwin"
    else
        die "Go 安装暂不支持当前系统: $OS"
    fi

    case "$(uname -m)" in
        x86_64|amd64) go_arch="amd64" ;;
        arm64|aarch64) go_arch="arm64" ;;
        *) die "Go 安装暂不支持当前架构: $(uname -m)" ;;
    esac

    local go_base="${GO_DOWNLOAD_BASE:-https://go.dev/dl}"
    go_url="$(resource_url GO_DOWNLOAD_URL "${go_base%/}/${GO_VERSION}.${go_os}-${go_arch}.tar.gz")"
    TMP_DIR=$(mktemp -d /tmp/go-XXXXXX)
    echo "  获取: $go_url"
    download_file "$go_url" "$TMP_DIR/go.tar.gz"
    sudo rm -rf "$GO_INSTALL_DIR"
    sudo tar -C /usr/local -xzf "$TMP_DIR/go.tar.gz"
    rm -rf "$TMP_DIR"
    echo "  installed: $("$GO_INSTALL_DIR/bin/go" version 2>/dev/null || echo "$GO_VERSION")"
}

echo "[1/2] go..."
if command -v go &>/dev/null || [[ -x "$GO_INSTALL_DIR/bin/go" ]]; then
    if [[ "$UPDATE" == true ]]; then
        if go_prefers_package_manager; then
            install_go_package update
        else
            install_go_binary update
        fi
    else
        skip "go $(go version 2>/dev/null | awk '{print $3}') already installed"
    fi
else
    if go_prefers_package_manager; then
        install_go_package install
    else
        install_go_binary install
    fi
fi

echo "[2/2] PATH..."
GO_PATH_BLOCK="$(cat <<'EOF'
if [ -d /usr/local/go/bin ]; then
    case ":$PATH:" in
        *:/usr/local/go/bin:*) ;;
        *) export PATH="$PATH:/usr/local/go/bin" ;;
    esac
fi
EOF
)"
os_init_upsert_shell_block "go" "$GO_PATH_BLOCK"

echo ""
echo "=== Go installation complete ==="
echo ""
os_init_text "打开新终端或执行 exec zsh 后运行 go version 验证。" "Open a new terminal or run exec zsh, then verify with go version."

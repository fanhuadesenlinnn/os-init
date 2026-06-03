#!/bin/bash
set -euo pipefail

# Install Go programming language from go.dev tarball
# Author: Dusan Panic <dpanic@gmail.com>
# Safe to re-run -- idempotent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

GO_INSTALL_DIR="/usr/local/go"

TITLE="Install"
[[ "$UNINSTALL" == true ]] && TITLE="Uninstall"
echo "=== Go Programming Language ($TITLE) ==="
echo ""

if [[ "$UNINSTALL" == true ]]; then
    if [[ -d "$GO_INSTALL_DIR" ]]; then
        remove "removing $GO_INSTALL_DIR"
        sudo rm -rf "$GO_INSTALL_DIR"
    else
        skip "Go not installed at $GO_INSTALL_DIR"
    fi
    echo "  note: remove 'export PATH=\$PATH:/usr/local/go/bin' from your shell profile"
    echo ""
    echo "=== Go uninstall complete ==="
    exit 0
fi

install_go() {
    local label="$1"
    local version_file go_os go_arch go_url archive_name

    if [[ -z "${GO_VERSION:-}" ]]; then
        if [[ "${OS_INIT_OFFLINE:-0}" == "1" ]]; then
            die "离线模式请在配置中设置 GO_VERSION，例如 GO_VERSION=go1.22.5"
        fi
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
    archive_name="$(basename "${go_url%%\?*}")"
    TMP_DIR=$(mktemp -d /tmp/go-XXXXXX)
    echo "  获取: $go_url"
    download_or_offline_file "$go_url" "$TMP_DIR/go.tar.gz" "$archive_name"
    sudo rm -rf "$GO_INSTALL_DIR"
    sudo tar -C /usr/local -xzf "$TMP_DIR/go.tar.gz"
    rm -rf "$TMP_DIR"
    echo "  installed: $("$GO_INSTALL_DIR/bin/go" version 2>/dev/null || echo "$GO_VERSION")"
}

echo "[1/2] go..."
if command -v go &>/dev/null || [[ -x "$GO_INSTALL_DIR/bin/go" ]]; then
    if [[ "$UPDATE" == true ]]; then
        install_go update
    else
        skip "go $(go version 2>/dev/null | awk '{print $3}') already installed"
    fi
else
    install_go install
fi

echo "[2/2] PATH..."
GO_PATH_LINE='export PATH=$PATH:/usr/local/go/bin'
if echo "$PATH" | grep -q "/usr/local/go/bin"; then
    skip "/usr/local/go/bin already in PATH"
else
    echo "  Add to your .zshrc or .profile:"
    echo "    $GO_PATH_LINE"
fi

echo ""
echo "=== Go installation complete ==="
echo ""
echo "Run 'go version' to verify."

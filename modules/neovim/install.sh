#!/bin/bash
set -euo pipefail

# Install Neovim + LazyVim starter config + dependencies
# Author: Dusan Panic <dpanic@gmail.com>
# Safe to re-run -- idempotent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

case "$(uname -m)" in
    x86_64|amd64)
        NVIM_ARCH="x86_64"
        LAZYGIT_ARCH="x86_64"
        ;;
    arm64|aarch64)
        NVIM_ARCH="arm64"
        LAZYGIT_ARCH="arm64"
        ;;
    *)
        NVIM_ARCH=""
        LAZYGIT_ARCH=""
        ;;
esac
NVIM_ARCH_DIR="nvim-linux-${NVIM_ARCH:-x86_64}"
NVIM_INSTALL_DIR="/opt/$NVIM_ARCH_DIR"

parse_update_flag "$@"

fd_package_name() {
    if is_macos || is_arch; then
        echo "fd"
    else
        echo "fd-find"
    fi
}

tool_prefers_package_manager() {
    is_macos || is_arch
}

TITLE="Setup"
[[ "$UNINSTALL" == true ]] && TITLE="Uninstall"
echo "=== Neovim + LazyVim $TITLE ==="
echo ""

if [[ "$UNINSTALL" == true ]]; then
    # neovim
    if command -v nvim &>/dev/null; then
        remove "removing neovim"
        if tool_prefers_package_manager; then
            pkg_remove neovim 2>/dev/null || true
        else
            sudo rm -rf "$NVIM_INSTALL_DIR" /usr/local/bin/nvim
        fi
    else
        skip "neovim not installed"
    fi

    # lazygit
    if command -v lazygit &>/dev/null; then
        remove "removing lazygit"
        if tool_prefers_package_manager; then
            pkg_remove lazygit 2>/dev/null || true
        else
            sudo rm -f /usr/local/bin/lazygit
        fi
    else
        skip "lazygit not installed"
    fi

    # ripgrep + fd
    command -v rg &>/dev/null && { remove "removing ripgrep"; pkg_remove ripgrep 2>/dev/null || true; }
    (command -v fdfind &>/dev/null || command -v fd &>/dev/null) && { remove "removing fd"; pkg_remove "$(fd_package_name)" 2>/dev/null || true; }

    # nvim config
    if [[ -d "$HOME/.config/nvim" ]]; then
        remove "removing ~/.config/nvim"
        rm -rf "$HOME/.config/nvim"
    fi

    # nvim data
    if [[ -d "$HOME/.local/share/nvim" ]]; then
        remove "removing ~/.local/share/nvim"
        rm -rf "$HOME/.local/share/nvim"
    fi
    os_init_remove_shell_block "neovim"

    echo ""
    echo "=== Neovim uninstall complete ==="
    exit 0
fi

# [1/4] Neovim via package manager or GitHub release tarball
echo "[1/4] neovim..."
install_nvim_linux() {
    local label="$1"
    [[ -n "$NVIM_ARCH" ]] || die "Neovim 安装暂不支持当前架构: $(uname -m)"
    $label "下载最新 Neovim 二进制包"
    TMP_DIR=$(mktemp -d /tmp/nvim-XXXXXX)
    NVIM_URL="$(resource_url NVIM_DOWNLOAD_URL "${NVIM_DOWNLOAD_BASE%/}/${NVIM_ARCH_DIR}.tar.gz")"
    echo "  获取: $NVIM_URL"
    download_file "$NVIM_URL" "$TMP_DIR/nvim.tar.gz"
    tar -xzf "$TMP_DIR/nvim.tar.gz" -C "$TMP_DIR"
    sudo rm -rf "$NVIM_INSTALL_DIR"
    sudo mv "$TMP_DIR/$NVIM_ARCH_DIR" "$NVIM_INSTALL_DIR"
    sudo ln -sf "$NVIM_INSTALL_DIR/bin/nvim" /usr/local/bin/nvim
    rm -rf "$TMP_DIR"
    echo "  installed: $(nvim --version | head -1)"
}

install_nvim_package() {
    local label="$1"
    if is_macos; then
        $label "通过 Homebrew 安装 Neovim"
    else
        $label "通过 pacman/AUR 安装 Neovim"
    fi
    pkg_install neovim
}

if command -v nvim &>/dev/null && nvim --version &>/dev/null; then
    if [[ "$UPDATE" == true ]]; then
        if is_macos; then
            update "updating neovim via Homebrew"
            brew_upgrade neovim 2>/dev/null || skip "neovim already at latest"
        elif is_arch; then
            install_nvim_package update
        else
            install_nvim_linux update
        fi
    else
        skip "nvim $(nvim --version | head -1) already installed"
    fi
else
    if tool_prefers_package_manager; then
        install_nvim_package install
    else
        install_nvim_linux install
    fi
fi

# [2/4] ripgrep + fd-find
echo "[2/4] ripgrep + fd-find..."
PKGS_TO_INSTALL=()
if command -v rg &>/dev/null; then
    skip "ripgrep $(rg --version | head -1) already installed"
else
    PKGS_TO_INSTALL+=(ripgrep)
fi

if command -v fdfind &>/dev/null || command -v fd &>/dev/null; then
    skip "fd-find already installed"
else
    PKGS_TO_INSTALL+=("$(fd_package_name)")
fi

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    install "installing ${PKGS_TO_INSTALL[*]}"
    pkg_install "${PKGS_TO_INSTALL[@]}"
fi

# [3/4] lazygit
echo "[3/4] lazygit..."
install_lazygit_linux() {
    local label="$1"
    [[ -n "$LAZYGIT_ARCH" ]] || die "lazygit 安装暂不支持当前架构: $(uname -m)"
    $label "下载最新 lazygit 二进制包"
    LAZYGIT_VERSION="${LAZYGIT_VERSION:-$(github_latest_version "jesseduffield/lazygit" "v")}"

    TMP_DIR=$(mktemp -d /tmp/lazygit-XXXXXX)
    LAZYGIT_URL="$(resource_url LAZYGIT_DOWNLOAD_URL "${LAZYGIT_DOWNLOAD_BASE%/}/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz")"
    echo "  获取: $LAZYGIT_URL"
    download_file "$LAZYGIT_URL" "$TMP_DIR/lazygit.tar.gz"
    tar -xzf "$TMP_DIR/lazygit.tar.gz" -C "$TMP_DIR"
    sudo mv "$TMP_DIR/lazygit" /usr/local/bin/lazygit
    sudo chmod +x /usr/local/bin/lazygit
    rm -rf "$TMP_DIR"
    echo "  installed: lazygit $LAZYGIT_VERSION"
}

install_lazygit_package() {
    local label="$1"
    if is_macos; then
        $label "通过 Homebrew 安装 lazygit"
    else
        $label "通过 pacman/AUR 安装 lazygit"
    fi
    pkg_install lazygit
}

if command -v lazygit &>/dev/null; then
    if [[ "$UPDATE" == true ]]; then
        if is_macos; then
            update "updating lazygit via Homebrew"
            brew_upgrade lazygit 2>/dev/null || skip "lazygit already at latest"
        elif is_arch; then
            install_lazygit_package update
        else
            install_lazygit_linux update
        fi
    else
        skip "lazygit already installed"
    fi
else
    if tool_prefers_package_manager; then
        install_lazygit_package install
    else
        install_lazygit_linux install
    fi
fi

# [4/4] LazyVim starter config
echo "[4/4] LazyVim config..."
NVIM_CONFIG="$HOME/.config/nvim"
if [[ -d "$NVIM_CONFIG" ]]; then
    if [[ -f "$NVIM_CONFIG/lazyvim.json" ]] || [[ -f "$NVIM_CONFIG/lazy-lock.json" ]]; then
        skip "LazyVim config already present at ~/.config/nvim/"
    else
        BACKUP="${NVIM_CONFIG}.bak.$(date +%s)"
        install "backing up existing nvim config to $BACKUP"
        mv "$NVIM_CONFIG" "$BACKUP"
        git_clone_depth 1 "$(repo_url LAZYVIM_STARTER_REPO "https://github.com/LazyVim/starter")" "$NVIM_CONFIG"
        rm -rf "$NVIM_CONFIG/.git"
    fi
else
    install "cloning LazyVim starter to ~/.config/nvim/"
    git_clone_depth 1 "$(repo_url LAZYVIM_STARTER_REPO "https://github.com/LazyVim/starter")" "$NVIM_CONFIG"
    rm -rf "$NVIM_CONFIG/.git"
fi

NVIM_SHELL_BLOCK="$(cat <<'EOF'
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="${EDITOR:-nvim}"
    export VISUAL="${VISUAL:-nvim}"
fi
EOF
)"
os_init_upsert_shell_block "neovim" "$NVIM_SHELL_BLOCK"

echo ""
echo "=== Neovim + LazyVim setup complete ==="
echo ""
echo "Run 'nvim' to launch. LazyVim will auto-install plugins on first start."

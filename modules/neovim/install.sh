#!/bin/bash
set -euo pipefail

# Install Neovim + Neovide (macOS) + config-yuan + dependencies
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

update_config_repo_safely() {
	local dir="$1" branch
	if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
		warn "config-yuan 存在未提交修改，跳过自动更新"
		return 0
	fi
	assert_git_remote_secure "$dir"
	branch="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || echo main)"
	git_with_proxy -C "$dir" fetch origin --depth=1 -q
	if ! git -C "$dir" merge --ff-only "origin/$branch"; then
		warn "config-yuan 无法快进更新，已保留当前配置"
	fi
}

TITLE="Setup"
[[ "$UNINSTALL" == true ]] && TITLE="Uninstall"
echo "=== Neovim + Neovide + config-yuan $TITLE ==="
echo ""

if [[ "$UNINSTALL" == true ]]; then
	# neovim
	if command -v nvim &>/dev/null; then
		if tool_prefers_package_manager && os_init_package_owned "neovim-package"; then
			remove "卸载由 OS Init 安装的 Neovim 软件包"
			pkg_remove neovim 2>/dev/null || true
			os_init_forget_package_ownership "neovim-package"
		elif tool_prefers_package_manager; then
			warn "Neovim 软件包不是由 OS Init 安装，予以保留"
		else
			os_init_restore_owned_path "neovim-install-dir" "$NVIM_INSTALL_DIR" || true
			os_init_restore_owned_path "neovim-bin-link" /usr/local/bin/nvim || true
		fi
    else
        skip "neovim not installed"
    fi

	# Neovide is part of this combined module on macOS.
	if is_macos; then
		if (brew_list --cask neovide-app &>/dev/null || [[ -d "/Applications/Neovide.app" ]]) && os_init_user_owned "macos-cask-neovide-app"; then
			remove "卸载由 OS Init 安装的 Neovide"
			brew_uninstall --cask neovide-app 2>/dev/null || true
			os_init_forget_user_ownership "macos-cask-neovide-app"
		elif brew_list --cask neovide-app &>/dev/null || [[ -d "/Applications/Neovide.app" ]]; then
			warn "Neovide 不是由 OS Init 安装，予以保留"
		else
			skip "Neovide not installed"
		fi
	fi

    # lazygit
	if command -v lazygit &>/dev/null; then
		if tool_prefers_package_manager && os_init_package_owned "lazygit-package"; then
			remove "卸载由 OS Init 安装的 lazygit 软件包"
			pkg_remove lazygit 2>/dev/null || true
			os_init_forget_package_ownership "lazygit-package"
		elif tool_prefers_package_manager; then
			warn "lazygit 软件包不是由 OS Init 安装，予以保留"
		else
			os_init_restore_owned_path "lazygit-bin" /usr/local/bin/lazygit || true
		fi
    else
        skip "lazygit not installed"
    fi

    # ripgrep + fd
	if os_init_package_owned "neovim-ripgrep-package"; then
		pkg_remove ripgrep 2>/dev/null || true
		os_init_forget_package_ownership "neovim-ripgrep-package"
	fi
	if os_init_package_owned "neovim-fd-package"; then
		pkg_remove "$(fd_package_name)" 2>/dev/null || true
		os_init_forget_package_ownership "neovim-fd-package"
	fi

    # nvim + Neovide config
	if [[ "${PURGE_CONFIG:-0}" == "1" ]]; then
		warn "PURGE_CONFIG=1，将恢复安装前的 Neovim 和 Neovide 配置"
		os_init_restore_owned_user_path "neovim-config-yuan" "$HOME/.config/nvim" || true
		os_init_restore_owned_user_path "neovide-config" "$HOME/.config/neovide/config.toml" || true
		if os_init_user_owned "neovim-data"; then
			rm -rf "$HOME/.local/share/nvim"
			os_init_forget_user_ownership "neovim-data"
		fi
	else
		skip "保留 Neovim/Neovide 配置和数据；如需恢复安装前状态请设置 PURGE_CONFIG=1"
	fi
    os_init_remove_shell_block "neovim"

    echo ""
    echo "=== Neovim uninstall complete ==="
    exit 0
fi

# [1/5] Neovim via package manager or GitHub release tarball
echo "[1/5] neovim..."
install_nvim_linux() {
    local label="$1"
    [[ -n "$NVIM_ARCH" ]] || die "Neovim 安装暂不支持当前架构: $(uname -m)"
    $label "下载最新 Neovim 二进制包"
    TMP_DIR=$(mktemp -d /tmp/nvim-XXXXXX)
    NVIM_URL="$(resource_url NVIM_DOWNLOAD_URL "${NVIM_DOWNLOAD_BASE%/}/${NVIM_ARCH_DIR}.tar.gz")"
    echo "  获取: $NVIM_URL"
	download_file_verified "$NVIM_URL" "$TMP_DIR/nvim.tar.gz" "${NVIM_DOWNLOAD_SHA256:-}"
    tar -xzf "$TMP_DIR/nvim.tar.gz" -C "$TMP_DIR"
	os_init_prepare_owned_path "neovim-install-dir" "$NVIM_INSTALL_DIR"
	os_init_prepare_owned_path "neovim-bin-link" /usr/local/bin/nvim
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
	[[ "$label" == "install" ]] && os_init_mark_package_ownership "neovim-package"
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

# [2/5] Neovide on macOS
echo "[2/5] neovide..."
if is_macos; then
	if brew_list --cask neovide-app &>/dev/null || [[ -d "/Applications/Neovide.app" ]]; then
		if [[ "$UPDATE" == true ]]; then
			update "updating Neovide via Homebrew"
			brew_upgrade --cask neovide-app 2>/dev/null || skip "Neovide already at latest"
		else
			skip "Neovide already installed"
		fi
	else
		install "installing Neovide via Homebrew cask"
		brew_install --cask neovide-app
		os_init_mark_user_ownership "macos-cask-neovide-app"
	fi
else
	skip "Neovide GUI is only installed on macOS"
fi

# [3/5] ripgrep + fd-find
echo "[3/5] ripgrep + fd-find..."
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
	for package in "${PKGS_TO_INSTALL[@]}"; do
		case "$package" in
			ripgrep) os_init_mark_package_ownership "neovim-ripgrep-package" ;;
			fd|fd-find) os_init_mark_package_ownership "neovim-fd-package" ;;
		esac
	done
fi

# [4/5] lazygit
echo "[4/5] lazygit..."
install_lazygit_linux() {
    local label="$1"
    [[ -n "$LAZYGIT_ARCH" ]] || die "lazygit 安装暂不支持当前架构: $(uname -m)"
    $label "下载最新 lazygit 二进制包"
    LAZYGIT_VERSION="${LAZYGIT_VERSION:-$(github_latest_version "jesseduffield/lazygit" "v")}"

    TMP_DIR=$(mktemp -d /tmp/lazygit-XXXXXX)
    LAZYGIT_URL="$(resource_url LAZYGIT_DOWNLOAD_URL "${LAZYGIT_DOWNLOAD_BASE%/}/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz")"
    echo "  获取: $LAZYGIT_URL"
	download_file_verified "$LAZYGIT_URL" "$TMP_DIR/lazygit.tar.gz" "${LAZYGIT_DOWNLOAD_SHA256:-}"
    tar -xzf "$TMP_DIR/lazygit.tar.gz" -C "$TMP_DIR"
	os_init_prepare_owned_path "lazygit-bin" /usr/local/bin/lazygit
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
	[[ "$label" == "install" ]] && os_init_mark_package_ownership "lazygit-package"
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

# [5/5] Personal Neovim + Neovide configuration
echo "[5/5] config-yuan..."
NVIM_CONFIG="$HOME/.config/nvim"
NVIM_CONFIG_REPO_URL="$(repo_url NVIM_CONFIG_REPO "https://github.com/fanhuadesenlinnn/nvim.git")"
os_init_prepare_owned_user_path "neovim-config-yuan" "$NVIM_CONFIG"
if [[ -d "$NVIM_CONFIG/.git" ]] && git -C "$NVIM_CONFIG" remote get-url origin &>/dev/null; then
	CURRENT_CONFIG_REMOTE="$(git -C "$NVIM_CONFIG" remote get-url origin)"
	if [[ "${CURRENT_CONFIG_REMOTE%.git}" == "${NVIM_CONFIG_REPO_URL%.git}" ]]; then
		if [[ "$UPDATE" == true ]]; then
			update "updating config-yuan"
			update_config_repo_safely "$NVIM_CONFIG"
		else
			skip "config-yuan already present at ~/.config/nvim"
		fi
	else
		install "replacing the managed Neovim config with config-yuan"
		rm -rf "$NVIM_CONFIG"
		git_clone_depth 1 "$NVIM_CONFIG_REPO_URL" "$NVIM_CONFIG"
	fi
else
	rm -rf "$NVIM_CONFIG"
	install "cloning config-yuan to ~/.config/nvim"
	git_clone_depth 1 "$NVIM_CONFIG_REPO_URL" "$NVIM_CONFIG"
fi

if is_macos && [[ -f "$NVIM_CONFIG/neovide/config.toml" ]]; then
	NEOVIDE_CONFIG="$HOME/.config/neovide/config.toml"
	os_init_prepare_owned_user_path "neovide-config" "$NEOVIDE_CONFIG"
	mkdir -p "$(dirname "$NEOVIDE_CONFIG")"
	rm -rf "$NEOVIDE_CONFIG"
	ln -s "$NVIM_CONFIG/neovide/config.toml" "$NEOVIDE_CONFIG"
fi

if [[ ! -e "$HOME/.local/share/nvim" ]]; then
	os_init_mark_user_ownership "neovim-data"
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
echo "=== Neovim + Neovide + config-yuan setup complete ==="
echo ""
echo "Run 'nvim' or open Neovide. lazy.nvim will install plugins on first start."

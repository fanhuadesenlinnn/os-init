#!/bin/bash
set -euo pipefail

# Install Yazi terminal file manager
# Author: Dusan Panic <dpanic@gmail.com>
# Safe to re-run -- idempotent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

TITLE="$(os_init_text "安装" "Install")"
[[ "$UNINSTALL" == true ]] && TITLE="$(os_init_text "卸载" "Uninstall")"
echo "=== Yazi $(os_init_text "终端文件管理器" "Terminal File Manager") ($TITLE) ==="
echo ""

if [[ "$UNINSTALL" == true ]]; then
	if command -v yazi &>/dev/null; then
		if (is_macos || is_arch) && os_init_package_owned "yazi-package"; then
			remove "卸载由 OS Init 安装的 yazi 软件包"
			pkg_remove yazi 2>/dev/null || true
			os_init_forget_package_ownership "yazi-package"
		elif is_macos || is_arch; then
			warn "yazi 软件包不是由 OS Init 安装，予以保留"
		else
			os_init_restore_owned_path "yazi-bin" /usr/local/bin/yazi || true
			os_init_restore_owned_path "yazi-ya-bin" /usr/local/bin/ya || true
		fi
	else
		skip "yazi 未安装"
	fi
	if [[ -d "$HOME/.config/yazi" ]]; then
		if [[ "${PURGE_CONFIG:-0}" == "1" ]]; then
			warn "PURGE_CONFIG=1，将删除整个 ~/.config/yazi"
			rm -rf "$HOME/.config/yazi"
		else
			if grep -Fq '# Managed by OS Init' "$HOME/.config/yazi/ya.sh" 2>/dev/null; then
				rm -f "$HOME/.config/yazi/ya.sh"
				remove "删除 OS Init 创建的 ya.sh"
			fi
			rm -f "$HOME/.config/yazi/.os-init-directory-owned"
			rmdir "$HOME/.config/yazi" 2>/dev/null || warn "保留现有 Yazi 配置目录"
		fi
	fi
    os_init_remove_shell_block "yazi"
    echo ""
    echo "=== Yazi $(os_init_text "卸载完成" "uninstall complete") ==="
    exit 0
fi

log_yazi_action() {
    local action="$1" message="$2"
    if [[ "$action" == "update" ]]; then
        update "$message"
    else
        install "$message"
    fi
}

homebrew_yazi_installed() {
    is_macos || return 1
    command -v brew &>/dev/null || return 1
    brew_list yazi &>/dev/null
}

yazi_available() {
    command -v yazi &>/dev/null || homebrew_yazi_installed
}

print_homebrew_hint() {
    echo "  $(os_init_text "安装器: Homebrew formula yazi" "Installer: Homebrew formula yazi")"
    if [[ -z "${HOMEBREW_API_DOMAIN:-}" || -z "${HOMEBREW_BOTTLE_DOMAIN:-}" ]]; then
        echo "  $(os_init_text "如果长时间停在这里，通常是 Homebrew bottle 下载慢；可在配置中设置 HOMEBREW_API_DOMAIN/HOMEBREW_BOTTLE_DOMAIN。" "If it stays here for a long time, Homebrew bottle downloads are usually slow; set HOMEBREW_API_DOMAIN/HOMEBREW_BOTTLE_DOMAIN in config.")"
    else
        echo "  $(os_init_text "已检测到 Homebrew 镜像配置。" "Homebrew mirror configuration detected.")"
    fi
}

install_yazi_from_homebrew() {
    local action="$1"
    print_homebrew_hint
    if [[ "$action" == "update" ]]; then
        log_yazi_action "$action" "通过 Homebrew 更新 yazi"
        brew_upgrade yazi 2>/dev/null || skip "yazi 已是最新"
    else
        log_yazi_action "$action" "通过 Homebrew 安装 yazi"
	pkg_install yazi
	[[ "$action" == "install" ]] && os_init_mark_package_ownership "yazi-package"
    fi
}

install_yazi_from_arch_package() {
    local action="$1"
    echo "  $(os_init_text "安装器: pacman/AUR 包 yazi" "Installer: pacman/AUR package yazi")"
    log_yazi_action "$action" "通过 pacman/AUR 安装 yazi"
	pkg_install yazi
	[[ "$action" == "install" ]] && os_init_mark_package_ownership "yazi-package"
}

prefer_arch_package() {
    is_arch || return 1
    [[ -z "${YAZI_DOWNLOAD_URL:-}" ]] || return 1

    local default_base="https://github.com/sxyazi/yazi/releases/latest/download"
    [[ "${YAZI_DOWNLOAD_BASE:-$default_base}" == "$default_base" ]]
}

install_yazi_from_zip() {
    local action="$1"
    local yazi_arch
    case "$(uname -m)" in
        x86_64|amd64) yazi_arch="x86_64" ;;
        arm64|aarch64) yazi_arch="aarch64" ;;
        *) die "Yazi 安装暂不支持当前架构: $(uname -m)" ;;
    esac

    log_yazi_action "$action" "下载最新 Yazi 二进制包"
    local ZIP_URL
    ZIP_URL="$(resource_url YAZI_DOWNLOAD_URL "${YAZI_DOWNLOAD_BASE%/}/yazi-${yazi_arch}-unknown-linux-gnu.zip")"

    TMP_DIR=$(mktemp -d /tmp/yazi-XXXXXX)
    echo "  $(os_init_text "安装器: GitHub release zip" "Installer: GitHub release zip")"
    echo "  $(os_init_text "获取" "Fetch"): $ZIP_URL"
    echo "  $(os_init_text "如果长时间停在这里，请配置 GITHUB_PROXY 或 YAZI_DOWNLOAD_URL。" "If it stays here for a long time, configure GITHUB_PROXY or YAZI_DOWNLOAD_URL.")"
	download_file_verified "$ZIP_URL" "$TMP_DIR/yazi.zip" "${YAZI_DOWNLOAD_SHA256:-}"
    unzip -q "$TMP_DIR/yazi.zip" -d "$TMP_DIR"

	os_init_prepare_owned_path "yazi-bin" /usr/local/bin/yazi
	os_init_prepare_owned_path "yazi-ya-bin" /usr/local/bin/ya
	sudo install -m 755 "$TMP_DIR"/yazi-*/yazi /usr/local/bin/yazi
	sudo install -m 755 "$TMP_DIR"/yazi-*/ya /usr/local/bin/ya

    rm -rf "$TMP_DIR"
    echo "  $(os_init_text "已安装" "installed"): yazi"
}

install_yazi_linux() {
    local action="$1"
    if prefer_arch_package; then
        install_yazi_from_arch_package "$action"
    else
        install_yazi_from_zip "$action"
    fi
}

# [1/3] Install yazi
echo "[1/3] yazi..."
if yazi_available; then
    if [[ "$UPDATE" == true ]]; then
        if is_macos; then
            install_yazi_from_homebrew update
        else
            install_yazi_linux update
        fi
    else
        skip "yazi 已安装"
        if ! command -v yazi &>/dev/null && homebrew_yazi_installed; then
            warn "Homebrew 已安装 yazi，但当前 PATH 找不到 yazi；请打开新终端或检查 brew shellenv"
        fi
    fi
else
    if is_macos; then
        install_yazi_from_homebrew install
    else
        install_yazi_linux install
    fi
fi

# [2/3] Yazi config directory
echo "[2/3] yazi config..."
YAZI_CONFIG="$HOME/.config/yazi"
if [[ -d "$YAZI_CONFIG" ]]; then
    skip "$HOME/.config/yazi/ 已存在"
else
	install "创建 ~/.config/yazi/"
	mkdir -p "$YAZI_CONFIG"
	touch "$YAZI_CONFIG/.os-init-directory-owned"
fi

# [3/3] Shell wrapper for cd-on-exit behavior
echo "[3/3] yazi shell wrapper..."
WRAPPER_FILE="$YAZI_CONFIG/ya.sh"
if [[ -f "$WRAPPER_FILE" ]]; then
    skip "ya.sh wrapper 已存在"
else
    install "创建 ya.sh cd-on-exit wrapper"
cat > "$WRAPPER_FILE" << 'WRAPPER'
#!/bin/bash
# Managed by OS Init
# Yazi wrapper: cd into the directory yazi was in when it exited
# Usage: source this file, then use `ya` instead of `yazi`
# Or add to .zshrc/.bashrc:  function ya() { ... }

function ya() {
    local tmp
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
WRAPPER
fi

YAZI_SHELL_BLOCK="$(cat <<'EOF'
if [ -f "$HOME/.config/yazi/ya.sh" ]; then
    . "$HOME/.config/yazi/ya.sh"
fi
EOF
)"
os_init_upsert_shell_block "yazi" "$YAZI_SHELL_BLOCK"

echo ""
echo "=== Yazi $(os_init_text "安装完成" "installation complete") ==="
echo ""
os_init_text "打开新终端后可用 yazi，或使用 ya 启用退出后 cd 到目标目录。" "Open a new terminal to use yazi, or use ya for cd-on-exit."

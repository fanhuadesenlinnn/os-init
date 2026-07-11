#!/bin/bash
set -euo pipefail

# Install macOS command-line tools via Homebrew formulae.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(
    bat eza ripgrep fd fzf gh htop iftop jq mise nmap nushell
    rsync shellcheck tmux uv wget zoxide ffmpeg imagemagick
    gallery-dl yt-dlp stylua tree-sitter-cli nload bind herdr llmfit
)
parse_update_flag "$@"
COMPONENTS=("${_CLEAN_ARGS[@]}")
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
    COMPONENTS=("${ALL_COMPONENTS[@]}")
fi

want() {
    local c
    for c in "${COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

known_component() {
    local c
    for c in "${ALL_COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

formula_label() {
    case "$1" in
        bat) echo "bat" ;;
        eza) echo "eza" ;;
        ripgrep) echo "ripgrep" ;;
        fd) echo "fd" ;;
        fzf) echo "fzf" ;;
        gh) echo "GitHub CLI" ;;
        htop) echo "htop" ;;
        iftop) echo "iftop" ;;
        jq) echo "jq" ;;
        mise) echo "mise" ;;
        nmap) echo "nmap" ;;
        nushell) echo "Nushell" ;;
        rsync) echo "rsync" ;;
        shellcheck) echo "ShellCheck" ;;
        tmux) echo "tmux" ;;
        uv) echo "uv" ;;
        wget) echo "wget" ;;
        zoxide) echo "zoxide" ;;
        ffmpeg) echo "FFmpeg" ;;
        imagemagick) echo "ImageMagick" ;;
        gallery-dl) echo "gallery-dl" ;;
        yt-dlp) echo "yt-dlp" ;;
        stylua) echo "StyLua" ;;
        tree-sitter-cli) echo "tree-sitter CLI" ;;
        nload) echo "nload" ;;
        bind) echo "BIND DNS tools" ;;
        herdr) echo "herdr" ;;
        llmfit) echo "llmfit" ;;
        *) echo "$1" ;;
    esac
}

formula_installed() {
    brew_list --formula "$1" &>/dev/null
}

install_formula() {
    local formula="$1" label
    label="$(formula_label "$formula")"
    if formula_installed "$formula"; then
        if [[ "$UPDATE" == true ]]; then
            update "更新 $label"
            brew_upgrade "$formula" 2>/dev/null || skip "$label 已是最新"
        else
            skip "$label 已安装"
        fi
	else
		install "安装 $label"
		brew_install "$formula"
		os_init_mark_user_ownership "macos-formula-${formula//[^A-Za-z0-9._-]/-}"
	fi
}

uninstall_formula() {
    local formula="$1" label
    label="$(formula_label "$formula")"
	if formula_installed "$formula" && os_init_user_owned "macos-formula-${formula//[^A-Za-z0-9._-]/-}"; then
		remove "卸载 $label"
		brew_uninstall "$formula" 2>/dev/null || true
		os_init_forget_user_ownership "macos-formula-${formula//[^A-Za-z0-9._-]/-}"
	elif formula_installed "$formula"; then
		warn "保留非 OS Init 安装的 $label"
    else
        skip "$label 未安装"
    fi
}

configure_zoxide_zsh() {
    local content
    content="$(cat <<'EOF'
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi
EOF
)"
    os_init_upsert_zsh_block "zoxide" "$content"
}

configure_mise_zsh() {
    local content
    content="$(cat <<'EOF'
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi
EOF
)"
    os_init_upsert_zsh_block "mise" "$content"
}

require_macos
if [[ "$UNINSTALL" == true ]] && ! command -v brew &>/dev/null; then
	warn "未安装 Homebrew，无法卸载 formula；不会为了卸载而安装 Homebrew"
	exit 0
fi
ensure_brew

for c in "${COMPONENTS[@]}"; do
    known_component "$c" || die "未知 macOS 命令行组件: $c"
done

TITLE="$(os_init_text "安装" "install")"
[[ "$UPDATE" == true ]] && TITLE="$(os_init_text "更新" "update")"
[[ "$UNINSTALL" == true ]] && TITLE="$(os_init_text "卸载" "uninstall")"
echo "=== $(os_init_text "macOS 命令行工具" "macOS CLI Tools") $TITLE ==="
echo "  $(os_init_text "组件" "Components"): ${COMPONENTS[*]}"
echo ""

STEP=0
TOTAL=0
for c in "${ALL_COMPONENTS[@]}"; do
    want "$c" && TOTAL=$((TOTAL + 1))
done
next() { STEP=$((STEP + 1)); echo "[$STEP/$TOTAL] $1..."; }

for formula in "${ALL_COMPONENTS[@]}"; do
    want "$formula" || continue
    next "$(formula_label "$formula")"
    if [[ "$UNINSTALL" == true ]]; then
        uninstall_formula "$formula"
    else
        install_formula "$formula"
    fi
done

if want "zoxide"; then
    if [[ "$UNINSTALL" == true ]]; then
        os_init_remove_zsh_block "zoxide"
    else
        configure_zoxide_zsh
    fi
fi

if want "mise"; then
    if [[ "$UNINSTALL" == true ]]; then
        os_init_remove_zsh_block "mise"
    else
        configure_mise_zsh
    fi
fi

echo ""
echo "=== $(os_init_text "macOS 命令行工具" "macOS CLI Tools") $TITLE $(os_init_text "完成" "complete") ==="

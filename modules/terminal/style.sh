#!/bin/bash
set -euo pipefail

# Install terminal appearance templates and safe shell aliases.
# The prompt selects rich/simple/plain at shell startup so SSH and TTY sessions
# stay readable even when the local graphical terminal looks colorful.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(style)
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

validate_components() {
    local c
    for c in "${COMPONENTS[@]}"; do
        case "$c" in
            style) ;;
            *) die "$(os_init_text "未知终端样式组件: $c" "unknown terminal style component: $c")" ;;
        esac
    done
}

terminal_config_dir() {
    local home
    home="$(real_home)"
    [[ -n "$home" ]] || die "$(os_init_text "无法确定用户 HOME" "unable to determine user HOME")"
    printf '%s\n' "$home/.config/os-init/terminal"
}

backup_user_file_once() {
    local file="$1" backup
    [[ -f "$file" ]] || return 0
    backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "$backup"
    os_init_reown_user_file "$backup"
    warn "$(os_init_text "已备份 $file -> $backup" "backed up $file -> $backup")"
}

install_template() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    [[ -f "$src" ]] || die "$(os_init_text "缺少内置模板: $src" "missing bundled template: $src")"

    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        skip "$dst already up to date"
        return 0
    fi

    if [[ -f "$dst" ]]; then
        backup_user_file_once "$dst"
        update "$(os_init_text "更新 $dst" "updating $dst")"
    else
        install "$(os_init_text "写入 $dst" "writing $dst")"
    fi
    cp "$src" "$dst"
    os_init_reown_user_file "$dst"
}

install_starship_templates() {
    local dir
    dir="$(terminal_config_dir)"
    install_template "$SCRIPT_DIR/starship-rich.toml" "$dir/starship-rich.toml"
    install_template "$SCRIPT_DIR/starship-simple.toml" "$dir/starship-simple.toml"
    install_template "$SCRIPT_DIR/starship-plain.toml" "$dir/starship-plain.toml"
}

terminal_alias_block() {
    local default_aliases default_bat_theme
    default_aliases="${OS_INIT_TERMINAL_ENABLE_ALIASES:-1}"
    default_bat_theme="${OS_INIT_TERMINAL_BAT_THEME:-Catppuccin Mocha}"
    cat <<EOF
: "\${OS_INIT_TERMINAL_ENABLE_ALIASES:=${default_aliases}}"
: "\${OS_INIT_TERMINAL_BAT_THEME:=${default_bat_theme}}"
export OS_INIT_TERMINAL_ENABLE_ALIASES OS_INIT_TERMINAL_BAT_THEME

if [[ "\$-" == *i* && "\${OS_INIT_TERMINAL_ENABLE_ALIASES}" != "0" ]]; then
    if command -v eza >/dev/null 2>&1; then
        alias ls='eza --group-directories-first'
        alias ll='eza -lah --group-directories-first --git'
        alias la='eza -la --group-directories-first'
        alias tree='eza --tree --group-directories-first'
    else
        alias ll='ls -lah'
        alias la='ls -la'
    fi

    if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
        alias bat='batcat'
    fi
    if command -v bat >/dev/null 2>&1; then
        export BAT_THEME="\${BAT_THEME:-\${OS_INIT_TERMINAL_BAT_THEME}}"
    fi
fi
EOF
}

install_shell_blocks() {
    os_init_upsert_interactive_shell_block "terminal-style" "$(terminal_alias_block)"
    os_init_upsert_zsh_block "starship" "$(os_init_starship_block_content zsh)"
    os_init_upsert_bash_block "starship" "$(os_init_starship_block_content bash)"
}

uninstall_style() {
    local dir
    dir="$(terminal_config_dir)"
    os_init_remove_interactive_shell_block "terminal-style"

    if [[ -d "$dir" ]]; then
        remove "$(os_init_text "删除 os-init 终端样式模板" "removing os-init terminal style templates")"
        rm -f "$dir/starship-rich.toml" "$dir/starship-simple.toml" "$dir/starship-plain.toml"
    else
        skip "$dir not found"
    fi
}

validate_components

TITLE="$(os_init_text "安装" "setup")"
[[ "$UNINSTALL" == true ]] && TITLE="$(os_init_text "卸载" "uninstall")"
echo "=== $(os_init_text "终端样式" "Terminal Style") $TITLE ==="
echo "  $(os_init_text "组件" "Components"): ${COMPONENTS[*]}"
echo ""

if [[ "$UNINSTALL" == true ]]; then
    want "style" && uninstall_style
    echo ""
    echo "=== $(os_init_text "终端样式卸载完成" "Terminal style uninstall complete") ==="
    exit 0
fi

if want "style"; then
    echo "[1/1] $(os_init_text "终端样式模板" "terminal style templates")..."
    install_starship_templates
    install_shell_blocks
fi

echo ""
echo "=== $(os_init_text "终端样式安装完成" "Terminal style setup complete") ==="
echo "  $(os_init_text "模式" "Mode"): ${OS_INIT_TERMINAL_STYLE:-auto}"
echo ""
os_init_text "打开新终端生效；SSH 会自动使用 simple，TTY 会自动使用 plain。" "Open a new terminal to apply it; SSH uses simple automatically, and TTY uses plain."

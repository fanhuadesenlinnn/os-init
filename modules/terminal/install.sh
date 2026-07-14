#!/bin/bash
set -euo pipefail

# Install terminal tools: ncdu
# Author: Dusan Panic <dpanic@gmail.com>
# Safe to re-run -- idempotent
#
# Usage:
#   ./install.sh
#   ./install.sh ncdu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

ALL_COMPONENTS=(ncdu)
parse_update_flag "$@"
COMPONENTS=("${_CLEAN_ARGS[@]}")
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
    COMPONENTS=("${ALL_COMPONENTS[@]}")
fi

validate_components() {
    local component supported supported_component
    for component in "${COMPONENTS[@]}"; do
        supported=false
        for supported_component in "${ALL_COMPONENTS[@]}"; do
            if [[ "$component" == "$supported_component" ]]; then
                supported=true
                break
            fi
        done
        [[ "$supported" == true ]] || die "$(os_init_text "未知终端组件: $component" "unknown terminal component: $component")"
    done
}
validate_components

want() {
    local c
    for c in "${COMPONENTS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

STEP=0
count_steps() {
    local total=0
    for c in "${ALL_COMPONENTS[@]}"; do want "$c" && total=$((total + 1)); done
    echo "$total"
}
TOTAL=$(count_steps)
next() { STEP=$((STEP + 1)); echo "[$STEP/$TOTAL] $1..."; }

TITLE="$(os_init_text "安装" "setup")"
[[ "$UNINSTALL" == true ]] && TITLE="$(os_init_text "卸载" "uninstall")"
echo "=== $(os_init_text "终端工具" "Terminal Tools") $TITLE ==="
echo "  $(os_init_text "组件" "Components"): ${COMPONENTS[*]}"
echo ""

if [[ "$UNINSTALL" == true ]]; then
    if want "ncdu"; then
        echo "$(os_init_text "[删除]" "[REMOVE]") ncdu..."
		if command -v ncdu &>/dev/null && os_init_package_owned "ncdu-package"; then
			remove "removing ncdu"
			pkg_remove ncdu 2>/dev/null || true
			os_init_forget_package_ownership "ncdu-package"
		elif command -v ncdu &>/dev/null; then
			warn "保留非 OS Init 安装的 ncdu"
        else
            skip "ncdu not installed"
        fi
    fi

    echo ""
    echo "=== $(os_init_text "终端工具卸载完成" "Terminal tools uninstall complete") ==="
    exit 0
fi

if want "ncdu"; then
    next "ncdu"

    if command -v ncdu &>/dev/null && [[ "$UPDATE" == true ]]; then
        update "updating ncdu"
        pkg_install ncdu
    elif command -v ncdu &>/dev/null; then
        skip "ncdu $(ncdu --version 2>/dev/null | head -1 || echo '?') already installed"
    else
		install "installing ncdu"
		pkg_install ncdu
		os_init_mark_package_ownership "ncdu-package"
    fi
fi

echo ""
echo "=== $(os_init_text "终端工具安装完成" "Terminal tools setup complete") ==="
echo "  $(os_init_text "已处理" "Processed"): ${COMPONENTS[*]}"
echo ""
os_init_text "快速开始:" "Quick start:"
want "ncdu" && echo "  ncdu  -- $(os_init_text "交互式磁盘占用分析" "interactive disk usage analyzer")"

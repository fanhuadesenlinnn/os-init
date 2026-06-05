#!/bin/bash
set -euo pipefail

# Thin os-init wrapper for the embedded ArchDevKit project.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHDEVKIT_DIR="$SCRIPT_DIR/vendor"
ARCHDEVKIT_OVERRIDE_FILE=""

ARCHDEVKIT_OVERRIDE_KEYS=(
    INSTALL_ARCHLINUXCN
    ENABLE_DNS
    ENABLE_OPS_TOOLKIT
    ENABLE_PROXY
    PROXY_CORE
    PROXY_AUTO_ENABLE_SERVICE
    ENABLE_METACUBEXD
    GPU_TYPE
    ENABLE_SDDM
    HYPRLAND_CONFIG_MODE
    ENABLE_FCITX5
    INPUT_METHOD_ENGINE
    RIME_SCHEMA
    INSTALL_RIME_CONFIG
    BROWSER_PACKAGE
    BROWSER_APP
)

# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

require_archdevkit() {
    [[ -x "$ARCHDEVKIT_DIR/install.sh" ]] || die "ArchDevKit 子系统缺少入口: $ARCHDEVKIT_DIR/install.sh"
    is_arch || die "ArchDevKit 仅支持 Arch Linux 系统"
}

run_archdevkit() {
    (
        cd "$ARCHDEVKIT_DIR"
        bash install.sh "$@"
    )
}

cleanup_archdevkit_override_file() {
    [[ -n "${ARCHDEVKIT_OVERRIDE_FILE:-}" ]] || return 0
    rm -f "$ARCHDEVKIT_OVERRIDE_FILE"
}

escape_archdevkit_config_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf "%s" "$value"
}

build_archdevkit_override_file() {
    local key env_key value has_override=0 tmp_file
    tmp_file="$(mktemp)"

    for key in "${ARCHDEVKIT_OVERRIDE_KEYS[@]}"; do
        env_key="OS_INIT_ARCHDEVKIT_${key}"
        if [[ -n "${!env_key+x}" ]]; then
            value="${!env_key}"
            printf '%s="%s"\n' "$key" "$(escape_archdevkit_config_value "$value")" >> "$tmp_file"
            has_override=1
        fi
    done

    if [[ "$has_override" -eq 1 ]]; then
        ARCHDEVKIT_OVERRIDE_FILE="$tmp_file"
        trap cleanup_archdevkit_override_file EXIT
    else
        rm -f "$tmp_file"
    fi
}

normalize_archdevkit_target() {
    case "$1" in
        ops_toolkit) echo "ops-toolkit" ;;
        shell_zsh) echo "shell" ;;
        desktop_hyprland) echo "desktop" ;;
        *) echo "$1" ;;
    esac
}

run_archdevkit_target() {
    local target="$1" mode="$2"
    target="$(normalize_archdevkit_target "$target")"

    case "$target" in
        status)
            run_archdevkit status --verbose
            ;;
        doctor)
            run_archdevkit doctor
            ;;
        config-init)
            run_archdevkit config init
            ;;
        config-show)
            run_archdevkit config show
            ;;
        config-validate)
            run_archdevkit config validate
            ;;
        reset-state)
            run_archdevkit reset-state all
            ;;
        base|dns|archlinuxcn|git|ops-toolkit|runtime|nvim|docker|fonts|shell|proxy|desktop|dev|workstation)
            local config_args=()
            if [[ -n "${ARCHDEVKIT_OVERRIDE_FILE:-}" ]]; then
                config_args=(--config-file "$ARCHDEVKIT_OVERRIDE_FILE")
            fi
            case "$mode" in
                --uninstall)
                    die "ArchDevKit 原项目不提供卸载流程；如需重跑请使用 ArchDevKit reset-state 或 --update"
                    ;;
                --update)
                    run_archdevkit install "$target" "${config_args[@]}" --yes --force
                    ;;
                *)
                    run_archdevkit install "$target" "${config_args[@]}" --yes
                    ;;
            esac
            ;;
        *)
            die "未知 ArchDevKit 目标: $target"
            ;;
    esac
}

main() {
    require_archdevkit
    build_archdevkit_override_file

    local mode="" arg
    local targets=()
    for arg in "$@"; do
        case "$arg" in
            --update|--uninstall)
                mode="$arg"
                ;;
            *)
                targets+=("$arg")
                ;;
        esac
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=(menu)
    fi

    for arg in "${targets[@]}"; do
        if [[ "$arg" == "menu" ]]; then
            run_archdevkit menu
        else
            run_archdevkit_target "$arg" "$mode"
        fi
    done
}

main "$@"

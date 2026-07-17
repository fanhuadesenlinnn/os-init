#!/bin/bash
set -euo pipefail

# Install mise and a shared Node.js/Python/Go runtime set. macOS uses Homebrew;
# Arch uses pacman when its current architecture repository provides mise and
# otherwise falls back to the official mise.run installer in ~/.local/bin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

home="$(real_home)"
env_file="$home/.config/os-init/mise-china.env"
mise_config="$home/.config/mise/config.toml"
mise_data="$home/.local/share/mise"
mise_binary="${MISE_INSTALL_PATH:-$home/.local/bin/mise}"
SUPPORTED_COMPONENTS=(core go python node)
COMPONENTS=()

want() {
    local component="$1" selected
    for selected in "${COMPONENTS[@]}"; do
        [[ "$selected" == "$component" ]] && return 0
    done
    return 1
}

mise_exec() {
    local binary
    if command -v mise >/dev/null 2>&1; then
        binary="$(command -v mise)"
    elif [[ -x "$mise_binary" ]]; then
        binary="$mise_binary"
    else
        die "mise 尚未安装，请先安装 mise core"
    fi
    run_with_github_git_proxy env \
        -u MISE_NODE_VERSION -u MISE_PYTHON_VERSION -u MISE_GO_VERSION \
        "$binary" "$@"
}

mise_uses_native_package() {
    if is_macos; then
        return 0
    fi
    is_arch || return 1
    pkg_is_installed mise && return 0
    command -v pacman >/dev/null 2>&1 && pacman -Si mise >/dev/null 2>&1
}

mise_package_key() {
    if is_macos; then
        echo "macos-formula-mise"
    else
        echo "arch-package-mise"
    fi
}

mise_package_installed() {
    if is_macos; then
        brew_list --formula mise &>/dev/null
    else
        pkg_is_installed mise
    fi
}

mise_binary_owned() {
    [[ -f "$(os_init_user_state_dir)/ownership/user-path-mise-binary" ]]
}

install_mise_binary() {
    local version binary_dir
    binary_dir="$(dirname "$mise_binary")"

    if [[ -x "$mise_binary" && "$UPDATE" != true ]]; then
        skip "mise 已通过官方安装脚本安装: $mise_binary"
        export PATH="$binary_dir:$PATH"
        return
    fi
    if [[ -x "$mise_binary" ]] && ! mise_binary_owned; then
        warn "保留非 OS Init 安装的 mise: $mise_binary"
        export PATH="$binary_dir:$PATH"
        return
    fi
    if [[ ! -e "$mise_binary" ]] && command -v mise >/dev/null 2>&1; then
        skip "mise already available at $(command -v mise)"
        return
    fi
    if [[ -e "$mise_binary" && ! -x "$mise_binary" ]] && ! mise_binary_owned; then
        die "refusing to replace unmanaged non-executable path: $mise_binary"
    fi

    command -v curl >/dev/null 2>&1 || die "安装 mise 需要 curl"
    version="${MISE_VERSION:-}"
    [[ -z "$version" ]] || version="v${version#v}"
    install "使用 mise 官方安装脚本安装${version:+ mise $version}"
    os_init_prepare_owned_user_path "mise-binary" "$mise_binary"
    mkdir -p "$binary_dir"
    if [[ -n "$version" ]]; then
        curl --fail --silent --show-error --location https://mise.run | \
            env MISE_INSTALL_PATH="$mise_binary" MISE_VERSION="$version" sh
    else
        curl --fail --silent --show-error --location https://mise.run | \
            env MISE_INSTALL_PATH="$mise_binary" sh
    fi
    [[ -x "$mise_binary" ]] || die "mise 官方安装脚本未生成可执行文件: $mise_binary"
    export PATH="$binary_dir:$PATH"
}

uninstall_mise_binary() {
    if mise_binary_owned; then
        os_init_restore_owned_user_path "mise-binary" "$mise_binary" || true
    elif [[ -e "$mise_binary" ]]; then
        warn "保留非 OS Init 安装的 mise: $mise_binary"
    else
        skip "mise 官方脚本安装的二进制不存在"
    fi
}

install_mise_package() {
    local key
    key="$(mise_package_key)"

    if mise_package_installed; then
        if [[ "$UPDATE" == true ]]; then
            update "更新 mise"
            if is_macos; then
                brew_upgrade mise 2>/dev/null || skip "mise 已是最新"
            else
                # Do not refresh only the package database here: Arch does not
                # support partial upgrades. Use the currently synced database.
                arch_run_pacman -Syu --needed --noconfirm mise
            fi
        else
            skip "mise 已安装"
        fi
        return
    fi

    install "安装 mise"
    if is_macos; then
        ensure_brew
        brew_install mise
    else
        # mise is available in the official Arch extra repository, so root
        # mode never needs an AUR build user for this module.
        arch_run_pacman -Syu --needed --noconfirm mise
    fi
    os_init_mark_package_ownership "$key"
}

uninstall_mise_package() {
    local key
    key="$(mise_package_key)"
    if mise_package_installed && os_init_package_owned "$key"; then
        remove "卸载由 OS Init 安装的 mise"
        pkg_remove mise 2>/dev/null || true
        os_init_forget_package_ownership "$key"
    elif mise_package_installed; then
        warn "mise 不是由 OS Init 安装，予以保留"
    else
        skip "mise 未安装"
    fi
}

remove_legacy_runtime_blocks() {
    local name
    for name in nvm fnm pyenv asdf; do
        os_init_remove_zsh_block "$name"
        os_init_remove_bash_block "$name"
    done
}

cleanup_legacy_system_go() {
    os_init_remove_shell_block "go"

    # Portable mise itself does not require sudo. Only attempt Linux migration
    # cleanup when the caller is root or another selected system module has
    # already primed sudo; otherwise leave the old, ownership-tracked resource
    # for a later privileged run.
    if ! is_macos && [[ "$(id -u)" != "0" ]] && ! command sudo -n true 2>/dev/null; then
        return
    fi

    if ! is_macos; then
        if os_init_owned_path "go-install-dir"; then
            remove "旧版 OS Init 管理的系统 Go"
            os_init_restore_owned_path "go-install-dir" "/usr/local/go" || true
        elif [[ -d /usr/local/go ]]; then
            warn "保留非 OS Init 管理的系统 Go: /usr/local/go"
        fi
    fi

    if pkg_is_installed go && os_init_package_owned "go-package"; then
        remove "旧版 OS Init 安装的系统 Go 包"
        pkg_remove go 2>/dev/null || true
        os_init_forget_package_ownership "go-package"
    elif pkg_is_installed go; then
        warn "保留非 OS Init 安装的系统 Go 包"
    fi
}

write_mise_china_env() {
    local content
    mkdir -p "$(dirname "$env_file")"
    os_init_prepare_owned_user_path "mise-china-env" "$env_file"
    content="$(cat <<EOF
export NPM_CONFIG_REGISTRY="${NPM_CONFIG_REGISTRY:-https://registry.npmmirror.com}"
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
EOF
)"
    printf '%s\n' "$content" > "$env_file"
}

resolve_mise_go_download_mirror() {
    local mirror
    mirror="${MISE_GO_DOWNLOAD_MIRROR:-https://dl.google.com/go}"
    mirror="${mirror%/}"
    case "$mirror" in
        https://golang.google.cn/dl)
            # golang.google.cn/dl is a download page and does not provide the
            # <archive>.sha256 sidecar format required by mise core:go.
            printf '%s\n' "https://dl.google.com/go"
            ;;
        *)
            printf '%s\n' "$mirror"
            ;;
    esac
}

configure_mise_settings() {
    local node_mirror go_mirror configured_go_mirror
    node_mirror="${MISE_NODE_MIRROR_URL:-https://npmmirror.com/mirrors/node/}"
    configured_go_mirror="${MISE_GO_DOWNLOAD_MIRROR:-https://dl.google.com/go}"
    go_mirror="$(resolve_mise_go_download_mirror)"
    if [[ "${configured_go_mirror%/}" != "$go_mirror" ]]; then
        warn "Go 下载地址 ${configured_go_mirror} 不兼容 mise 校验文件格式，改用 ${go_mirror}"
    fi
    os_init_prepare_owned_user_path "mise-config" "$mise_config"
    mise_exec settings set prefer_offline true
    mise_exec settings set node.corepack true
    mise_exec settings set node.mirror_url "$node_mirror"
    mise_exec settings set go.download_mirror "$go_mirror"
}

mise_runtime_version() {
    case "$1" in
        go) echo "${OS_INIT_MISE_GO_VERSION:-1.26}" ;;
        python) echo "${OS_INIT_MISE_PYTHON_VERSION:-3.13}" ;;
        node) echo "${OS_INIT_MISE_NODE_VERSION:-24}" ;;
        *) die "未知 mise 运行时: $1" ;;
    esac
}

mise_use_global_runtime() {
    local tool="$1" version="$2" node_mirror go_mirror
    node_mirror="${MISE_NODE_MIRROR_URL:-https://npmmirror.com/mirrors/node/}"
    go_mirror="$(resolve_mise_go_download_mirror)"
    if [[ "$tool" == "python" && -n "${GITHUB_PROXY:-}" ]]; then
        MISE_PYTHON_COMPILE="${MISE_PYTHON_COMPILE:-1}" \
        MISE_NODE_MIRROR_URL="$node_mirror" \
        MISE_GO_DOWNLOAD_MIRROR="$go_mirror" \
            mise_exec use --global "${tool}@${version}"
    else
        MISE_NODE_MIRROR_URL="$node_mirror" \
        MISE_GO_DOWNLOAD_MIRROR="$go_mirror" \
            mise_exec use --global "${tool}@${version}"
    fi
}

mise_use_global_runtime_from_official_source() {
    local tool="$1" version="$2"
    MISE_NODE_MIRROR_URL="https://nodejs.org/dist/" \
    MISE_GO_DOWNLOAD_MIRROR="https://dl.google.com/go" \
        mise_exec use --global "${tool}@${version}"
}

verify_mise_runtime() {
    local tool="$1" version="$2" tool_path bin_dir
    tool_path="$(mise_exec which "$tool")"
    [[ -x "$tool_path" ]] || die "mise ${tool} 可执行文件不存在"
    case "$tool" in
        go)
            "$tool_path" version | grep -Eq "go${version}(\\.|[[:space:]])" || die "mise Go 版本验证失败"
            ;;
        python)
            "$tool_path" --version | grep -Eq "Python ${version}(\\.|$)" || die "mise Python 版本验证失败"
            ;;
        node)
            "$tool_path" --version | grep -Eq "^v${version}(\\.|$)" || die "mise Node.js 版本验证失败"
            bin_dir="$(dirname "$tool_path")"
            # npm and corepack resolve node through /usr/bin/env. The current
            # non-interactive installer shell has not activated mise yet, so
            # make the freshly installed runtime visible while validating it.
            env PATH="$bin_dir:$PATH" "$bin_dir/npm" --version >/dev/null
            env PATH="$bin_dir:$PATH" "$bin_dir/corepack" --version >/dev/null
            ;;
    esac
}

install_mise_runtime() {
    local tool="$1" version created_data=false
    version="$(mise_runtime_version "$tool")"
    [[ -e "$mise_data" ]] || created_data=true

    install "通过 mise 安装用户级 ${tool}@${version}"
    if ! mise_use_global_runtime "$tool" "$version"; then
        if [[ "$tool" == "python" ]]; then
            die "mise 安装 python@${version} 失败；请检查系统编译依赖和上游下载状态"
        fi
        warn "${tool} 国内运行时镜像安装失败，使用官方源重试"
        if ! mise_use_global_runtime_from_official_source "$tool" "$version"; then
            die "mise 使用官方源安装 ${tool}@${version} 仍然失败"
        fi
        configure_mise_settings
    fi
    [[ "$created_data" == true ]] && os_init_mark_user_ownership "mise-data-dir"
    verify_mise_runtime "$tool" "$version"
}

uninstall_mise_runtime() {
    local tool="$1"
    if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$mise_binary" ]]; then
        skip "mise 未安装，无法找到由其管理的 ${tool}"
        return
    fi
    remove "从全局 mise 配置移除用户级 ${tool}"
    mise_exec unuse --global "$tool" 2>/dev/null || true
    mise_exec uninstall --all "$tool" 2>/dev/null || true
}

configure_mise_shells() {
    local zprofile_content profile_content zshrc_content bashrc_content mise_bin_dir
    if mise_uses_native_package && command -v mise >/dev/null 2>&1; then
        mise_bin_dir="$(dirname "$(command -v mise)")"
    else
        mise_bin_dir="$(dirname "$mise_binary")"
    fi
    zprofile_content="$(cat <<EOF
export PATH="$mise_bin_dir:\$PATH"
if command -v brew >/dev/null 2>&1; then
    eval "\$(brew shellenv)"
fi
if [[ -f "$env_file" ]]; then
    source "$env_file"
fi
if command -v mise >/dev/null 2>&1; then
    eval "\$(mise activate zsh --shims)"
fi
EOF
)"
    os_init_upsert_block "$home/.zprofile" "mise" "$zprofile_content"

    profile_content="$(cat <<EOF
export PATH="$mise_bin_dir:\$PATH"
if [ -f "$env_file" ]; then
    . "$env_file"
fi
if command -v mise >/dev/null 2>&1; then
    eval "\$(mise activate bash --shims)"
fi
EOF
)"
    os_init_upsert_block "$home/.profile" "mise" "$profile_content"

    zshrc_content="$(cat <<EOF
export PATH="$mise_bin_dir:\$PATH"
if [[ -f "$env_file" ]]; then
    source "$env_file"
fi
if command -v mise >/dev/null 2>&1; then
    eval "\$(mise activate zsh)"
fi
EOF
)"
    os_init_upsert_zsh_block "mise" "$zshrc_content"

    bashrc_content="$(cat <<EOF
export PATH="$mise_bin_dir:\$PATH"
if [[ -f "$env_file" ]]; then
    source "$env_file"
fi
if command -v mise >/dev/null 2>&1; then
    eval "\$(mise activate bash)"
fi
EOF
)"
    os_init_upsert_bash_block "mise" "$bashrc_content"
}

remove_mise_shells() {
    os_init_remove_block "$home/.zprofile" "mise"
    os_init_remove_block "$home/.profile" "mise"
    os_init_remove_zsh_block "mise"
    os_init_remove_bash_block "mise"
    os_init_restore_owned_user_path "mise-china-env" "$env_file" || true
}

purge_mise_data() {
    [[ "${PURGE_CONFIG:-0}" == "1" ]] || return 0
    warn "PURGE_CONFIG=1，将恢复安装前的 mise 配置并删除由 OS Init 创建的运行时数据"
    os_init_restore_owned_user_path "mise-config" "$mise_config" || true
    if os_init_user_owned "mise-data-dir"; then
        rm -rf "$mise_data"
        os_init_forget_user_ownership "mise-data-dir"
        remove "删除 OS Init 创建的 mise 运行时数据: $mise_data"
    else
        warn "保留非 OS Init 创建的 mise 运行时数据: $mise_data"
    fi
}

mise_main() {
    local title component
    parse_update_flag "$@"

    if [[ ${#_CLEAN_ARGS[@]} -eq 0 ]]; then
        COMPONENTS=(core go python node)
    else
        COMPONENTS=("${_CLEAN_ARGS[@]}")
    fi
    for component in "${COMPONENTS[@]}"; do
        case " ${SUPPORTED_COMPONENTS[*]} " in
            *" $component "*) ;;
            *) die "未知 mise 组件: $component" ;;
        esac
    done

    title="$(os_init_text "安装" "install")"
    [[ "$UPDATE" == true ]] && title="$(os_init_text "更新" "update")"
    [[ "$UNINSTALL" == true ]] && title="$(os_init_text "卸载" "uninstall")"
    echo "=== mise 用户开发环境 $title ==="
    echo "  $(os_init_text "组件" "Components"): ${COMPONENTS[*]}"
    echo ""

    if [[ "$UNINSTALL" == true ]]; then
        want "go" && uninstall_mise_runtime go
        want "python" && uninstall_mise_runtime python
        want "node" && uninstall_mise_runtime node
        if want "core"; then
            remove_mise_shells
            purge_mise_data
            if is_macos; then
                uninstall_mise_package
            elif is_arch; then
                # The available delivery may change after repository updates;
                # clean only whichever OS Init-owned source actually exists.
                uninstall_mise_package
                uninstall_mise_binary
            else
                uninstall_mise_binary
            fi
        fi
    else
        if want "core"; then
            if mise_uses_native_package; then
                install_mise_package
            else
                require_linux
                if is_arch; then
                    warn "当前 Arch 架构仓库不提供 mise，改用 mise 官方安装脚本"
                fi
                install_mise_binary
            fi
            remove_legacy_runtime_blocks
            cleanup_legacy_system_go
            write_mise_china_env
            configure_mise_settings
            configure_mise_shells
        fi
        want "go" && install_mise_runtime go
        want "python" && install_mise_runtime python
        want "node" && install_mise_runtime node
    fi

    echo ""
    echo "=== mise 用户开发环境 $title $(os_init_text "完成" "complete") ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    mise_main "$@"
fi

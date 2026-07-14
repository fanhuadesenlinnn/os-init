#!/bin/bash
set -euo pipefail

# Install mise and a shared Node.js/Python/Go runtime set on macOS or Arch Linux.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

home="$(real_home)"
env_file="$home/.config/os-init/mise-china.env"
mise_config="$home/.config/mise/config.toml"
mise_data="$home/.local/share/mise"

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
                sudo_env pacman -S --needed --noconfirm mise
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
        sudo_env pacman -S --needed --noconfirm mise
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
    mise settings set prefer_offline true
    mise settings set node.corepack true
    mise settings set node.mirror_url "$node_mirror"
    mise settings set go.download_mirror "$go_mirror"
}

mise_use_global_runtimes() {
    local node_version="$1" python_version="$2" go_version="$3"
    local node_mirror go_mirror
    node_mirror="${MISE_NODE_MIRROR_URL:-https://npmmirror.com/mirrors/node/}"
    go_mirror="$(resolve_mise_go_download_mirror)"
    MISE_NODE_MIRROR_URL="$node_mirror" \
    MISE_GO_DOWNLOAD_MIRROR="$go_mirror" \
        mise use --global "node@${node_version}" "python@${python_version}" "go@${go_version}"
}

mise_use_global_runtimes_from_official_sources() {
    local node_version="$1" python_version="$2" go_version="$3"
    MISE_NODE_MIRROR_URL="https://nodejs.org/dist/" \
    MISE_GO_DOWNLOAD_MIRROR="https://dl.google.com/go" \
        mise use --global "node@${node_version}" "python@${python_version}" "go@${go_version}"
}

install_mise_runtimes() {
    local node_version python_version go_version created_data=false
    node_version="${MISE_NODE_VERSION:-24}"
    python_version="${MISE_PYTHON_VERSION:-3.13}"
    go_version="${MISE_GO_VERSION:-1.24}"

    [[ -e "$mise_data" ]] || created_data=true
    install "通过 mise 安装 Node.js ${node_version}、Python ${python_version} 和 Go ${go_version}"
    if ! mise_use_global_runtimes "$node_version" "$python_version" "$go_version"; then
        warn "运行时镜像安装失败，使用官方源重试"
        mise settings set node.mirror_url "https://nodejs.org/dist/"
        mise settings set go.download_mirror "https://dl.google.com/go"
        if ! mise_use_global_runtimes_from_official_sources "$node_version" "$python_version" "$go_version"; then
            die "mise 使用官方源安装运行时仍然失败"
        fi
        configure_mise_settings
    fi
    [[ "$created_data" == true ]] && os_init_mark_user_ownership "mise-data-dir"

    mise exec -- node --version | grep -Eq "^v${node_version}(\\.|$)" || die "mise Node.js 版本验证失败"
    mise exec -- python --version | grep -Eq "Python ${python_version}(\\.|$)" || die "mise Python 版本验证失败"
    mise exec -- go version | grep -Eq "go${go_version}(\\.|[[:space:]])" || die "mise Go 版本验证失败"
    mise exec -- npm --version >/dev/null
    mise exec -- corepack --version >/dev/null
    mise which node >/dev/null
    mise which python >/dev/null
    mise which go >/dev/null
}

configure_mise_shells() {
    local zprofile_content profile_content zshrc_content bashrc_content
    zprofile_content="$(cat <<EOF
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
    local title
    parse_update_flag "$@"

    if ! is_macos && ! is_arch; then
        die "mise 模块仅支持 macOS 和 Arch Linux"
    fi

    title="$(os_init_text "安装" "install")"
    [[ "$UPDATE" == true ]] && title="$(os_init_text "更新" "update")"
    [[ "$UNINSTALL" == true ]] && title="$(os_init_text "卸载" "uninstall")"
    echo "=== mise + Node.js + Python + Go $title ==="
    echo ""

    if [[ "$UNINSTALL" == true ]]; then
        remove_mise_shells
        purge_mise_data
        uninstall_mise_package
    else
        install_mise_package
        remove_legacy_runtime_blocks
        write_mise_china_env
        configure_mise_settings
        install_mise_runtimes
        configure_mise_shells
    fi

    echo ""
    echo "=== mise + Node.js + Python + Go $title $(os_init_text "完成" "complete") ==="
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    mise_main "$@"
fi

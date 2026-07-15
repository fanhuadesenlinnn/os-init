#!/usr/bin/env bash
# Sourced by modules/lib.sh.

pkg_update() {
    if is_macos; then
        run_brew update
    elif [[ "$OS_FAMILY" == "debian" ]]; then
        sudo_env apt-get update -qq
    elif [[ "$OS_FAMILY" == "arch" ]]; then
        sudo_env pacman -Sy --noconfirm
    elif [[ "$OS_FAMILY" == "redhat" ]]; then
        if command -v dnf &>/dev/null; then
            sudo_env dnf makecache -y
        elif command -v yum &>/dev/null; then
            sudo_env yum makecache -y
        else
            die "RedHat 系统未找到 dnf/yum"
        fi
    else
        die "不支持的包管理器家族: ${OS_FAMILY}"
    fi
}

ensure_brew() {
    export_homebrew_env
    if command -v brew &>/dev/null; then
        return
    fi
    install "安装 Homebrew"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")"
	download_file_verified "$(resource_url HOMEBREW_INSTALL_URL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")" "$tmp" "${HOMEBREW_INSTALL_SHA256:-}"
    NONINTERACTIVE=1 /bin/bash "$tmp"
    rm -f "$tmp"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    export_homebrew_env
}

enable_redhat_epel() {
    local manager id="" version_id="" major=""
    manager="$1"
    if rpm -q epel-release &>/dev/null; then
        return 0
    fi
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="$(lower "${ID:-}")"
        version_id="${VERSION_ID:-}"
    fi
    [[ "$id" != "fedora" ]] || return 1

    install "启用 EPEL 软件源以补充 RedHat 系软件包"
    if sudo_env "$manager" install -y epel-release; then
        return 0
    fi

    major="${version_id%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || return 1
    sudo_env "$manager" install -y \
        "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major}.noarch.rpm"
}

redhat_install_packages() {
    local manager
    if command -v dnf &>/dev/null; then
        manager=dnf
    elif command -v yum &>/dev/null; then
        manager=yum
    else
        die "RedHat 系统未找到 dnf/yum"
    fi

    if sudo_env "$manager" install -y "$@"; then
        return 0
    fi
    enable_redhat_epel "$manager" || die "RedHat 基础仓库缺少软件包且无法启用 EPEL: $*"
    sudo_env "$manager" install -y "$@"
}

pkg_install() {
    if is_macos; then
        brew_install "$@"
    elif [[ "$OS_FAMILY" == "debian" ]]; then
        pkg_update
        sudo_env apt-get install -y "$@"
    elif [[ "$OS_FAMILY" == "arch" ]]; then
        arch_install_packages_or_aur "$@"
    elif [[ "$OS_FAMILY" == "redhat" ]]; then
        redhat_install_packages "$@"
    else
        die "不支持的包管理器家族: ${OS_FAMILY}"
    fi
}

pkg_remove() {
    if is_macos; then
        if command -v brew &>/dev/null; then
            brew_uninstall "$@" 2>/dev/null || true
        fi
    elif [[ "$OS_FAMILY" == "debian" ]]; then
        sudo_env apt-get remove -y "$@"
    elif [[ "$OS_FAMILY" == "arch" ]]; then
        sudo_env pacman -Rns --noconfirm "$@"
    elif [[ "$OS_FAMILY" == "redhat" ]]; then
        if command -v dnf &>/dev/null; then
            sudo_env dnf remove -y "$@"
        elif command -v yum &>/dev/null; then
            sudo_env yum remove -y "$@"
        else
            die "RedHat 系统未找到 dnf/yum"
        fi
    else
        die "不支持的包管理器家族: ${OS_FAMILY}"
    fi
}

pkg_is_installed() {
    local pkg="$1"
    if is_macos; then
        brew_list "$pkg" &>/dev/null
    elif [[ "$OS_FAMILY" == "debian" ]]; then
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
    elif [[ "$OS_FAMILY" == "arch" ]]; then
        pacman -Q "$pkg" &>/dev/null
    elif [[ "$OS_FAMILY" == "redhat" ]]; then
        rpm -q "$pkg" &>/dev/null
    else
        return 1
    fi
}

is_macos() { [[ "$OS" == "macos" ]]; }
is_linux() { [[ "$OS" == "linux" ]]; }
is_arch() { [[ "$OS_FAMILY" == "arch" ]]; }
is_debian() { [[ "$OS_FAMILY" == "debian" ]]; }
is_redhat() { [[ "$OS_FAMILY" == "redhat" ]]; }
is_systemd() { [[ "$INIT_SYSTEM" == "systemd" ]]; }

_ARCH_PACKAGE_DATABASE_SYNCED=false
arch_sync_package_database() {
    is_arch || return 0
    [[ "$_ARCH_PACKAGE_DATABASE_SYNCED" == true ]] && return 0
    sudo_env pacman -Sy --noconfirm
    _ARCH_PACKAGE_DATABASE_SYNCED=true
}

arch_package_available() {
    local package="$1"
    is_arch || return 1
    arch_sync_package_database
    pacman -Si "$package" &>/dev/null
}

arch_package_installed() {
    local package="$1"
    is_arch || return 1
    pacman -Q "$package" &>/dev/null
}

arch_pacman_install() {
    [[ "$#" -gt 0 ]] || return 0
    install "通过 pacman 安装: $*"
    arch_sync_package_database
    sudo_env pacman -S --needed --noconfirm "$@"
}

arch_aur_helper_command() {
    if command -v paru &>/dev/null; then
        echo "paru"
        return 0
    fi
    if command -v yay &>/dev/null; then
        echo "yay"
        return 0
    fi
    return 1
}

run_as_real_user() {
    local user home
    if [[ "$(id -u)" != "0" ]]; then
        "$@"
        return
    fi

    user="$(real_user)"
    home="$(real_home)"
    [[ -n "$user" && "$user" != "root" ]] || die "AUR 构建需要普通用户"
    [[ -n "$home" ]] || die "无法确定普通用户 HOME"

    if command -v sudo &>/dev/null; then
        command sudo -u "$user" -H env HOME="$home" "$@"
    elif command -v runuser &>/dev/null; then
        runuser -u "$user" -- env HOME="$home" "$@"
    else
        die "需要 sudo 或 runuser 才能以普通用户构建 AUR 包"
    fi
}

arch_install_aur_via_makepkg() {
    local package="$1" tmp_dir package_dir aur_url user
    [[ -n "$package" ]] || die "AUR 包名为空"

    arch_pacman_install base-devel git
    command -v git &>/dev/null || die "缺少 git，无法克隆 AUR 包"
    command -v makepkg &>/dev/null || die "缺少 makepkg，无法构建 AUR 包"

    aur_url="https://aur.archlinux.org/${package}.git"
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/os-init-aur-${package}.XXXXXX")"
    package_dir="$tmp_dir/$package"
    user="$(real_user)"
    if [[ "$(id -u)" == "0" && -n "$user" && "$user" != "root" ]]; then
        chown "$user" "$tmp_dir" 2>/dev/null || true
    fi

    install "从 AUR 构建安装: $package"
    run_as_real_user git clone "$aur_url" "$package_dir" || {
        rm -rf "$tmp_dir"
        die "克隆 AUR 仓库失败: $aur_url"
    }
    run_as_real_user bash -c "cd \"\$1\" && makepkg -si --needed --noconfirm" bash "$package_dir" || {
        rm -rf "$tmp_dir"
        die "AUR 包安装失败: $package"
    }
    rm -rf "$tmp_dir"
}

arch_install_with_current_aur_helper() {
    local helper
    [[ "$#" -gt 0 ]] || return 0
    helper="$(arch_aur_helper_command)" || return 1
    install "通过 $helper 安装 AUR 包: $*"
    run_as_real_user "$helper" -S --needed --noconfirm "$@"
}

ensure_arch_aur_helpers() {
    local helper
    is_arch || return 0

    if command -v paru &>/dev/null; then
        helper="paru"
    elif command -v yay &>/dev/null; then
        helper="yay"
    else
        install "未检测到 paru/yay，自动安装 paru"
        if arch_package_available paru; then
            arch_pacman_install paru
        else
            arch_install_aur_via_makepkg paru
        fi
        helper="$(arch_aur_helper_command)" || die "AUR helper 安装失败"
    fi

    if ! command -v yay &>/dev/null; then
        warn "未检测到 yay，尝试补装 yay 供手动使用"
        if arch_package_available yay; then
            arch_pacman_install yay || true
        else
            arch_install_with_current_aur_helper yay || warn "yay 安装失败，后续继续使用 $helper"
        fi
    fi

    helper="$(arch_aur_helper_command)" || die "AUR helper 不可用"
    skip "AUR helper 已就绪: $helper"
}

arch_install_packages_or_aur() {
    local package helper
    local pacman_packages=()
    local aur_packages=()

    [[ "$#" -gt 0 ]] || return 0
    is_arch || die "当前系统不是 Arch 系，不能使用 Arch 安装策略"

    for package in "$@"; do
        [[ -n "$package" ]] || die "软件包名为空"
        if arch_package_installed "$package"; then
            skip "软件包已安装: $package"
        elif arch_package_available "$package"; then
            pacman_packages+=("$package")
        else
            aur_packages+=("$package")
        fi
    done

    if [[ ${#pacman_packages[@]} -gt 0 ]]; then
        arch_pacman_install "${pacman_packages[@]}"
    fi

    if [[ ${#aur_packages[@]} -gt 0 ]]; then
        warn "pacman 源未提供: ${aur_packages[*]}，改用 AUR helper 安装"
        ensure_arch_aur_helpers
        helper="$(arch_aur_helper_command)" || die "AUR helper 不可用"
        arch_install_with_current_aur_helper "${aur_packages[@]}" || {
            warn "$helper 安装失败，回退到 makepkg 逐个安装"
            for package in "${aur_packages[@]}"; do
                arch_install_aur_via_makepkg "$package"
            done
        }
    fi
}

sudo_env() {
    if [[ "$(id -u)" == "0" ]]; then
        "$@"
    else
        if ! sudo -n -E "$@"; then
            warn "命令执行失败或 sudo 未授权: $*"
            return 1
        fi
    fi
}

export_homebrew_env() {
    is_macos || return 0
    [[ -n "${HOMEBREW_API_DOMAIN:-}" ]] && export HOMEBREW_API_DOMAIN
    [[ -n "${HOMEBREW_BOTTLE_DOMAIN:-}" ]] && export HOMEBREW_BOTTLE_DOMAIN
    [[ -n "${HOMEBREW_ARTIFACT_DOMAIN:-}" ]] && export HOMEBREW_ARTIFACT_DOMAIN
    [[ -n "${HOMEBREW_BREW_GIT_REMOTE:-}" ]] && export HOMEBREW_BREW_GIT_REMOTE
    [[ -n "${HOMEBREW_CORE_GIT_REMOTE:-}" ]] && export HOMEBREW_CORE_GIT_REMOTE
    [[ -n "${HOMEBREW_PIP_INDEX_URL:-}" ]] && export HOMEBREW_PIP_INDEX_URL
    export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
    export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
}

run_brew() {
    ensure_brew
    export_homebrew_env
    case "${1:-}" in
        update)
            command brew "$@"
            ;;
        *)
            HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}" command brew "$@"
            ;;
    esac
}

brew_install() {
    run_brew install "$@"
}

brew_upgrade() {
    run_brew upgrade "$@"
}

brew_uninstall() {
    export_homebrew_env
    command -v brew &>/dev/null || return 0
    HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}" command brew uninstall "$@"
}

brew_list() {
    export_homebrew_env
    command brew list "$@"
}

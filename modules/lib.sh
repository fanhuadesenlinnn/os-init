#!/bin/bash
# Shared helpers for all kickstart scripts
# Source from a module script: source "$REPO_DIR/lib.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

skip()    { echo -e "  ${GREEN}[跳过]${NC} $1"; }
install() { echo -e "  ${YELLOW}[安装]${NC} $1"; }
update()  { echo -e "  ${CYAN}[更新]${NC} $1"; }
remove()  { echo -e "  ${RED}[删除]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[警告]${NC} $1"; }
die()     { echo -e "  ${RED}[错误]${NC} $1" >&2; exit 1; }

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_INIT_REPO_DIR="${REPO_DIR:-$LIB_DIR}"

OS_INIT_CONFIG_KEYS=(
    OS_INIT_LANG OS_INIT_REGION OS_INIT_OFFLINE OS_INIT_FILES_DIR
    OS_INIT_PROXY HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
    DOWNLOAD_RETRY DOWNLOAD_TIMEOUT GITHUB_PROXY DOWNLOAD_URL_PROXY
    HOMEBREW_INSTALL_URL
    OH_MY_ZSH_REPO FZF_REPO STARSHIP_INSTALL_URL DIRENV_PACKAGE
    ZSH_AUTOSUGGESTIONS_REPO ZSH_SYNTAX_HIGHLIGHTING_REPO
    NVM_VERSION NVM_INSTALL_BASE NVM_INSTALL_URL FNM_INSTALL_URL
    DOCKER_DOWNLOAD_BASE DOCKER_CHANNEL DOCKER_VERSION DOCKER_COMPOSE_VERSION DOCKER_COMPOSE_DOWNLOAD_BASE
    DOCKER_TGZ_URL DOCKER_COMPOSE_DOWNLOAD_URL
    DOCKER_REGISTRY_MIRRORS DOCKER_INSECURE_REGISTRIES DOCKER_DATA_ROOT
    ENABLE_MIHOMO MIHOMO_PACKAGE MIHOMO_VERSION MIHOMO_DOWNLOAD_BASE MIHOMO_BINARY_SOURCE
    MIHOMO_DOWNLOAD_URL
    MIHOMO_SERVICE_NAME MIHOMO_CONFIG_DIR MIHOMO_CONFIG_FILE MIHOMO_CONFIG_SOURCE
    MIHOMO_MIXED_PORT MIHOMO_ALLOW_LAN MIHOMO_BIND_ADDRESS
    MIHOMO_CONTROLLER_HOST MIHOMO_CONTROLLER_PORT MIHOMO_DNS_LISTEN MIHOMO_SECRET
    MIHOMO_STATE_DIR MIHOMO_EXTERNAL_UI_DIR MIHOMO_AUTO_ENABLE_SERVICE
    ENABLE_METACUBEXD METACUBEXD_PACKAGE METACUBEXD_VERSION METACUBEXD_SOURCE METACUBEXD_REPO METACUBEXD_WEB_ROOT
    GO_VERSION GO_DOWNLOAD_BASE GO_VERSION_URL GO_DOWNLOAD_URL
    NVIM_DOWNLOAD_BASE NVIM_DOWNLOAD_URL
    LAZYGIT_VERSION LAZYGIT_DOWNLOAD_BASE LAZYGIT_DOWNLOAD_URL
    LAZYVIM_STARTER_REPO
    YAZI_DOWNLOAD_BASE YAZI_DOWNLOAD_URL
)

# Action flags: --update refreshes to latest, --uninstall removes
UPDATE=false
UNINSTALL=false
_CLEAN_ARGS=()
parse_update_flag() {
    UPDATE=false
    UNINSTALL=false
    _CLEAN_ARGS=()
    for a in "$@"; do
        if [[ "$a" == "--update" ]]; then
            UPDATE=true
        elif [[ "$a" == "--uninstall" ]]; then
            UNINSTALL=true
        else
            _CLEAN_ARGS+=("$a")
        fi
    done
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

detect_linux_family() {
    if [[ "$OS" != "linux" ]]; then
        echo "$OS"
        return
    fi

    local id="" id_like=""
    if [[ -r /etc/os-release ]]; then
        # /etc/os-release is defined as shell-compatible key=value data.
        # shellcheck disable=SC1091
        . /etc/os-release
        id="$(lower "${ID:-}")"
        id_like="$(lower "${ID_LIKE:-}")"
    fi

    case "$id" in
        arch|manjaro|endeavouros) echo "arch"; return ;;
        debian|ubuntu|linuxmint|kali) echo "debian"; return ;;
        rhel|centos|rocky|almalinux|fedora|oracle|oraclelinux|ol) echo "redhat"; return ;;
    esac

    case " $id_like " in
        *" arch "*) echo "arch"; return ;;
        *" debian "*|*" ubuntu "*) echo "debian"; return ;;
        *" rhel "*|*" fedora "*|*" centos "*) echo "redhat"; return ;;
    esac

    echo "unknown"
}

detect_init() {
    if [[ "$OS" != "linux" ]]; then
        echo "unknown"
    elif [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif command -v rc-service &>/dev/null; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

real_user() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        echo "$SUDO_USER"
    else
        id -un
    fi
}

real_home() {
    local user
    user="$(real_user)"
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        if command -v getent &>/dev/null; then
            getent passwd "$user" | cut -d: -f6
            return
        fi
        eval "printf '%s\n' ~$user"
        return
    fi
    echo "${HOME:-}"
}

OS="$(detect_os)"
OS_FAMILY="$(detect_linux_family)"
INIT_SYSTEM="$(detect_init)"

source_config_file() {
    local file="$1"
    if [[ -r "$file" ]]; then
        # shellcheck disable=SC1090
        source "$file"
    fi
}

export_proxy_env() {
    OS_INIT_PROXY="${OS_INIT_PROXY:-${os_init_proxy:-}}"
    HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
    HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
    ALL_PROXY="${ALL_PROXY:-${all_proxy:-}}"
    NO_PROXY="${NO_PROXY:-${no_proxy:-}}"

    if [[ -n "${OS_INIT_PROXY:-}" ]]; then
        HTTP_PROXY="${HTTP_PROXY:-$OS_INIT_PROXY}"
        HTTPS_PROXY="${HTTPS_PROXY:-$OS_INIT_PROXY}"
        ALL_PROXY="${ALL_PROXY:-$OS_INIT_PROXY}"
    fi

    export OS_INIT_PROXY HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export no_proxy="$NO_PROXY"
}

load_os_init_config() {
    local snapshot key value home
    snapshot="$(mktemp "${TMPDIR:-/tmp}/os-init-env.XXXXXX")" || die "无法创建临时配置快照"
    chmod 600 "$snapshot" 2>/dev/null || true

    for key in "${OS_INIT_CONFIG_KEYS[@]}"; do
        if eval '[[ ${'"$key"'+x} == x ]]'; then
            value="$(eval "printf '%s' \"\${$key}\"")"
            printf 'export %s=%q\n' "$key" "$value" >> "$snapshot"
        fi
    done

    source_config_file "$OS_INIT_REPO_DIR/config/defaults.env"
    source_config_file "/etc/os-init/config.env"
    home="$(real_home)"
    if [[ -n "$home" ]]; then
        source_config_file "$home/.config/os-init/config.env"
    fi

    if [[ -s "$snapshot" ]]; then
        # shellcheck disable=SC1090
        source "$snapshot"
    fi
    rm -f "$snapshot"

    for key in "${OS_INIT_CONFIG_KEYS[@]}"; do
        export "$key"
    done
    export_proxy_env
}

detect_platform() {
    OS="$(detect_os)"
    OS_FAMILY="$(detect_linux_family)"
    INIT_SYSTEM="$(detect_init)"
    export OS OS_FAMILY INIT_SYSTEM
}

is_family() { [[ "$OS_FAMILY" == "$1" ]]; }
require_linux() {
    is_linux || die "该模块只支持 Linux"
}
require_systemd() {
    require_linux
    is_systemd || die "该模块需要 systemd，当前 init=${INIT_SYSTEM}"
}

pkg_update() {
    if [[ "$OS" == "macos" ]]; then
        ensure_brew
        brew update
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
    if command -v brew &>/dev/null; then
        return
    fi
    install "安装 Homebrew"
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/homebrew-install.XXXXXX")"
    download_file "$(resource_url HOMEBREW_INSTALL_URL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")" "$tmp"
    /bin/bash "$tmp"
    rm -f "$tmp"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
}

pkg_install() {
    if [[ "$OS" == "macos" ]]; then
        ensure_brew
        brew install "$@"
    elif [[ "$OS_FAMILY" == "debian" ]]; then
        pkg_update
        sudo_env apt-get install -y "$@"
    elif [[ "$OS_FAMILY" == "arch" ]]; then
        sudo_env pacman -Sy --needed --noconfirm "$@"
    elif [[ "$OS_FAMILY" == "redhat" ]]; then
        if command -v dnf &>/dev/null; then
            sudo_env dnf install -y "$@"
        elif command -v yum &>/dev/null; then
            sudo_env yum install -y "$@"
        else
            die "RedHat 系统未找到 dnf/yum"
        fi
    else
        die "不支持的包管理器家族: ${OS_FAMILY}"
    fi
}

pkg_remove() {
    if [[ "$OS" == "macos" ]]; then
        ensure_brew
        brew uninstall "$@" 2>/dev/null || true
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
    if [[ "$OS" == "macos" ]]; then
        brew list "$pkg" &>/dev/null
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

cask_install() {
    if [[ "$OS" == "macos" ]]; then
        ensure_brew
        brew install --cask "$@"
    else
        echo "cask_install is macOS-only" >&2
        return 1
    fi
}

is_macos() { [[ "$OS" == "macos" ]]; }
is_linux() { [[ "$OS" == "linux" ]]; }
is_arch() { [[ "$OS_FAMILY" == "arch" ]]; }
is_debian() { [[ "$OS_FAMILY" == "debian" ]]; }
is_redhat() { [[ "$OS_FAMILY" == "redhat" ]]; }
is_systemd() { [[ "$INIT_SYSTEM" == "systemd" ]]; }

sudo_env() {
    if [[ "$(id -u)" == "0" ]]; then
        "$@"
    else
        sudo -E "$@"
    fi
}

resource_url() {
    local key="$1" fallback="$2" value
    value="${!key:-}"
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$fallback"
    fi
}

repo_url() {
    resource_url "$@"
}

render_url_proxy() {
    local proxy="$1" url="$2"
    if [[ "$proxy" == *"{url}"* ]]; then
        echo "${proxy//\{url\}/$url}"
    else
        echo "${proxy%/}/$url"
    fi
}

rewrite_github_url() {
    local url="$1"
    if [[ -z "${GITHUB_PROXY:-}" ]]; then
        echo "$url"
        return
    fi

    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*)
            render_url_proxy "$GITHUB_PROXY" "$url"
            ;;
        *)
            echo "$url"
            ;;
    esac
}

rewrite_download_url() {
    local url="$1" rewritten
    rewritten="$(rewrite_github_url "$url")"
    if [[ "$rewritten" != "$url" ]]; then
        echo "$rewritten"
        return
    fi

    case "$url" in
        http://*|https://*)
            if [[ -n "${DOWNLOAD_URL_PROXY:-}" ]]; then
                render_url_proxy "$DOWNLOAD_URL_PROXY" "$url"
            else
                echo "$url"
            fi
            ;;
        *)
            echo "$url"
            ;;
    esac
}

git_with_proxy() {
    local -a git_args=()
    if [[ -n "${HTTP_PROXY:-}" ]]; then
        git_args+=(-c "http.proxy=${HTTP_PROXY}")
    fi
    if [[ -n "${HTTPS_PROXY:-}" ]]; then
        git_args+=(-c "https.proxy=${HTTPS_PROXY}")
    fi
    git "${git_args[@]}" "$@"
}

github_latest_version() {
    local repo="$1" prefix="${2:-v}"
    local url latest
    url="$(rewrite_download_url "https://github.com/${repo}/releases/latest")"
    if command -v curl &>/dev/null; then
        latest="$(curl -fsSI "$url" 2>/dev/null | grep -i '^location:' | sed "s|.*/${prefix}||" | tr -d '\r\n')"
    elif command -v wget &>/dev/null; then
        latest="$(wget --server-response --spider "$url" 2>&1 | grep -i 'Location:' | tail -1 | sed "s|.*/${prefix}||" | tr -d '\r\n')"
    else
        die "需要 curl 或 wget 才能查询 GitHub 最新版本"
    fi
    [[ -n "$latest" ]] || die "无法获取 ${repo} 最新版本"
    echo "$latest"
}

git_clone_depth() {
    local depth="$1" url="$2" dest="$3"
    git_with_proxy clone --depth="$depth" "$(rewrite_download_url "$url")" "$dest"
}

download_file() {
    local url="$1" dest="$2"
    [[ "${OS_INIT_OFFLINE:-0}" == "1" ]] && die "离线模式禁止下载: $url"

    local final_url
    final_url="$(rewrite_download_url "$url")"
    mkdir -p "$(dirname "$dest")"
    if command -v curl &>/dev/null; then
        curl -fL --retry "${DOWNLOAD_RETRY:-3}" \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" \
            -o "$dest" "$final_url"
    elif command -v wget &>/dev/null; then
        wget --tries="${DOWNLOAD_RETRY:-3}" \
            --timeout="${DOWNLOAD_TIMEOUT:-30}" \
            -O "$dest" "$final_url"
    else
        die "需要 curl 或 wget 才能下载文件"
    fi
}

find_offline_file() {
    local filename="$1"
    local dir candidate
    local dirs=()
    [[ -n "${OS_INIT_FILES_DIR:-}" ]] && dirs+=("$OS_INIT_FILES_DIR")
    [[ -n "${SCRIPT_DIR:-}" ]] && dirs+=("$SCRIPT_DIR/files" "$SCRIPT_DIR")
    dirs+=("$OS_INIT_REPO_DIR/files")

    for dir in "${dirs[@]}"; do
        candidate="$dir/$filename"
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

download_or_offline_file() {
    local url="$1" dest="$2" filename="${3:-}"
    if [[ -z "$filename" ]]; then
        filename="$(basename "${url%%\?*}")"
    fi

    if [[ "${OS_INIT_OFFLINE:-0}" == "1" ]]; then
        local offline_file
        offline_file="$(find_offline_file "$filename")" || die "离线模式缺少文件: $filename"
        install "使用离线文件 $filename"
        mkdir -p "$(dirname "$dest")"
        cp "$offline_file" "$dest"
        return
    fi

    download_file "$url" "$dest"
}

backup_file() {
    local file="$1"
    if [[ -e "$file" ]]; then
        local backup="${file}.bak-os-init.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$file" "$backup"
        echo "$backup"
    fi
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "$value"
}

json_array_from_csv() {
    local csv="${1:-}" item first=true
    local -a items=()
    printf '['
    IFS=',' read -r -a items <<< "$csv"
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -z "$item" ]] && continue
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$(json_escape "$item")"
    done
    printf ']'
}

load_os_init_config

# Reliable update for shallow git clones (git pull often fails with divergent branches)
git_update_shallow() {
    local dir="$1"
    local branch
    branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || branch="master"
    git_with_proxy -C "$dir" fetch origin --depth=1 -q
    git_with_proxy -C "$dir" reset --hard "origin/$branch"
}

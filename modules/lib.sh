#!/bin/bash
# Shared helpers for all kickstart scripts
# Source from a module script: source "$REPO_DIR/lib.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

os_init_is_en() {
    case "$(printf '%s' "${OS_INIT_LANG:-}" | tr '[:upper:]' '[:lower:]')" in
        en*) return 0 ;;
        *) return 1 ;;
    esac
}

os_init_text() {
    if os_init_is_en; then
        printf '%s\n' "$2"
    else
        printf '%s\n' "$1"
    fi
}

log_message() {
    local msg="$1"
    if os_init_is_en; then
        case "$msg" in
            "通过 Homebrew 安装 "*) printf 'installing %s with Homebrew\n' "${msg#通过 Homebrew 安装 }"; return ;;
            "通过 Homebrew 更新 "*) printf 'updating %s with Homebrew\n' "${msg#通过 Homebrew 更新 }"; return ;;
            "通过 Homebrew 卸载 "*) printf 'uninstalling %s with Homebrew\n' "${msg#通过 Homebrew 卸载 }"; return ;;
            "安装 "*) printf 'installing %s\n' "${msg#安装 }"; return ;;
            "更新 "*) printf 'updating %s\n' "${msg#更新 }"; return ;;
            "删除 "*) printf 'removing %s\n' "${msg#删除 }"; return ;;
            "复制 "*) printf 'copying %s\n' "${msg#复制 }"; return ;;
            "使用离线文件 "*) printf 'using offline file %s\n' "${msg#使用离线文件 }"; return ;;
            "离线模式禁止下载: "*) printf 'offline mode blocks download: %s\n' "${msg#离线模式禁止下载: }"; return ;;
            "需要 curl 或 wget 才能下载文件") printf 'curl or wget is required to download files\n'; return ;;
            "需要 curl 或 wget 才能查询 GitHub 最新版本") printf 'curl or wget is required to query the latest GitHub version\n'; return ;;
            "无法创建临时配置快照") printf 'failed to create temporary config snapshot\n'; return ;;
            "该模块只支持 Linux") printf 'this module only supports Linux\n'; return ;;
            "该模块只支持 macOS") printf 'this module only supports macOS\n'; return ;;
            "该模块需要 systemd，当前 init="*) printf 'this module requires systemd; current init=%s\n' "${msg#该模块需要 systemd，当前 init=}"; return ;;
            "不支持的包管理器家族: "*) printf 'unsupported package manager family: %s\n' "${msg#不支持的包管理器家族: }"; return ;;
            "RedHat 系统未找到 dnf/yum") printf 'dnf/yum was not found on this RedHat-family system\n'; return ;;
            "未知 macOS 应用组件: "*) printf 'unknown macOS app component: %s\n' "${msg#未知 macOS 应用组件: }"; return ;;
            "未知 macOS 命令行组件: "*) printf 'unknown macOS CLI component: %s\n' "${msg#未知 macOS 命令行组件: }"; return ;;
        esac
        printf '%s\n' "$msg"
        return
    fi

    case "$msg" in
        "installing "*) printf '安装 %s\n' "${msg#installing }"; return ;;
        "updating "*) printf '更新 %s\n' "${msg#updating }"; return ;;
        "removing "*) printf '删除 %s\n' "${msg#removing }"; return ;;
        "cloning "*) printf '克隆 %s\n' "${msg#cloning }"; return ;;
        "copying "*) printf '复制 %s\n' "${msg#copying }"; return ;;
        "setting "*) printf '设置 %s\n' "${msg#setting }"; return ;;
    esac
    msg="${msg/already installed/已安装}"
    msg="${msg/not installed/未安装}"
    msg="${msg/not found/未找到}"
    msg="${msg/not overwriting/不会覆盖}"
    printf '%s\n' "$msg"
}

log_line() {
    local color="$1" zh_tag="$2" en_tag="$3" msg="$4"
    echo -e "  ${color}[$(os_init_text "$zh_tag" "$en_tag")]${NC} $(log_message "$msg")"
}

skip()    { log_line "$GREEN" "跳过" "Skip" "$1"; }
install() { log_line "$YELLOW" "安装" "Install" "$1"; }
update()  { log_line "$CYAN" "更新" "Update" "$1"; }
remove()  { log_line "$RED" "删除" "Remove" "$1"; }
warn()    { log_line "$YELLOW" "警告" "Warning" "$1"; }
die()     { log_line "$RED" "错误" "Error" "$1" >&2; exit 1; }

sudo() {
    if [[ "$(id -u)" == "0" ]] && ! type -P sudo &>/dev/null; then
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -n|-E|-H|-S) shift ;;
                -p) shift 2 ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        "$@"
        return
    fi
    command sudo -n "$@"
}

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_INIT_REPO_DIR="${REPO_DIR:-$LIB_DIR}"

OS_INIT_CONFIG_KEYS=(
    OS_INIT_LANG OS_INIT_REGION OS_INIT_CONFIG_PROMPT OS_INIT_OFFLINE OS_INIT_FILES_DIR OS_INIT_SCRIPT_TIMEOUT
    DOWNLOAD_RETRY DOWNLOAD_TIMEOUT GITHUB_PROXY
    HOMEBREW_INSTALL_URL HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN HOMEBREW_ARTIFACT_DOMAIN
    HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE HOMEBREW_PIP_INDEX_URL
    OH_MY_ZSH_REPO STARSHIP_INSTALL_URL DIRENV_PACKAGE
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
            # shellcheck disable=SC2034
            UPDATE=true
        elif [[ "$a" == "--uninstall" ]]; then
            # shellcheck disable=SC2034
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
    local file="$1" filtered
    if [[ -r "$file" ]]; then
        filtered="$(mktemp "${TMPDIR:-/tmp}/os-init-config.XXXXXX")" || die "无法创建临时配置快照"
        awk '
            BEGIN {
                ignored["OS_INIT_PROXY"] = 1
                ignored["os_init_proxy"] = 1
                ignored["HTTP_PROXY"] = 1
                ignored["http_proxy"] = 1
                ignored["HTTPS_PROXY"] = 1
                ignored["https_proxy"] = 1
                ignored["ALL_PROXY"] = 1
                ignored["all_proxy"] = 1
                ignored["NO_PROXY"] = 1
                ignored["no_proxy"] = 1
                ignored["DOWNLOAD_URL_PROXY"] = 1
            }
            /^[[:space:]]*($|#)/ { print; next }
            {
                line = $0
                sub(/^[[:space:]]*export[[:space:]]+/, "", line)
                split(line, parts, "=")
                key = parts[1]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (ignored[key]) next
                print
            }
        ' "$file" > "$filtered"
        # shellcheck disable=SC1090
        source "$filtered"
        rm -f "$filtered"
    fi
}

export_proxy_env() {
    export GITHUB_PROXY
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
        export "${key?}"
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
require_macos() {
    is_macos || die "该模块只支持 macOS"
}
require_systemd() {
    require_linux
    is_systemd || die "该模块需要 systemd，当前 init=${INIT_SYSTEM}"
}

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
    download_file "$(resource_url HOMEBREW_INSTALL_URL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh")" "$tmp"
    NONINTERACTIVE=1 /bin/bash "$tmp"
    rm -f "$tmp"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
    export_homebrew_env
}

pkg_install() {
    if is_macos; then
        brew_install "$@"
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
    if is_macos; then
        brew_uninstall "$@" 2>/dev/null || true
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
    run_brew uninstall "$@"
}

brew_list() {
    export_homebrew_env
    command brew list "$@"
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
        https://github.com/*|https://raw.githubusercontent.com/*|https://objects.githubusercontent.com/*|https://github-releases.githubusercontent.com/*)
            render_url_proxy "$GITHUB_PROXY" "$url"
            ;;
        *)
            echo "$url"
            ;;
    esac
}

rewrite_download_url() {
    rewrite_github_url "$1"
}

git_with_proxy() {
    GIT_TERMINAL_PROMPT=0 command git "$@"
}

github_latest_version() {
    local repo="$1" prefix="${2:-v}"
    local url latest
    url="$(rewrite_download_url "https://github.com/${repo}/releases/latest")"
    if command -v curl &>/dev/null; then
        latest="$(curl -fsSI \
            --connect-timeout "${DOWNLOAD_TIMEOUT:-30}" \
            --max-time "${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>/dev/null | grep -i '^location:' | sed "s|.*/${prefix}||" | tr -d '\r\n')"
    elif command -v wget &>/dev/null; then
        latest="$(wget --server-response --spider \
            --timeout="${DOWNLOAD_TIMEOUT:-30}" \
            "$url" 2>&1 | grep -i 'Location:' | tail -1 | sed "s|.*/${prefix}||" | tr -d '\r\n')"
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

git_clone_depth_branch() {
    local depth="$1" branch="$2" url="$3" dest="$4"
    git_with_proxy clone --depth="$depth" -b "$branch" "$(rewrite_download_url "$url")" "$dest"
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
        local backup
        backup="${file}.bak-os-init.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$file" "$backup"
        echo "$backup"
    fi
}

os_init_reown_user_file() {
    local file="$1" user
    if [[ "$(id -u)" != "0" || -z "${SUDO_USER:-}" || "${SUDO_USER:-}" == "root" ]]; then
        return 0
    fi
    user="$(real_user)"
    chown "$user" "$file" 2>/dev/null || true
}

os_init_prepare_user_file() {
    local file="$1"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    os_init_reown_user_file "$file"
}

os_init_upsert_block() {
    local file="$1" name="$2" content="$3" before_regex="${4:-}"
    local begin end tmp repl
    begin="# >>> os-init ${name} >>>"
    end="# <<< os-init ${name} <<<"

    os_init_prepare_user_file "$file"
    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-block.XXXXXX")"
    repl="$(mktemp "${TMPDIR:-/tmp}/os-init-block-repl.XXXXXX")"

    {
        printf '%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } > "$repl"

    if grep -Fq "$begin" "$file"; then
        awk -v begin="$begin" -v end="$end" -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            $0 == begin {
                if (!printed) {
                    print_repl()
                    printed = 1
                }
                in_block = 1
                next
            }
            in_block && $0 == end {
                in_block = 0
                next
            }
            !in_block { print }
            END {
                if (!printed) print_repl()
            }
        ' "$file" > "$tmp"
    elif [[ -n "$before_regex" ]]; then
        awk -v pattern="$before_regex" -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            $0 ~ pattern && !printed {
                print_repl()
                printed = 1
            }
            { print }
            END {
                if (!printed) {
                    if (NR > 0) print ""
                    print_repl()
                }
            }
        ' "$file" > "$tmp"
    else
        awk -v repl="$repl" '
            function print_repl(  line) {
                while ((getline line < repl) > 0) print line
                close(repl)
            }
            { print }
            END {
                if (NR > 0) print ""
                print_repl()
            }
        ' "$file" > "$tmp"
    fi

    if cmp -s "$file" "$tmp"; then
        skip "$(basename "$file") 已包含 ${name} 配置"
    else
        install "写入 $(basename "$file") 的 ${name} 配置"
        mv "$tmp" "$file"
        os_init_reown_user_file "$file"
    fi
    rm -f "$tmp" "$repl"
}

os_init_remove_block() {
    local file="$1" name="$2" begin end tmp
    [[ -f "$file" ]] || return 0
    begin="# >>> os-init ${name} >>>"
    end="# <<< os-init ${name} <<<"
    grep -Fq "$begin" "$file" || {
        skip "$(basename "$file") 未包含 ${name} 配置"
        return 0
    }

    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-block-remove.XXXXXX")"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { in_block = 1; next }
        in_block && $0 == end { in_block = 0; next }
        !in_block { print }
    ' "$file" > "$tmp"
    install "删除 $(basename "$file") 的 ${name} 配置"
    mv "$tmp" "$file"
    os_init_reown_user_file "$file"
}

os_init_zshrc() {
    local home
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    printf '%s\n' "$home/.zshrc"
}

os_init_shell_rc_files() {
    local home file any=false
    home="$(real_home)"
    [[ -n "$home" ]] || return 1
    for file in "$home/.zshrc" "$home/.bashrc"; do
        if [[ -e "$file" ]]; then
            printf '%s\n' "$file"
            any=true
        fi
    done
    if [[ "$any" == false ]]; then
        printf '%s\n' "$home/.zshrc"
    fi
}

os_init_upsert_zsh_block() {
    local name="$1" content="$2" before_regex="${3:-}" file
    file="$(os_init_zshrc)" || return 0
    os_init_upsert_block "$file" "$name" "$content" "$before_regex"
}

os_init_upsert_shell_block() {
    local name="$1" content="$2" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_upsert_block "$file" "$name" "$content"
    done < <(os_init_shell_rc_files)
}

os_init_remove_zsh_block() {
    local name="$1" file
    file="$(os_init_zshrc)" || return 0
    os_init_remove_block "$file" "$name"
}

os_init_remove_shell_block() {
    local name="$1" file
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        os_init_remove_block "$file" "$name"
    done < <(os_init_shell_rc_files)
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

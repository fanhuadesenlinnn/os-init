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
# shellcheck disable=SC2032
install() { log_line "$YELLOW" "安装" "Install" "$1"; }
update()  { log_line "$CYAN" "更新" "Update" "$1"; }
remove()  { log_line "$RED" "删除" "Remove" "$1"; }
warn()    { log_line "$YELLOW" "警告" "Warning" "$1"; }
die()     { log_line "$RED" "错误" "Error" "$1" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }
require_cmd() {
    need_cmd "$1" || die "$(os_init_text "缺少命令：$1" "missing command: $1")"
}

sudo() {
    # Root is the target user in root mode. Execute privileged commands
    # directly so minimal/root-only systems do not need a sudo package.
    if [[ "$(id -u)" == "0" ]]; then
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -n|-E|-H|-S) shift ;;
                -p) shift 2 ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        # Bypass shell functions such as the logging helper named install().
        # Privileged commands must resolve to the external executable just as
        # they do when the real sudo binary is used for a normal user.
        command "$@"
        return
    fi
    command sudo -n "$@"
}

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_INIT_REPO_DIR="${REPO_DIR:-$LIB_DIR}"

OS_INIT_CONFIG_KEYS=(
    OS_INIT_LANG OS_INIT_REGION OS_INIT_CONFIG_PROMPT OS_INIT_SCRIPT_TIMEOUT
		DOWNLOAD_RETRY DOWNLOAD_TIMEOUT GITHUB_PROXY
	PACMAN_RETRY_ATTEMPTS ARCHLINUXARM_MIRRORS ENABLE_DNS ENABLE_OPS_TOOLKIT GPU_TYPE
	HOMEBREW_INSTALL_URL HOMEBREW_INSTALL_SHA256 HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN HOMEBREW_ARTIFACT_DOMAIN
    HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE HOMEBREW_PIP_INDEX_URL
	DIRENV_PACKAGE
    ZSH_AUTOSUGGESTIONS_REPO ZSH_SYNTAX_HIGHLIGHTING_REPO
	MISE_VERSION MISE_INSTALL_PATH
		OS_INIT_MISE_NODE_VERSION OS_INIT_MISE_PYTHON_VERSION OS_INIT_MISE_GO_VERSION MISE_NODE_MIRROR_URL MISE_GO_DOWNLOAD_MIRROR
	NPM_CONFIG_REGISTRY PIP_INDEX_URL UV_DEFAULT_INDEX GOPROXY
    DOCKER_DOWNLOAD_BASE DOCKER_CHANNEL DOCKER_VERSION DOCKER_COMPOSE_VERSION DOCKER_COMPOSE_DOWNLOAD_BASE
	DOCKER_TGZ_URL DOCKER_TGZ_SHA256 DOCKER_COMPOSE_DOWNLOAD_URL DOCKER_COMPOSE_SHA256
    DOCKER_REGISTRY_MIRRORS DOCKER_INSECURE_REGISTRIES DOCKER_DATA_ROOT
    MIHOMO_PACKAGE MIHOMO_VERSION MIHOMO_DOWNLOAD_BASE MIHOMO_BINARY_SOURCE
	MIHOMO_DOWNLOAD_URL MIHOMO_DOWNLOAD_SHA256
    MIHOMO_SERVICE_NAME MIHOMO_CONFIG_DIR MIHOMO_CONFIG_FILE MIHOMO_CONFIG_SOURCE
    MIHOMO_MIXED_PORT MIHOMO_ALLOW_LAN MIHOMO_BIND_ADDRESS
    MIHOMO_CONTROLLER_HOST MIHOMO_CONTROLLER_PORT MIHOMO_DNS_LISTEN MIHOMO_SECRET
    MIHOMO_STATE_DIR MIHOMO_EXTERNAL_UI_DIR MIHOMO_AUTO_ENABLE_SERVICE
	ENABLE_METACUBEXD METACUBEXD_SOURCE METACUBEXD_SHA256 METACUBEXD_REPO
	NVIM_DOWNLOAD_BASE NVIM_DOWNLOAD_URL NVIM_DOWNLOAD_SHA256
	LAZYGIT_VERSION LAZYGIT_DOWNLOAD_BASE LAZYGIT_DOWNLOAD_URL LAZYGIT_DOWNLOAD_SHA256
	NVIM_CONFIG_REPO
	YAZI_DOWNLOAD_BASE YAZI_DOWNLOAD_URL YAZI_DOWNLOAD_SHA256
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
	if [[ -n "${OS_INIT_TARGET_GOOS:-}" ]]; then
		[[ "${OS_INIT_TARGET_GOOS}" == "darwin" ]] && echo "macos" || echo "${OS_INIT_TARGET_GOOS}"
		return
	fi
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
	if [[ -n "${OS_INIT_TARGET_FAMILY:-}" ]]; then
		echo "${OS_INIT_TARGET_FAMILY}"
		return
	fi
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
        rhel|centos|rocky|almalinux|fedora|oracle|oraclelinux|ol|kylin) echo "redhat"; return ;;
    esac

    case " $id_like " in
        *" arch "*) echo "arch"; return ;;
        *" debian "*|*" ubuntu "*) echo "debian"; return ;;
        *" rhel "*|*" fedora "*|*" centos "*) echo "redhat"; return ;;
    esac

    echo "unknown"
}

detect_init() {
	if [[ -n "${OS_INIT_TARGET_INIT:-}" ]]; then
		echo "${OS_INIT_TARGET_INIT}"
		return
	fi
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

detect_linux_environment() {
	if [[ -n "${OS_INIT_TARGET_ENVIRONMENT:-}" ]]; then
		echo "${OS_INIT_TARGET_ENVIRONMENT}"
		return
	fi
	if [[ "$OS" == "linux" ]] && grep -qi 'orbstack' /proc/sys/kernel/osrelease 2>/dev/null; then
		echo "orbstack"
	elif [[ "$OS" == "linux" ]] && grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
		echo "wsl"
	else
		echo "native"
	fi
}

is_orbstack() {
	[[ "${LINUX_ENVIRONMENT:-$(detect_linux_environment)}" == "orbstack" ]]
}

detect_wsl_version() {
	if [[ -n "${OS_INIT_TARGET_WSL_VERSION:-}" ]]; then
		echo "${OS_INIT_TARGET_WSL_VERSION}"
		return
	fi
	if [[ "${LINUX_ENVIRONMENT:-$(detect_linux_environment)}" != "wsl" ]]; then
		echo 0
	elif grep -Eqi '(wsl2|microsoft-standard)' /proc/sys/kernel/osrelease 2>/dev/null; then
		echo 2
	else
		echo 1
	fi
}

detect_wslg() {
	if [[ -n "${OS_INIT_TARGET_WSLG:-}" ]]; then
		case "$(lower "${OS_INIT_TARGET_WSLG}")" in
			1|true|yes|on) echo 1 ;;
			*) echo 0 ;;
		esac
	elif [[ -d /mnt/wslg ]]; then
		echo 1
	else
		echo 0
	fi
}

real_user() {
    if [[ "${OS_INIT_CONTEXT_VERSION:-}" == "1" && -n "${OS_INIT_TARGET_USER:-}" ]]; then
        echo "$OS_INIT_TARGET_USER"
        return
    fi
    if [[ "$(id -u)" == "0" ]]; then
        echo "root"
        return
    fi
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
        echo "$SUDO_USER"
    else
        id -un
    fi
}

real_home() {
    local user
    if [[ "${OS_INIT_CONTEXT_VERSION:-}" == "1" && -n "${OS_INIT_TARGET_HOME:-}" ]]; then
        echo "$OS_INIT_TARGET_HOME"
        return
    fi
    user="$(real_user)"
    if [[ "$(id -u)" == "0" ]]; then
        if command -v getent &>/dev/null; then
            getent passwd root | cut -d: -f6
            return
        fi
        eval "printf '%s\n' ~root"
        return
    fi
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
LINUX_ENVIRONMENT="$(detect_linux_environment)"
WSL_VERSION="$(detect_wsl_version)"
WSLG="$(detect_wslg)"
export OS OS_FAMILY INIT_SYSTEM LINUX_ENVIRONMENT WSL_VERSION WSLG

source_config_file() {
    local file="$1" filtered allowed_keys
    if [[ -r "$file" ]]; then
        filtered="$(mktemp "${TMPDIR:-/tmp}/os-init-config.XXXXXX")" || die "无法创建临时配置快照"
        printf -v allowed_keys ' %s' "${OS_INIT_CONFIG_KEYS[@]}"
        awk -v allowed_keys="$allowed_keys" '
            BEGIN {
                count = split(allowed_keys, keys, /[[:space:]]+/)
                for (i = 1; i <= count; i++) {
                    if (keys[i] != "") allowed[keys[i]] = 1
                }
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
                legacy["MISE_NODE_VERSION"] = "OS_INIT_MISE_NODE_VERSION"
                legacy["MISE_PYTHON_VERSION"] = "OS_INIT_MISE_PYTHON_VERSION"
                legacy["MISE_GO_VERSION"] = "OS_INIT_MISE_GO_VERSION"
            }
            /^[[:space:]]*($|#)/ { print; next }
            {
                line = $0
                sub(/^[[:space:]]*export[[:space:]]+/, "", line)
                split(line, parts, "=")
                key = parts[1]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (key in legacy) {
                    print legacy[key] substr(line, index(line, "="))
                    next
                }
                if (!allowed[key] || ignored[key]) next
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
    LINUX_ENVIRONMENT="$(detect_linux_environment)"
    WSL_VERSION="$(detect_wsl_version)"
    WSLG="$(detect_wslg)"
    export OS OS_FAMILY INIT_SYSTEM LINUX_ENVIRONMENT WSL_VERSION WSLG
}

is_family() { [[ "$OS_FAMILY" == "$1" ]]; }
is_wsl() { [[ "${LINUX_ENVIRONMENT:-native}" == "wsl" ]]; }
is_wsl2() { is_wsl && [[ "${WSL_VERSION:-0}" == "2" ]]; }
wsl_docker_desktop_integration_detected() {
    local docker_path context operating_system socket_path
    is_wsl || return 1
    socket_path="$(readlink -f /var/run/docker.sock 2>/dev/null || true)"
    [[ "${socket_path}" == /mnt/wsl/docker-desktop/* ]] && return 0
    command -v docker >/dev/null 2>&1 || return 1
    docker_path="$(readlink -f "$(command -v docker)" 2>/dev/null || command -v docker)"
    [[ "${docker_path}" == /mnt/wsl/docker-desktop/* ]] && return 0
    context="$(docker context show 2>/dev/null || true)"
    [[ "${context}" == "desktop-linux" ]] && return 0
    operating_system="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"
    [[ "$(lower "${operating_system}")" == *"docker desktop"* ]]
}
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
require_wsl() {
    require_linux
    is_wsl || die "该模块只支持 WSL"
}
require_wsl2() {
    require_wsl
    is_wsl2 || die "该模块需要 WSL2；当前 WSL_VERSION=${WSL_VERSION:-0}"
}

# shellcheck disable=SC1091
source "${LIB_DIR}/lib/packages.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/github_proxy.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/download.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/state.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/json.sh"

if [[ "${OS_INIT_CONFIG_LOADED:-0}" != "1" ]]; then
	load_os_init_config
fi

#!/bin/bash
set -euo pipefail

# Install and configure Mihomo for Linux/systemd hosts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

MIHOMO_BIN="/usr/local/bin/mihomo"
MIHOMO_CONFIG_FILE="${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
MIHOMO_CONFIG_DIR="${MIHOMO_CONFIG_DIR:-$(dirname "$MIHOMO_CONFIG_FILE")}"
MIHOMO_STATE_DIR="${MIHOMO_STATE_DIR:-/var/lib/mihomo}"
MIHOMO_SERVICE_NAME="${MIHOMO_SERVICE_NAME:-mihomo.service}"

TITLE="安装"
[[ "$UNINSTALL" == true ]] && TITLE="卸载"
echo "=== Mihomo 代理 ($TITLE) ==="
echo ""

bool_to_yaml() {
    case "${1:-0}" in
        1|true|yes|on) printf "true" ;;
        *) printf "false" ;;
    esac
}

quote_yaml_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

refresh_mihomo_bin() {
    if command -v mihomo &>/dev/null; then
        MIHOMO_BIN="$(command -v mihomo)"
    fi
}

sed_escape_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

mihomo_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64-v1" ;;
        arm64|aarch64) echo "arm64" ;;
        *) die "Mihomo 暂不支持当前架构: $(uname -m)" ;;
    esac
}

mihomo_version() {
    local version="${MIHOMO_VERSION:-}"
    if [[ -z "$version" ]]; then
        version="$(github_latest_version "MetaCubeX/mihomo" "v")"
    fi
    version="${version#v}"
    [[ -n "$version" ]] || die "无法确定 Mihomo 版本"
    echo "$version"
}

mihomo_download_url() {
    if [[ -n "${MIHOMO_DOWNLOAD_URL:-}" ]]; then
        echo "$MIHOMO_DOWNLOAD_URL"
        return
    fi

    if [[ -n "${MIHOMO_BINARY_SOURCE:-}" ]]; then
        echo "$MIHOMO_BINARY_SOURCE"
        return
    fi

    local version arch base
    version="$(mihomo_version)"
    arch="$(mihomo_arch)"
    base="${MIHOMO_DOWNLOAD_BASE:-https://github.com/MetaCubeX/mihomo/releases/download/v${version}}"
    echo "${base%/}/mihomo-linux-${arch}-v${version}.gz"
}

mihomo_safe_external_ui_dir() {
    local requested="${MIHOMO_EXTERNAL_UI_DIR:-${MIHOMO_STATE_DIR}/ui}"
    case "$requested" in
        "$MIHOMO_STATE_DIR"|"$MIHOMO_STATE_DIR"/*)
            echo "$requested"
            ;;
        *)
            warn "MetaCubeXD UI 目录必须位于 ${MIHOMO_STATE_DIR} 内，已改为 ${MIHOMO_STATE_DIR}/ui"
            echo "${MIHOMO_STATE_DIR}/ui"
            ;;
    esac
}

warn_mihomo_exposure() {
    if [[ "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}" == "0.0.0.0" && -z "${MIHOMO_SECRET:-}" ]]; then
        warn "Mihomo 控制接口监听 0.0.0.0 且 MIHOMO_SECRET 为空"
        warn "如需开放 MetaCubeXD，请设置 MIHOMO_SECRET"
    fi
}

render_mihomo_config_template() {
    local template="$1" target="$2" tmp external_ui_line=""

    warn_mihomo_exposure
    tmp="$(mktemp "${TMPDIR:-/tmp}/mihomo-config.XXXXXX")"

    if [[ "${ENABLE_METACUBEXD:-1}" == "1" ]]; then
        external_ui_line="external-ui: $(mihomo_safe_external_ui_dir)"
    fi

    sed \
        -e "s/__MIHOMO_MIXED_PORT__/$(sed_escape_replacement "${MIHOMO_MIXED_PORT:-7890}")/g" \
        -e "s/__MIHOMO_ALLOW_LAN__/$(sed_escape_replacement "$(bool_to_yaml "${MIHOMO_ALLOW_LAN:-0}")")/g" \
        -e "s/__MIHOMO_BIND_ADDRESS__/$(sed_escape_replacement "${MIHOMO_BIND_ADDRESS:-127.0.0.1}")/g" \
        -e "s/__MIHOMO_CONTROLLER_HOST__/$(sed_escape_replacement "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}")/g" \
        -e "s/__MIHOMO_CONTROLLER_PORT__/$(sed_escape_replacement "${MIHOMO_CONTROLLER_PORT:-9090}")/g" \
        -e "s/__MIHOMO_DNS_LISTEN__/$(sed_escape_replacement "${MIHOMO_DNS_LISTEN:-127.0.0.1:1053}")/g" \
        -e "s/__MIHOMO_SECRET_YAML__/$(sed_escape_replacement "$(quote_yaml_string "${MIHOMO_SECRET:-}")")/g" \
        -e "s/__METACUBEXD_EXTERNAL_UI_LINE__/$(sed_escape_replacement "$external_ui_line")/g" \
        "$template" > "$tmp"

    sudo install -m 0600 -D "$tmp" "$target"
    rm -f "$tmp"
}

install_mihomo_binary() {
    local url file_name tmp gz
    url="$(mihomo_download_url)"
    file_name="$(basename "${url%%\?*}")"
    tmp="$(mktemp -d /tmp/mihomo-XXXXXX)"
    gz="$tmp/$file_name"

    install "获取 Mihomo 核心: $file_name"
    case "$url" in
        http://*|https://*)
            download_or_offline_file "$url" "$gz" "$file_name"
            ;;
        *)
            [[ -f "$url" ]] || die "Mihomo 二进制来源不存在: $url"
            cp -a "$url" "$gz"
            ;;
    esac
    if [[ "$file_name" == *.gz ]]; then
        gzip -dc "$gz" > "$tmp/mihomo"
    else
        cp -a "$gz" "$tmp/mihomo"
    fi
    sudo install -m 0755 "$tmp/mihomo" "$MIHOMO_BIN"
    rm -rf "$tmp"
    "$MIHOMO_BIN" -v || true
}

package_available() {
    local package="$1"
    if is_arch && command -v pacman &>/dev/null; then
        pacman -Si "$package" &>/dev/null
    elif is_debian && command -v apt-cache &>/dev/null; then
        apt-cache show "$package" &>/dev/null
    elif is_redhat; then
        if command -v dnf &>/dev/null; then
            dnf -q list "$package" &>/dev/null
        elif command -v yum &>/dev/null; then
            yum -q list "$package" &>/dev/null
        else
            return 1
        fi
    else
        return 1
    fi
}

install_mihomo_core() {
    local package="${MIHOMO_PACKAGE:-mihomo}"

    if [[ -z "${MIHOMO_BINARY_SOURCE:-}" ]] && package_available "$package"; then
        install "通过发行版仓库安装 Mihomo: $package"
        pkg_install "$package"
        return
    fi

    install_mihomo_binary
}

config_source_to_root_file() {
    local source="$1" target="$2" tmp
    [[ -n "$source" ]] || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/mihomo-source.XXXXXX")"
    case "$source" in
        http://*|https://*)
            download_or_offline_file "$source" "$tmp" "$(basename "${source%%\?*}")"
            ;;
        *)
            [[ -f "$source" ]] || die "Mihomo 配置文件不存在: $source"
            cp -a "$source" "$tmp"
            ;;
    esac
    sudo install -m 0600 -D "$tmp" "$target"
    rm -f "$tmp"
}

configure_mihomo() {
    install "写入 Mihomo 配置: $MIHOMO_CONFIG_FILE"
    sudo mkdir -p "$MIHOMO_CONFIG_DIR" "$MIHOMO_CONFIG_DIR/providers" "$MIHOMO_CONFIG_DIR/ruleset" "$MIHOMO_STATE_DIR"

    if [[ -z "${MIHOMO_CONFIG_SOURCE:-}" ]]; then
        render_mihomo_config_template "$SCRIPT_DIR/config.yaml.tpl" "$MIHOMO_CONFIG_FILE"
    elif [[ "$MIHOMO_CONFIG_SOURCE" == *.tpl && "$MIHOMO_CONFIG_SOURCE" != http://* && "$MIHOMO_CONFIG_SOURCE" != https://* ]]; then
        render_mihomo_config_template "$MIHOMO_CONFIG_SOURCE" "$MIHOMO_CONFIG_FILE"
    else
        config_source_to_root_file "$MIHOMO_CONFIG_SOURCE" "$MIHOMO_CONFIG_FILE"
    fi
}

mihomo_config_has_placeholder_subscription() {
    sudo grep -Fq "https://example.com/your-subscription-url" "$MIHOMO_CONFIG_FILE" 2>/dev/null
}

write_mihomo_service() {
    local unit_path
    unit_path="$(systemctl show -P FragmentPath "$MIHOMO_SERVICE_NAME" 2>/dev/null || true)"
    if [[ -n "$unit_path" && -f "$unit_path" && "$unit_path" != "/etc/systemd/system/$MIHOMO_SERVICE_NAME" ]]; then
        skip "检测到发行版自带 systemd unit: $unit_path"
        return
    fi

    install "写入 systemd unit: /etc/systemd/system/$MIHOMO_SERVICE_NAME"
    sudo tee "/etc/systemd/system/$MIHOMO_SERVICE_NAME" >/dev/null <<EOF
[Unit]
Description=Mihomo proxy service
Documentation=https://github.com/MetaCubeX/mihomo
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$MIHOMO_BIN -f $MIHOMO_CONFIG_FILE -d $MIHOMO_STATE_DIR
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_ADMIN
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_ADMIN

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
}

test_mihomo_config() {
    install "测试 Mihomo 配置"
    sudo mkdir -p "$MIHOMO_STATE_DIR"
    sudo "$MIHOMO_BIN" -t -f "$MIHOMO_CONFIG_FILE" -d "$MIHOMO_STATE_DIR"
}

stop_failed_service() {
    sudo systemctl disable --now "$MIHOMO_SERVICE_NAME" 2>/dev/null || true
    sudo systemctl reset-failed "$MIHOMO_SERVICE_NAME" 2>/dev/null || true
}

enable_mihomo_service_if_ready() {
    [[ "${MIHOMO_AUTO_ENABLE_SERVICE:-1}" == "1" ]] || {
        warn "当前配置不自动启用 Mihomo 服务"
        return
    }

    if mihomo_config_has_placeholder_subscription; then
        warn "Mihomo 配置仍使用示例订阅地址，已跳过自动启动服务"
        warn "请替换 proxy-providers.airport.url，或设置 MIHOMO_CONFIG_SOURCE"
        stop_failed_service
        return
    fi

    if test_mihomo_config; then
        install "启用 Mihomo 服务"
        sudo systemctl enable --now "$MIHOMO_SERVICE_NAME"
    else
        warn "Mihomo 配置测试失败，已跳过自动启动服务"
        stop_failed_service
    fi
}

install_metacubexd() {
    [[ "${ENABLE_METACUBEXD:-1}" == "1" ]] || return 0

    local target tmp source
    target="$(mihomo_safe_external_ui_dir)"
    source="${METACUBEXD_SOURCE:-}"
    tmp="$(mktemp -d /tmp/metacubexd-XXXXXX)"

    install "安装 MetaCubeXD 面板到 $target"
    if [[ -n "$source" ]]; then
        case "$source" in
            http://*|https://*)
                download_or_offline_file "$source" "$tmp/metacubexd.tar.gz" "$(basename "${source%%\?*}")"
                tar -xzf "$tmp/metacubexd.tar.gz" -C "$tmp"
                source="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
                ;;
            *)
                [[ -d "$source" ]] || die "MetaCubeXD_SOURCE 目录不存在: $source"
                ;;
        esac
        sudo rm -rf "$target"
        sudo mkdir -p "$(dirname "$target")"
        sudo cp -a "$source" "$target"
    elif [[ "${OS_INIT_OFFLINE:-0}" == "1" ]]; then
        warn "离线模式未设置 METACUBEXD_SOURCE，跳过 MetaCubeXD 面板"
    else
        git_clone_depth_branch 1 gh-pages "$(repo_url METACUBEXD_REPO "https://github.com/metacubex/metacubexd.git")" "$tmp/ui"
        sudo rm -rf "$target"
        sudo mkdir -p "$(dirname "$target")"
        sudo cp -a "$tmp/ui" "$target"
    fi

    rm -rf "$tmp"
}

install_proxy_env_template() {
    local home rc_file marker_begin marker_end
    home="$(real_home)"
    [[ -n "$home" ]] || return 0
    marker_begin="# >>> os-init proxy-env >>>"
    marker_end="# <<< os-init proxy-env <<<"

    for rc_file in "$home/.bashrc" "$home/.zshrc"; do
        [[ -e "$rc_file" ]] || continue
        if grep -Fq "$marker_begin" "$rc_file"; then
            skip "$(basename "$rc_file") 已包含代理环境变量模板"
            continue
        fi
        install "写入 $(basename "$rc_file") 代理环境变量模板"
        cat >> "$rc_file" <<EOF

$marker_begin
# export http_proxy="http://127.0.0.1:${MIHOMO_MIXED_PORT:-7890}"
# export https_proxy="\$http_proxy"
# export all_proxy="socks5://127.0.0.1:${MIHOMO_MIXED_PORT:-7890}"
# export HTTP_PROXY="\$http_proxy"
# export HTTPS_PROXY="\$https_proxy"
# export ALL_PROXY="\$all_proxy"
# export no_proxy="localhost,127.0.0.1,::1"
# export NO_PROXY="\$no_proxy"
$marker_end
EOF
    done
}

verify_mihomo() {
    echo ""
    echo "=== Mihomo 信息 ==="
    "$MIHOMO_BIN" -v 2>/dev/null || true
    echo "配置目录: $MIHOMO_CONFIG_DIR"
    echo "配置文件: $MIHOMO_CONFIG_FILE"
    echo "状态目录: $MIHOMO_STATE_DIR"
    echo "系统服务: $MIHOMO_SERVICE_NAME"
    echo "代理端口: ${MIHOMO_BIND_ADDRESS:-127.0.0.1}:${MIHOMO_MIXED_PORT:-7890}"
    echo "控制接口: http://${MIHOMO_CONTROLLER_HOST:-127.0.0.1}:${MIHOMO_CONTROLLER_PORT:-9090}"
    if [[ "${ENABLE_METACUBEXD:-1}" == "1" ]]; then
        echo "MetaCubeXD: http://${MIHOMO_CONTROLLER_HOST:-127.0.0.1}:${MIHOMO_CONTROLLER_PORT:-9090}/ui/"
    fi
}

uninstall_mihomo() {
    require_systemd
    remove "停止 Mihomo 服务"
    stop_failed_service
    sudo rm -f "/etc/systemd/system/$MIHOMO_SERVICE_NAME"
    sudo systemctl daemon-reload

    if [[ -x "$MIHOMO_BIN" ]]; then
        remove "删除 Mihomo 二进制"
        sudo rm -f "$MIHOMO_BIN"
    fi

    if [[ "${PURGE_DATA:-0}" == "1" ]]; then
        remove "清理 Mihomo 配置和状态目录"
        sudo rm -rf "$MIHOMO_CONFIG_DIR" "$MIHOMO_STATE_DIR"
    else
        skip "保留 Mihomo 配置和状态目录，如需清理请设置 PURGE_DATA=1"
    fi
}

if [[ "$UNINSTALL" == true ]]; then
    uninstall_mihomo
    echo ""
    echo "=== Mihomo 卸载完成 ==="
    exit 0
fi

require_systemd

echo "[1/5] Mihomo 核心..."
if command -v mihomo &>/dev/null && [[ "$UPDATE" != true ]]; then
    skip "mihomo 已安装: $(mihomo -v 2>/dev/null | head -1)"
else
    install_mihomo_core
fi
refresh_mihomo_bin

echo "[2/5] 配置文件..."
configure_mihomo

echo "[3/5] MetaCubeXD..."
install_metacubexd

echo "[4/5] systemd 服务..."
write_mihomo_service
enable_mihomo_service_if_ready

echo "[5/5] Shell 代理模板..."
install_proxy_env_template

verify_mihomo
echo ""
echo "=== Mihomo 安装完成 ==="

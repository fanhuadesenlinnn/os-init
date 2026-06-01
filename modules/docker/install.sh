#!/bin/bash
set -euo pipefail

# Install Docker Engine from official static binaries and Docker Compose as a CLI plugin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

DOCKER_SERVICE="/etc/systemd/system/docker.service"
CONTAINERD_SERVICE="/etc/systemd/system/containerd.service"
COMPOSE_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
COMPOSE_PLUGIN="${COMPOSE_PLUGIN_DIR}/docker-compose"
DAEMON_CFG="/etc/docker/daemon.json"

TITLE="安装"
[[ "$UNINSTALL" == true ]] && TITLE="卸载"
echo "=== Docker 二进制安装 ($TITLE) ==="
echo ""

docker_static_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "aarch64" ;;
        *) die "Docker 静态二进制暂不支持当前架构: $(uname -m)" ;;
    esac
}

compose_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "aarch64" ;;
        *) die "Docker Compose 暂不支持当前架构: $(uname -m)" ;;
    esac
}

docker_static_base_url() {
    local arch channel base
    arch="$(docker_static_arch)"
    channel="${DOCKER_CHANNEL:-stable}"
    base="${DOCKER_DOWNLOAD_BASE:-https://download.docker.com}"
    echo "${base%/}/linux/static/${channel}/${arch}"
}

latest_docker_version() {
    local index_file version
    [[ "${OS_INIT_OFFLINE:-0}" == "1" ]] && die "离线模式请设置 DOCKER_VERSION"
    index_file="$(mktemp "${TMPDIR:-/tmp}/docker-index.XXXXXX")"
    download_file "$(docker_static_base_url)/" "$index_file"
    version="$(grep -Eo 'docker-[0-9]+(\.[0-9]+){1,3}\.tgz' "$index_file" \
        | sed -E 's/docker-//; s/\.tgz//' \
        | sort -V \
        | tail -1)"
    rm -f "$index_file"
    [[ -n "$version" ]] || die "无法确定 Docker 最新版本"
    echo "$version"
}

docker_version() {
    local version="${DOCKER_VERSION:-}"
    [[ -n "$version" ]] || version="$(latest_docker_version)"
    version="${version#v}"
    echo "$version"
}

docker_archive_url() {
    local version
    version="$(docker_version)"
    echo "$(docker_static_base_url)/docker-${version}.tgz"
}

compose_version() {
    local version="${DOCKER_COMPOSE_VERSION:-}"
    [[ -n "$version" ]] || version="$(github_latest_version "docker/compose" "v")"
    version="${version#v}"
    echo "$version"
}

compose_download_url() {
    local version base
    version="$(compose_version)"
    base="${DOCKER_COMPOSE_DOWNLOAD_BASE:-https://github.com/docker/compose/releases/download}"
    echo "${base%/}/v${version}/docker-compose-linux-$(compose_arch)"
}

install_prerequisites() {
    local packages=()
    command -v tar &>/dev/null || packages+=(tar)
    command -v gzip &>/dev/null || packages+=(gzip)
    command -v git &>/dev/null || packages+=(git)
    command -v iptables &>/dev/null || packages+=(iptables)
    command -v ps &>/dev/null || {
        if is_debian; then
            packages+=(procps)
        else
            packages+=(procps-ng)
        fi
    }

    if [[ ${#packages[@]} -gt 0 ]]; then
        install "安装 Docker 运行前置依赖: ${packages[*]}"
        pkg_install "${packages[@]}"
    else
        skip "Docker 前置依赖已满足"
    fi
}

install_docker_binaries() {
    local url file_name tmp
    url="$(docker_archive_url)"
    file_name="$(basename "$url")"
    tmp="$(mktemp -d /tmp/docker-bin-XXXXXX)"

    install "获取 Docker 静态二进制: $file_name"
    download_or_offline_file "$url" "$tmp/$file_name" "$file_name"
    tar -xzf "$tmp/$file_name" -C "$tmp"
    sudo install -m 0755 "$tmp/docker/"* /usr/local/bin/
    rm -rf "$tmp"
    docker --version || true
}

install_compose_plugin() {
    local url file_name tmp
    url="$(compose_download_url)"
    file_name="$(basename "$url")"
    tmp="$(mktemp -d /tmp/docker-compose-XXXXXX)"

    install "安装 Docker Compose CLI 插件: $file_name"
    download_or_offline_file "$url" "$tmp/docker-compose" "$file_name"
    sudo install -m 0755 -D "$tmp/docker-compose" "$COMPOSE_PLUGIN"
    rm -rf "$tmp"
}

json_string() {
    printf '"%s"' "$(json_escape "$1")"
}

daemon_add_entry() {
    local file="$1" key="$2" value="$3"
    if [[ "$(cat "$file")" != "{" ]]; then
        printf ',\n' >> "$file"
    else
        printf '\n' >> "$file"
    fi
    printf '  "%s": %s' "$key" "$value" >> "$file"
}

proxy_json() {
    local tmp first=true
    tmp="$(mktemp "${TMPDIR:-/tmp}/docker-proxy.XXXXXX")"
    printf '{' > "$tmp"
    if [[ -n "${HTTP_PROXY:-}" ]]; then
        printf '\n    "http-proxy": %s' "$(json_string "$HTTP_PROXY")" >> "$tmp"
        first=false
    fi
    if [[ -n "${HTTPS_PROXY:-}" ]]; then
        [[ "$first" == true ]] || printf ',\n' >> "$tmp"
        printf '    "https-proxy": %s' "$(json_string "$HTTPS_PROXY")" >> "$tmp"
        first=false
    fi
    if [[ -n "${NO_PROXY:-}" ]]; then
        [[ "$first" == true ]] || printf ',\n' >> "$tmp"
        printf '    "no-proxy": %s' "$(json_string "$NO_PROXY")" >> "$tmp"
        first=false
    fi
    [[ "$first" == true ]] || printf '\n  ' >> "$tmp"
    printf '}' >> "$tmp"
    cat "$tmp"
    rm -f "$tmp"
}

write_daemon_config() {
    local tmp mirrors insecure proxies
    tmp="$(mktemp "${TMPDIR:-/tmp}/daemon-json.XXXXXX")"
    printf '{' > "$tmp"

    daemon_add_entry "$tmp" "max-concurrent-downloads" "16"
    daemon_add_entry "$tmp" "max-concurrent-uploads" "8"
    daemon_add_entry "$tmp" "log-driver" "$(json_string "json-file")"
    daemon_add_entry "$tmp" "log-opts" '{"max-size":"1000m","max-file":"5"}'

    mirrors="$(json_array_from_csv "${DOCKER_REGISTRY_MIRRORS:-}")"
    [[ "$mirrors" == "[]" ]] || daemon_add_entry "$tmp" "registry-mirrors" "$mirrors"

    insecure="$(json_array_from_csv "${DOCKER_INSECURE_REGISTRIES:-}")"
    [[ "$insecure" == "[]" ]] || daemon_add_entry "$tmp" "insecure-registries" "$insecure"

    if [[ -n "${DOCKER_DATA_ROOT:-}" ]]; then
        daemon_add_entry "$tmp" "data-root" "$(json_string "$DOCKER_DATA_ROOT")"
    fi

    if [[ -n "${HTTP_PROXY:-}${HTTPS_PROXY:-}${NO_PROXY:-}" ]]; then
        proxies="$(proxy_json)"
        daemon_add_entry "$tmp" "proxies" "$proxies"
    fi

    printf '\n}\n' >> "$tmp"
    install "写入 Docker daemon 配置: $DAEMON_CFG"
    backup_file "$DAEMON_CFG" >/dev/null || true
    sudo install -m 0644 -D "$tmp" "$DAEMON_CFG"
    rm -f "$tmp"
}

write_systemd_units() {
    install "写入 containerd.service"
    sudo tee "$CONTAINERD_SERVICE" >/dev/null <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStart=/usr/local/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

    install "写入 docker.service"
    sudo tee "$DOCKER_SERVICE" >/dev/null <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd -H unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
}

ensure_docker_group() {
    local user
    if ! getent group docker >/dev/null 2>&1; then
        install "创建 docker 用户组"
        sudo groupadd docker
    fi

    user="$(real_user)"
    if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
        skip "用户 $user 已在 docker 组"
    else
        install "添加 $user 到 docker 组"
        sudo usermod -aG docker "$user"
        warn "请重新登录后再免 sudo 使用 docker"
    fi
}

enable_docker_service() {
    install "启用 Docker 服务"
    sudo systemctl enable --now containerd.service
    sudo systemctl enable --now docker.service
}

verify_docker() {
    echo ""
    echo "=== Docker 信息 ==="
    docker --version || true
    docker compose version || true
    sudo systemctl --no-pager --full status docker.service | sed -n '1,8p' || true
}

uninstall_docker() {
    require_systemd
    remove "停止 Docker 服务"
    sudo systemctl disable --now docker.service 2>/dev/null || true
    sudo systemctl disable --now containerd.service 2>/dev/null || true
    sudo systemctl reset-failed docker.service containerd.service 2>/dev/null || true

    remove "删除 systemd unit 和 Compose 插件"
    sudo rm -f "$DOCKER_SERVICE" "$CONTAINERD_SERVICE" "$COMPOSE_PLUGIN"
    sudo systemctl daemon-reload

    remove "删除 Docker 静态二进制"
    sudo rm -f \
        /usr/local/bin/containerd \
        /usr/local/bin/containerd-shim \
        /usr/local/bin/containerd-shim-runc-v2 \
        /usr/local/bin/ctr \
        /usr/local/bin/docker \
        /usr/local/bin/dockerd \
        /usr/local/bin/docker-init \
        /usr/local/bin/docker-proxy \
        /usr/local/bin/runc

    if [[ "${PURGE_DATA:-0}" == "1" ]]; then
        warn "PURGE_DATA=1，将删除 Docker 数据目录"
        sudo rm -rf /var/lib/docker /var/lib/containerd
    else
        skip "保留 /var/lib/docker 和 /var/lib/containerd；如需清理请设置 PURGE_DATA=1"
    fi

    if [[ "${PURGE_CONFIG:-0}" == "1" ]]; then
        remove "删除 Docker 配置"
        sudo rm -rf /etc/docker
    else
        skip "保留 /etc/docker；如需清理请设置 PURGE_CONFIG=1"
    fi
}

if [[ "$UNINSTALL" == true ]]; then
    uninstall_docker
    echo ""
    echo "=== Docker 卸载完成 ==="
    exit 0
fi

require_systemd

echo "[1/6] 前置依赖..."
install_prerequisites

echo "[2/6] Docker 静态二进制..."
if command -v dockerd &>/dev/null && command -v docker &>/dev/null && [[ "$UPDATE" != true ]]; then
    skip "Docker 已安装: $(docker --version)"
else
    install_docker_binaries
fi

echo "[3/6] Docker Compose plugin..."
if docker compose version &>/dev/null && [[ "$UPDATE" != true ]]; then
    skip "Docker Compose 已安装: $(docker compose version --short 2>/dev/null || echo '?')"
else
    install_compose_plugin
fi

echo "[4/6] daemon.json..."
write_daemon_config

echo "[5/6] systemd..."
write_systemd_units
enable_docker_service

echo "[6/6] docker 组..."
ensure_docker_group

verify_docker
echo ""
echo "=== Docker 安装完成 ==="

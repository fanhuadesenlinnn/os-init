#!/bin/bash
set -euo pipefail

# Install Docker Engine from official static binaries and Docker Compose as a CLI plugin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_DIR/lib.sh"

parse_update_flag "$@"

DOCKER_SERVICE="/etc/systemd/system/docker.service"
CONTAINERD_SERVICE="/etc/systemd/system/containerd.service"
COMPOSE_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
COMPOSE_PLUGIN="${COMPOSE_PLUGIN_DIR}/docker-compose"
DAEMON_CFG="/etc/docker/daemon.json"

TITLE="安装"
[[ "$UNINSTALL" == true ]] && TITLE="卸载"
echo "=== Docker 安装 ($TITLE) ==="
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
    if [[ -n "${DOCKER_TGZ_URL:-}" ]]; then
        echo "$DOCKER_TGZ_URL"
        return
    fi
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
    if [[ -n "${DOCKER_COMPOSE_DOWNLOAD_URL:-}" ]]; then
        echo "$DOCKER_COMPOSE_DOWNLOAD_URL"
        return
    fi
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
	local url file_name tmp source target binary
    url="$(docker_archive_url)"
    file_name="$(basename "${url%%\?*}")"
    tmp="$(mktemp -d /tmp/docker-bin-XXXXXX)"

    install "获取 Docker 静态二进制: $file_name"
	download_file_verified "$url" "$tmp/$file_name" "${DOCKER_TGZ_SHA256:-}"
    tar -xzf "$tmp/$file_name" -C "$tmp"
	for source in "$tmp/docker/"*; do
		binary="$(basename "$source")"
		target="/usr/local/bin/${binary}"
		os_init_prepare_owned_path "docker-bin-${binary}" "$target"
		sudo install -m 0755 "$source" "$target"
	done
    rm -rf "$tmp"
    docker --version || true
}

install_compose_plugin() {
    local url file_name tmp
    url="$(compose_download_url)"
    file_name="$(basename "${url%%\?*}")"
    tmp="$(mktemp -d /tmp/docker-compose-XXXXXX)"

	install "安装 Docker Compose CLI 插件: $file_name"
	download_file_verified "$url" "$tmp/docker-compose" "${DOCKER_COMPOSE_SHA256:-}"
	os_init_prepare_owned_path "docker-compose-plugin" "$COMPOSE_PLUGIN"
	sudo install -m 0755 -D "$tmp/docker-compose" "$COMPOSE_PLUGIN"
    rm -rf "$tmp"
}

install_docker_arch_packages() {
	install "通过 pacman/AUR 安装 Docker 组件"
	pkg_install docker docker-compose docker-buildx
	os_init_mark_ownership "docker-arch-packages"
    docker --version || true
    docker compose version || true
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

write_daemon_config() {
    local tmp mirrors insecure
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

    printf '\n}\n' >> "$tmp"
	install "写入 Docker daemon 配置: $DAEMON_CFG"
	os_init_prepare_owned_path "docker-daemon-config" "$DAEMON_CFG"
	sudo install -m 0644 -D "$tmp" "$DAEMON_CFG"
    rm -f "$tmp"
}

write_systemd_units() {
	install "写入 containerd.service"
	os_init_prepare_owned_path "docker-containerd-service" "$CONTAINERD_SERVICE"
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
	os_init_prepare_owned_path "docker-service" "$DOCKER_SERVICE"
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
    user="$(real_user)"
    if [[ "$user" == "root" ]]; then
        skip "root 不需要加入 docker 用户组"
        return
    fi

    if ! getent group docker >/dev/null 2>&1; then
        install "创建 docker 用户组"
        sudo groupadd docker
    fi

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
    if systemctl list-unit-files containerd.service >/dev/null 2>&1; then
        sudo systemctl enable --now containerd.service || warn "containerd.service 启用失败，将继续尝试 docker.service"
    fi
    sudo systemctl enable --now docker.service
}

verify_docker() {
    local user
    user="$(real_user)"
    echo ""
    echo "=== Docker 信息 ==="
    docker --version || true
    docker compose version || true
    if systemctl is-active --quiet docker.service; then
        skip "Docker 服务正在运行"
    else
        warn "Docker 服务未运行，请查看: systemctl status docker.service"
    fi
    if [[ "$user" == "root" ]]; then
        skip "root 可直接使用 Docker"
    elif id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
        if [[ "$user" == "$(id -un)" ]] && ! id -nG | tr ' ' '\n' | grep -qx docker; then
            warn "用户 $user 已加入 docker 组，但当前终端会话尚未生效；请重新登录"
        else
            skip "用户 $user 可通过 docker 组使用 Docker"
        fi
    else
        warn "用户 $user 尚未加入 docker 组，免 sudo 使用 Docker 不会生效"
    fi
    sudo systemctl --no-pager --full status docker.service | sed -n '1,8p' || true
}

prepare_wsl_native_docker() {
    is_wsl || return 0
    require_wsl2
    if wsl_docker_desktop_integration_detected; then
        die "检测到 Docker Desktop WSL Integration。请先在 Docker Desktop 中关闭当前发行版的 Integration，再安装由本 WSL 发行版管理的原生 Docker Engine"
    fi
    install "WSL2 将使用当前 Linux 发行版内的原生 Docker Engine"
}

uninstall_docker() {
	require_systemd

	if is_arch; then
		if os_init_owned_path "docker-arch-packages"; then
			remove "停止并卸载由 OS Init 安装的 Docker 组件"
			sudo systemctl disable --now docker.service 2>/dev/null || true
			sudo systemctl disable --now containerd.service 2>/dev/null || true
			pkg_remove docker-buildx docker-compose docker 2>/dev/null || true
			os_init_forget_ownership "docker-arch-packages"
			os_init_restore_owned_path "docker-daemon-config" "$DAEMON_CFG" || true
		else
			warn "未找到 Docker 包所有权记录，保留软件包和服务"
		fi
	else
		if os_init_owned_path "docker-service" || os_init_owned_path "docker-containerd-service"; then
			remove "停止由 OS Init 管理的 Docker 服务"
			sudo systemctl disable --now docker.service 2>/dev/null || true
			sudo systemctl disable --now containerd.service 2>/dev/null || true
			sudo systemctl reset-failed docker.service containerd.service 2>/dev/null || true
		fi
		os_init_restore_owned_path "docker-service" "$DOCKER_SERVICE" || true
		os_init_restore_owned_path "docker-containerd-service" "$CONTAINERD_SERVICE" || true
		os_init_restore_owned_path "docker-compose-plugin" "$COMPOSE_PLUGIN" || true
		os_init_restore_owned_path "docker-daemon-config" "$DAEMON_CFG" || true
		sudo systemctl daemon-reload

		local binary
		for binary in containerd containerd-shim containerd-shim-runc-v2 ctr docker dockerd docker-init docker-proxy runc; do
			os_init_restore_owned_path "docker-bin-${binary}" "/usr/local/bin/${binary}" || true
		done
	fi

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
prepare_wsl_native_docker

if is_arch; then
    echo "[1/5] Docker 软件包..."
    install_docker_arch_packages

    echo "[2/5] daemon.json..."
    write_daemon_config

    echo "[3/5] systemd..."
    enable_docker_service

    echo "[4/5] docker 组..."
    ensure_docker_group

    echo "[5/5] 验证..."
    verify_docker
else
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
fi
echo ""
echo "=== Docker 安装完成 ==="

#!/usr/bin/env bash
# Docker 模块
# 负责安装 Docker / Docker Compose，并配置镜像源和服务。

render_docker_daemon_json() {
  log_info "写入 Docker daemon.json"
  backup_file_root "/etc/docker/daemon.json"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write /etc/docker/daemon.json"
    return 0
  fi

  sudo mkdir -p /etc/docker
  {
    echo '{'
    echo '  "registry-mirrors": ['
    local i
    for i in "${!DOCKER_MIRRORS[@]}"; do
      local comma=","
      [[ "${i}" -eq $((${#DOCKER_MIRRORS[@]} - 1)) ]] && comma=""
      printf '    "%s"%s\n' "${DOCKER_MIRRORS[$i]}" "${comma}"
    done
    echo '  ],'
    echo '  "log-driver": "json-file",'
    echo '  "log-opts": {'
    echo '    "max-size": "100m",'
    echo '    "max-file": "3"'
    echo '  },'
    echo '  "exec-opts": ["native.cgroupdriver=systemd"]'
    echo '}'
  } | sudo tee /etc/docker/daemon.json >/dev/null
}

install_docker_env() {
  if is_done "docker"; then
    log_info "Docker 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 Docker 环境"
  pacman_install docker docker-compose

  if [[ "${CONFIGURE_DOCKER_MIRRORS:-0}" -eq 1 ]]; then
    render_docker_daemon_json
  fi

  if [[ "${ENABLE_DOCKER_SERVICE:-0}" -eq 1 ]]; then
    log_info "启用 Docker 服务"
    enable_system_service_best_effort docker.service
  fi

  if [[ "${ADD_USER_TO_DOCKER_GROUP:-0}" -eq 1 ]]; then
    log_info "将当前用户加入 docker 用户组：${USER}"
    run_sudo usermod -aG docker "${USER}"
    log_warn "用户组变更需要重新登录后生效"
  fi

  verify_docker

  mark_done "docker"
  log_info "Docker 环境安装完成"
}

verify_docker() {
  log_info "验证 Docker 安装"
  run_cmd docker --version || true
  run_cmd docker compose version || true
}

ensure_docker() {
  if ! is_done "docker"; then
    install_docker_env
  fi
}

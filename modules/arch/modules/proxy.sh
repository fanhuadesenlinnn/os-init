#!/usr/bin/env bash
# shellcheck disable=SC1091
# Arch sing-box 扩展。Mihomo 由 OS Init 通用模块负责。

PROXY_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/proxy/config_source.sh
source "${PROXY_MODULE_DIR}/proxy/config_source.sh"
# shellcheck source=modules/proxy/sing_box.sh
source "${PROXY_MODULE_DIR}/proxy/sing_box.sh"
# shellcheck source=modules/proxy/common.sh
source "${PROXY_MODULE_DIR}/proxy/common.sh"

install_proxy_env() {
  if is_done "proxy"; then
    log_info "Proxy 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 sing-box 环境"
  install_sing_box
  configure_sing_box

  install_proxy_shell_env_template
  enable_proxy_service_if_needed
  verify_proxy_env

  mark_done "proxy"
  log_info "Proxy 环境安装完成"
}

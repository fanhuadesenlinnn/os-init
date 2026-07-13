#!/usr/bin/env bash
# shellcheck disable=SC1091
# Arch Mihomo 能力：保留原 Arch 配置预检、systemd 适配和 MetaCubeXD 部署。

PROXY_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/proxy/config_source.sh
source "${PROXY_MODULE_DIR}/proxy/config_source.sh"
# shellcheck source=modules/proxy/mihomo.sh
source "${PROXY_MODULE_DIR}/proxy/mihomo.sh"
# shellcheck source=modules/proxy/common.sh
source "${PROXY_MODULE_DIR}/proxy/common.sh"

install_proxy_env() {
  if is_done "proxy"; then
    log_info "Proxy 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 Mihomo 环境"
  install_mihomo
  configure_mihomo
  if [[ "${ENABLE_METACUBEXD:-0}" -eq 1 ]]; then
    install_metacubexd
  fi

  install_proxy_shell_env_template
  enable_proxy_service_if_needed
  verify_proxy_env

  mark_done "proxy"
  log_info "Proxy 环境安装完成"
}

#!/usr/bin/env bash
# Proxy 模块
# 负责安装 Mihomo / sing-box 代理核心。
# Mihomo 使用系统级 /etc/mihomo 配置和包自带 systemd 服务；sing-box 仍使用 ArchDevKit 用户级服务。

PROXY_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/proxy/config_source.sh
source "${PROXY_MODULE_DIR}/proxy/config_source.sh"
# shellcheck source=modules/proxy/mihomo.sh
source "${PROXY_MODULE_DIR}/proxy/mihomo.sh"
# shellcheck source=modules/proxy/sing_box.sh
source "${PROXY_MODULE_DIR}/proxy/sing_box.sh"
# shellcheck source=modules/proxy/common.sh
source "${PROXY_MODULE_DIR}/proxy/common.sh"

install_proxy_env() {
  if is_done "proxy"; then
    log_info "Proxy 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 Proxy 环境：${PROXY_CORE}"
  case "${PROXY_CORE:-mihomo}" in
    mihomo)
      install_mihomo
      configure_mihomo
      if [[ "${ENABLE_METACUBEXD:-0}" -eq 1 ]]; then
        install_metacubexd
      fi
      ;;
    sing-box)
      install_sing_box
      configure_sing_box
      ;;
    *)
      die "未知代理核心：${PROXY_CORE}"
      ;;
  esac

  install_proxy_shell_env_template
  enable_proxy_service_if_needed
  verify_proxy_env

  mark_done "proxy"
  log_info "Proxy 环境安装完成"
}

ensure_proxy_env() {
  if [[ "${ENABLE_PROXY:-0}" -eq 1 ]]; then
    install_proxy_env
  else
    log_info "当前配置未启用 Proxy，跳过"
  fi
}

#!/usr/bin/env bash
# Proxy 公共流程：套餐依赖、shell 模板、服务启用和验证输出。

proxy_service_name() {
  case "${PROXY_CORE:-mihomo}" in
    mihomo) printf "%s" "${MIHOMO_SERVICE_NAME:-mihomo.service}" ;;
    sing-box) printf "archdevkit-sing-box.service" ;;
    *) die "未知代理核心：${PROXY_CORE}" ;;
  esac
}

install_proxy_shell_env_template() {
  local rc_file

  log_info "写入 shell 代理环境变量模板（默认注释）"
  for rc_file in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    write_managed_block_from_stdin "${rc_file}" "proxy-env" 0644 <<'EOF'
# ArchDevKit proxy environment template. Uncomment when needed.
# export http_proxy="http://127.0.0.1:7890"
# export https_proxy="http://127.0.0.1:7890"
# export all_proxy="socks5://127.0.0.1:7890"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"
# export ALL_PROXY="$all_proxy"
# export no_proxy="localhost,127.0.0.1,::1"
# export NO_PROXY="$no_proxy"
EOF
  done
}

proxy_needs_archlinuxcn() {
  local package
  case "${PROXY_CORE:-mihomo}" in
    mihomo)
      package="${MIHOMO_PACKAGE:-mihomo}"
      package_needs_archlinuxcn_repo "${package}" && return 0
      if [[ "${ENABLE_METACUBEXD:-0}" -eq 1 ]]; then
        package_needs_archlinuxcn_repo "${METACUBEXD_PACKAGE:-metacubexd-bin}" && return 0
      fi
      ;;
    sing-box)
      package_needs_archlinuxcn_repo "${SING_BOX_PACKAGE:-sing-box}" && return 0
      ;;
  esac

  return 1
}

enable_proxy_service_if_needed() {
  [[ "${PROXY_AUTO_ENABLE_SERVICE:-0}" -eq 1 ]] || {
    log_warn "当前配置不自动启用 Proxy 服务"
    return 0
  }

  case "${PROXY_CORE:-mihomo}" in
    mihomo)
      if mihomo_service_ready; then
        enable_system_service "$(proxy_service_name)" || die "Mihomo 服务启动失败，请根据上方日志修正配置后重试"
      else
        log_warn "已跳过 Mihomo 服务启动；配置修正后执行：sudo systemctl enable --now ${MIHOMO_SERVICE_NAME:-mihomo.service}"
      fi
      ;;
    sing-box) enable_user_service "$(proxy_service_name)" ;;
  esac
}

verify_proxy_env() {
  log_info "验证 Proxy 环境"
  case "${PROXY_CORE:-mihomo}" in
    mihomo)
      run_cmd mihomo -v || true
      log_info "Mihomo 配置目录：${MIHOMO_CONFIG_DIR:-/etc/mihomo}"
      log_info "Mihomo 配置文件：${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
      log_info "Mihomo 系统服务：${MIHOMO_SERVICE_NAME:-mihomo.service}"
      log_info "Mihomo mixed-port：${MIHOMO_BIND_ADDRESS:-127.0.0.1}:${MIHOMO_MIXED_PORT:-7890}"
      log_info "Mihomo 控制接口：http://${MIHOMO_CONTROLLER_HOST:-127.0.0.1}:${MIHOMO_CONTROLLER_PORT:-9090}"
      log_info "Mihomo 规则源：原始 URL（不配置代理前缀）"
      if [[ "${ENABLE_METACUBEXD:-0}" -eq 1 ]]; then
        log_info "MetaCubeXD 面板由 Mihomo 托管：http://${MIHOMO_CONTROLLER_HOST:-127.0.0.1}:${MIHOMO_CONTROLLER_PORT:-9090}/ui/"
        log_info "MetaCubeXD UI 目录：$(mihomo_safe_external_ui_dir)"
      fi
      ;;
    sing-box)
      run_cmd sing-box version || true
      log_info "sing-box mixed-port：127.0.0.1:${SING_BOX_MIXED_PORT:-7890}"
      ;;
  esac
}

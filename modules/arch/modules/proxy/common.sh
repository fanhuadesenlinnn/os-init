#!/usr/bin/env bash
# Proxy 公共流程：套餐依赖、shell 模板、服务启用和验证输出。

proxy_service_name() {
  printf "os-init-arch-sing-box.service"
}

install_proxy_shell_env_template() {
  local rc_file

  log_info "写入 shell 代理环境变量模板（默认注释）"
  for rc_file in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    write_managed_block_from_stdin "${rc_file}" "proxy-env" 0644 <<'EOF'
# OS Init Arch proxy environment template. Uncomment when needed.
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

enable_proxy_service_if_needed() {
  [[ "${PROXY_AUTO_ENABLE_SERVICE:-0}" -eq 1 ]] || {
    log_warn "当前配置不自动启用 Proxy 服务"
    return 0
  }

  if [[ "${EUID}" -eq 0 ]]; then
    enable_system_service_best_effort "$(proxy_service_name)"
  else
    enable_user_service "$(proxy_service_name)"
  fi
}

verify_proxy_env() {
  log_info "验证 Proxy 环境"
  run_cmd sing-box version || true
  log_info "sing-box mixed-port：127.0.0.1:${SING_BOX_MIXED_PORT:-7890}"
}

#!/usr/bin/env bash
# Arch 现代 CLI 与排障工具集合。该能力依赖已配置的 archlinuxcn，
# 不属于其他模块的隐式基础设施。

cli_packages() {
  echo "rclone net-tools iotop iftop nethogs ripgrep fd fzf bat eza dust bottom procs bandwhich sd hyperfine just"
}

install_cli_tools() {
  if is_done "cli"; then
    log_info "现代 CLI 已处理，跳过"
    return 0
  fi

  local packages
  read -r -a packages <<<"$(cli_packages)"
  require_arch
  log_info "开始安装现代 CLI 与排障工具"
  install_packages_or_aur "${packages[@]}"
  mark_done "cli"
  log_info "现代 CLI 安装完成"
}

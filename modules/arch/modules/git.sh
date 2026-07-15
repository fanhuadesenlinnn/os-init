#!/usr/bin/env bash
# Git / GitHub 环境模块

install_git_env() {
  if is_done "git"; then
    log_info "Git 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 Git / GitHub CLI 环境"
  install_packages_or_aur git github-cli openssh

  log_info "配置 Git 默认行为"
  run_cmd git config --global init.defaultBranch main
  run_cmd git config --global pull.rebase false
  run_cmd git config --global core.editor nvim || true

  log_info "GitHub CLI 安装完成"
  log_warn "如果需要登录 GitHub，请手动执行：gh auth login && gh auth setup-git"

  mark_done "git"
}

ensure_git() {
  if ! is_done "git"; then
    install_git_env
  fi
}

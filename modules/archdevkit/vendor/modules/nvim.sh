#!/usr/bin/env bash
# Neovim 模块
# 只负责安装 Neovim 和部署个人配置，不隐式安装 runtime 模块。

install_nvim_env() {
  if is_done "nvim"; then
    log_info "Neovim 环境已处理，跳过"
    return 0
  fi

  log_info "开始安装 Neovim 环境"
  pacman_install neovim python-pynvim

  install_nvim_config

  if [[ "${SYNC_NVIM_PLUGINS:-0}" -eq 1 ]]; then
    sync_nvim_plugins
  else
    log_warn "当前配置关闭了 Neovim 插件同步"
  fi

  verify_nvim

  mark_done "nvim"
  log_info "Neovim 环境安装完成"
}

install_nvim_config() {
  log_info "安装个人 Neovim 配置"
  log_info "配置仓库：${NVIM_REPO}"
  log_info "配置分支：${NVIM_BRANCH:-默认分支}"
  clone_repo_safe "${NVIM_REPO}" "${NVIM_CONFIG_DIR}" "${NVIM_BRANCH}"
}

sync_nvim_plugins() {
  log_info "尝试同步 Neovim 插件"

  # 插件同步依赖 GitHub 网络，失败不应中断整个环境安装。
  # 用户可以稍后手动执行：nvim +Lazy sync
  if run_with_github_proxy nvim --headless "+Lazy! sync" +qa; then
    log_info "Neovim 插件同步完成"
  else
    log_warn "Neovim 插件同步失败，可能是 GitHub 网络或插件源问题"
    log_warn "可稍后手动执行：nvim +Lazy sync"
  fi
}

verify_nvim() {
  log_info "验证 Neovim"
  nvim --version | head -n 3 || true
  [[ -d "${NVIM_CONFIG_DIR}" ]] || die "Neovim 配置目录不存在：${NVIM_CONFIG_DIR}"
}

ensure_nvim() {
  if ! is_done "nvim"; then
    install_nvim_env
  fi
}

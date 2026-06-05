#!/usr/bin/env bash
# Zsh 模块
# 安装 zsh、oh-my-zsh、常用插件、Powerlevel10k 和可选 p10k 配置。

install_shell_zsh() {
  if is_done "shell_zsh"; then
    log_info "Zsh 环境已处理，跳过"
    return 0
  fi

  if shell_needs_fonts; then
    ensure_fonts
  else
    log_info "当前 Zsh 配置不依赖字体模块，跳过字体安装"
  fi

  log_info "开始安装 Zsh / Oh My Zsh 环境"
  pacman_install zsh zsh-completions fzf

  if [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]; then
    install_oh_my_zsh
    install_zsh_plugins
  else
    log_warn "当前配置未启用 Oh My Zsh，跳过 Oh My Zsh 与插件安装"
  fi

  if [[ "${INSTALL_POWERLEVEL10K:-0}" -eq 1 ]]; then
    if [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]; then
      install_powerlevel10k
    else
      log_warn "Powerlevel10k 配置依赖 Oh My Zsh，已跳过主题安装"
    fi
  fi

  render_zshrc

  if [[ "${INSTALL_P10K_CONFIG:-0}" -eq 1 && "${INSTALL_POWERLEVEL10K:-0}" -eq 1 ]]; then
    install_p10k_config
  elif [[ "${INSTALL_P10K_CONFIG:-0}" -eq 1 ]]; then
    log_warn "未启用 Powerlevel10k，跳过 p10k 配置安装"
  fi

  change_default_shell_if_needed
  verify_zsh

  mark_done "shell_zsh"
  log_info "Zsh 环境安装完成"
}

shell_needs_fonts() {
  [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 && "${INSTALL_POWERLEVEL10K:-0}" -eq 1 ]]
}

shell_needs_repo_clone() {
  [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]
}

install_oh_my_zsh() {
  log_info "安装 Oh My Zsh"
  clone_repo_safe "${OH_MY_ZSH_REPO}" "${HOME}/.oh-my-zsh" ""
}

install_zsh_plugins() {
  local custom_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

  log_info "安装 zsh-autosuggestions"
  clone_repo_safe "${ZSH_AUTOSUGGESTIONS_REPO}" "${custom_dir}/plugins/zsh-autosuggestions" ""

  log_info "安装 zsh-syntax-highlighting"
  clone_repo_safe "${ZSH_SYNTAX_HIGHLIGHTING_REPO}" "${custom_dir}/plugins/zsh-syntax-highlighting" ""
}

install_powerlevel10k() {
  local custom_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

  log_info "安装 Powerlevel10k"
  clone_repo_safe "${POWERLEVEL10K_REPO}" "${custom_dir}/themes/powerlevel10k" ""
}

render_zshrc() {
  log_info "生成 ~/.zshrc"
  backup_path "${HOME}/.zshrc"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${HOME}/.zshrc"
    return 0
  fi

  cat > "${HOME}/.zshrc" <<'EOF'
# ArchDevKit 生成的 zsh 配置
# 如需修改主题或插件，建议先备份该文件。

if [[ -d "${HOME}/.local/bin" ]]; then
  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) export PATH="${HOME}/.local/bin:${PATH}" ;;
  esac
fi
EOF

  if [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]; then
    cat >> "${HOME}/.zshrc" <<EOF
export ZSH="\${HOME}/.oh-my-zsh"

ZSH_THEME="${ZSH_THEME_NAME:-powerlevel10k/powerlevel10k}"

plugins=(${ZSH_PLUGINS:-git zsh-autosuggestions zsh-syntax-highlighting fzf docker kubectl})

source "\${ZSH}/oh-my-zsh.sh"

[[ -f "\${HOME}/.p10k.zsh" ]] && source "\${HOME}/.p10k.zsh"
EOF
  else
    cat >> "${HOME}/.zshrc" <<'EOF'
autoload -Uz compinit
compinit

PROMPT='%n@%m %1~ %# '
EOF
  fi

  cat >> "${HOME}/.zshrc" <<'EOF'
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

[[ -f "${HOME}/.config/archdevkit/mise-china.env" ]] && source "${HOME}/.config/archdevkit/mise-china.env"

if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
  source /usr/share/fzf/key-bindings.zsh
fi

if [[ -f /usr/share/fzf/completion.zsh ]]; then
  source /usr/share/fzf/completion.zsh
fi
EOF
}

install_p10k_config() {
  log_info "安装 Powerlevel10k 配置"

  [[ -f "${P10K_CONFIG_SOURCE}" ]] || {
    log_warn "未找到 p10k 配置文件：${P10K_CONFIG_SOURCE}，跳过"
    return 0
  }

  backup_path "${HOME}/.p10k.zsh"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ cp ${P10K_CONFIG_SOURCE} ${HOME}/.p10k.zsh"
    return 0
  fi

  cp -a "${P10K_CONFIG_SOURCE}" "${HOME}/.p10k.zsh"
  log_info "已安装：${HOME}/.p10k.zsh"
}

change_default_shell_if_needed() {
  [[ "${SET_ZSH_AS_DEFAULT:-0}" -eq 1 ]] || return 0

  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ "${SHELL:-}" == "${zsh_path}" ]]; then
    log_info "当前默认 shell 已是 zsh"
    return 0
  fi

  if ! confirm_yes "是否将默认 shell 切换为 zsh？重新登录后生效"; then
    log_warn "已跳过默认 shell 切换"
    return 0
  fi

  log_info "切换默认 shell 为：${zsh_path}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ chsh -s ${zsh_path}"
    return 0
  fi

  chsh -s "${zsh_path}" || sudo chsh -s "${zsh_path}" "${USER}"
}

verify_zsh() {
  log_info "验证 Zsh"
  run_cmd zsh --version || true
}

ensure_shell_zsh() {
  if ! is_done "shell_zsh"; then
    install_shell_zsh
  fi
}

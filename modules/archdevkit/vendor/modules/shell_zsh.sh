#!/usr/bin/env bash
# Zsh 模块
# 安装 zsh、oh-my-zsh、常用插件，以及 Starship/Powerlevel10k 提示符。

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
  local shell_packages=(zsh zsh-completions fzf)
  if shell_uses_starship; then
    shell_packages+=(starship)
  fi
  pacman_install "${shell_packages[@]}"

  if [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]; then
    install_oh_my_zsh
    install_zsh_plugins
  else
    log_warn "当前配置未启用 Oh My Zsh，跳过 Oh My Zsh 与插件安装"
  fi

  if shell_uses_p10k && [[ "${INSTALL_POWERLEVEL10K:-0}" -eq 1 ]]; then
    if [[ "${INSTALL_OH_MY_ZSH:-0}" -eq 1 ]]; then
      install_powerlevel10k
    else
      log_warn "Powerlevel10k 配置依赖 Oh My Zsh，已跳过主题安装"
    fi
  fi

  if shell_uses_starship; then
    install_starship_templates
  fi

  render_zshrc
  render_bashrc_terminal

  if shell_uses_p10k && [[ "${INSTALL_P10K_CONFIG:-0}" -eq 1 && "${INSTALL_POWERLEVEL10K:-0}" -eq 1 ]]; then
    install_p10k_config
  elif shell_uses_p10k && [[ "${INSTALL_P10K_CONFIG:-0}" -eq 1 ]]; then
    log_warn "未启用 Powerlevel10k，跳过 p10k 配置安装"
  fi

  change_default_shell_if_needed
  verify_zsh

  mark_done "shell_zsh"
  log_info "Zsh 环境安装完成"
}

shell_needs_fonts() {
  case "$(shell_prompt_engine)" in
    starship|powerlevel10k) return 0 ;;
    *) return 1 ;;
  esac
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

shell_prompt_engine() {
  local engine
  engine="$(printf '%s' "${SHELL_PROMPT_ENGINE:-starship}" | tr '[:upper:]' '[:lower:]')"
  case "${engine}" in
    p10k) echo "powerlevel10k" ;;
    *) echo "${engine}" ;;
  esac
}

shell_uses_starship() {
  [[ "$(shell_prompt_engine)" == "starship" ]]
}

shell_uses_p10k() {
  [[ "$(shell_prompt_engine)" == "powerlevel10k" ]]
}

archdevkit_terminal_template_source_dir() {
  local dir
  for dir in "${SCRIPT_DIR}/../../terminal" "${SCRIPT_DIR}/files/terminal"; do
    if [[ -f "${dir}/starship-rich.toml" ]]; then
      printf '%s\n' "${dir}"
      return 0
    fi
  done
  return 1
}

install_starship_templates() {
  local source_dir target_dir name src dst
  source_dir="$(archdevkit_terminal_template_source_dir)" || {
    log_warn "未找到 os-init Starship 模板，Starship 将使用默认配置"
    return 0
  }
  target_dir="${HOME}/.config/os-init/terminal"
  mkdir -p "${target_dir}"

  for name in rich simple plain; do
    src="${source_dir}/starship-${name}.toml"
    dst="${target_dir}/starship-${name}.toml"
    [[ -f "${src}" ]] || continue
    if [[ -f "${dst}" ]] && cmp -s "${src}" "${dst}"; then
      log_info "Starship ${name} 模板已是最新"
      continue
    fi
    backup_path "${dst}"
    cp -a "${src}" "${dst}"
    log_info "已安装 Starship ${name} 模板：${dst}"
  done
}

starship_shell_block() {
  local shell_name="$1" default_style
  default_style="${OS_INIT_TERMINAL_STYLE:-auto}"
  cat <<EOF
: "\${OS_INIT_TERMINAL_STYLE:=${default_style}}"
export OS_INIT_TERMINAL_STYLE

_os_init_starship_config() {
  local style config_dir candidate
  style="\${OS_INIT_TERMINAL_STYLE:-auto}"

  case "\${style}" in
    none|off|0|false|disable|disabled)
      return 1
      ;;
    rich|simple|plain)
      ;;
    auto|"")
      if [[ -z "\${TERM:-}" || "\${TERM:-}" == "dumb" ]]; then
        style="plain"
      elif [[ -n "\${SSH_CONNECTION:-}\${SSH_TTY:-}" ]]; then
        style="simple"
      elif [[ -n "\${DISPLAY:-}\${WAYLAND_DISPLAY:-}" || "\${COLORTERM:-}" == "truecolor" || "\${COLORTERM:-}" == "24bit" ]]; then
        style="rich"
      else
        style="simple"
      fi
      ;;
    *)
      style="simple"
      ;;
  esac

  config_dir="\${OS_INIT_TERMINAL_CONFIG_DIR:-\${HOME}/.config/os-init/terminal}"
  candidate="\${config_dir}/starship-\${style}.toml"
  if [[ -f "\${candidate}" ]]; then
    export STARSHIP_CONFIG="\${candidate}"
    return 0
  fi
  if [[ -f "\${HOME}/.config/starship.toml" ]]; then
    export STARSHIP_CONFIG="\${HOME}/.config/starship.toml"
  fi
  return 0
}

if command -v starship >/dev/null 2>&1 && _os_init_starship_config; then
  eval "\$(starship init ${shell_name})"
fi
unset -f _os_init_starship_config >/dev/null 2>&1 || true
EOF
}

terminal_alias_block() {
  local default_aliases default_bat_theme
  default_aliases="${OS_INIT_TERMINAL_ENABLE_ALIASES:-1}"
  default_bat_theme="${OS_INIT_TERMINAL_BAT_THEME:-Catppuccin Mocha}"
  cat <<EOF
: "\${OS_INIT_TERMINAL_ENABLE_ALIASES:=${default_aliases}}"
: "\${OS_INIT_TERMINAL_BAT_THEME:=${default_bat_theme}}"
export OS_INIT_TERMINAL_ENABLE_ALIASES OS_INIT_TERMINAL_BAT_THEME

if [[ "\$-" == *i* && "\${OS_INIT_TERMINAL_ENABLE_ALIASES}" != "0" ]]; then
  if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --group-directories-first --git'
    alias la='eza -la --group-directories-first'
    alias tree='eza --tree --group-directories-first'
  else
    alias ll='ls -lah'
    alias la='ls -la'
  fi

  if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
  fi
  if command -v bat >/dev/null 2>&1; then
    export BAT_THEME="\${BAT_THEME:-\${OS_INIT_TERMINAL_BAT_THEME}}"
  fi
fi
EOF
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
    local zsh_theme="${ZSH_THEME_NAME:-}"
    if shell_uses_p10k; then
      zsh_theme="${zsh_theme:-powerlevel10k/powerlevel10k}"
    fi
    cat >> "${HOME}/.zshrc" <<EOF
export ZSH="\${HOME}/.oh-my-zsh"

ZSH_THEME="${zsh_theme}"

plugins=(${ZSH_PLUGINS:-git zsh-autosuggestions zsh-syntax-highlighting fzf docker kubectl})

source "\${ZSH}/oh-my-zsh.sh"
EOF
    if shell_uses_p10k; then
      cat >> "${HOME}/.zshrc" <<'EOF'

[[ -f "${HOME}/.p10k.zsh" ]] && source "${HOME}/.p10k.zsh"
EOF
    fi
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

  {
    printf '\n# >>> os-init terminal-style >>>\n'
    terminal_alias_block
    printf '# <<< os-init terminal-style <<<\n'
    if shell_uses_starship; then
      printf '\n# >>> os-init starship >>>\n'
      starship_shell_block zsh
      printf '# <<< os-init starship <<<\n'
    fi
  } >> "${HOME}/.zshrc"
}

render_bashrc_terminal() {
  write_managed_block_from_stdin "${HOME}/.bashrc" "terminal-style" 0644 < <(terminal_alias_block)
  if shell_uses_starship; then
    write_managed_block_from_stdin "${HOME}/.bashrc" "starship" 0644 < <(starship_shell_block bash)
  fi
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
  if shell_uses_starship; then
    run_cmd starship --version || true
  fi
}

ensure_shell_zsh() {
  if ! is_done "shell_zsh"; then
    install_shell_zsh
  fi
}

#!/usr/bin/env bash
# Hyprland 桌面输入法逻辑：Fcitx5 包、环境变量和 Rime 配置。

install_input_method_packages() {
  [[ "${ENABLE_FCITX5:-0}" -eq 1 ]] || {
    log_warn "当前配置未启用 Fcitx5，跳过输入法包安装"
    return 0
  }

  case "${INPUT_METHOD_ENGINE:-rime}" in
    rime)
      install_packages_or_aur fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-rime rime-luna-pinyin
      ;;
    *)
      die "暂不支持的输入法引擎：${INPUT_METHOD_ENGINE}"
      ;;
  esac
}

configure_fcitx5_env() {
  [[ "${ENABLE_FCITX5:-0}" -eq 1 ]] || return 0

  local env_file="${HOME}/.config/environment.d/fcitx5.conf"
  log_info "配置 Fcitx5 中文输入法环境变量"

  write_file_from_stdin "${env_file}" 0644 <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
INPUT_METHOD=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
GDK_BACKEND=wayland,x11
XCURSOR_SIZE=24
EOF
}

configure_rime_if_needed() {
  [[ "${ENABLE_FCITX5:-0}" -eq 1 ]] || return 0
  [[ "${INPUT_METHOD_ENGINE:-rime}" == "rime" ]] || return 0

  install_rime_config_repo
  configure_fcitx5_rime_profile
}

install_rime_config_repo() {
  [[ "${INSTALL_RIME_CONFIG:-1}" -eq 1 ]] || {
    log_warn "当前配置不安装 Rime 配置仓库"
    return 0
  }

  local repo="${RIME_CONFIG_REPO:-}"
  local branch="${RIME_CONFIG_BRANCH:-}"
  local rime_dir="${RIME_CONFIG_DIR:-${HOME}/.local/share/fcitx5/rime}"
  local actual_url tmp_dir

  [[ -n "${repo}" ]] || die "Rime 配置仓库地址为空"
  ensure_git_command

  actual_url="$(github_proxy_url "${repo}")"
  tmp_dir="$(mktemp -d)"

  log_info "安装 Rime 配置仓库：${repo}"
  [[ "${repo}" != "${actual_url}" ]] && log_info "实际下载地址：${actual_url}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    if [[ -n "${branch}" ]]; then
      echo "+ git clone --depth=1 -b ${branch} ${actual_url} ${tmp_dir}/repo"
    else
      echo "+ git clone --depth=1 ${actual_url} ${tmp_dir}/repo"
    fi
    echo "+ backup ${rime_dir}"
    echo "+ install Rime config files -> ${rime_dir}"
    rmdir "${tmp_dir}"
    return 0
  fi

  local args=(clone --depth=1)
  [[ -n "${branch}" ]] && args+=(-b "${branch}")
  args+=("${actual_url}" "${tmp_dir}/repo")

  git "${args[@]}" || {
    rm -rf "${tmp_dir}"
    die "克隆 Rime 配置仓库失败：${repo}"
  }

  backup_path "${rime_dir}"
  mkdir -p "${rime_dir}"
  find "${tmp_dir}/repo" -mindepth 1 -maxdepth 1 \
    ! -name ".git" \
    ! -name ".gitignore" \
    ! -name "README.md" \
    ! -name "install.sh" \
    -exec cp -a {} "${rime_dir}/" \;
  rm -rf "${tmp_dir}"
  log_info "Rime 配置已安装到：${rime_dir}"
}

configure_fcitx5_rime_profile() {
  local fcitx5_dir="${HOME}/.config/fcitx5"
  local schema="${RIME_SCHEMA:-luna_pinyin_simp}"

  log_info "配置 Fcitx5 默认输入法为 Rime：${schema}"

  write_file_from_stdin "${fcitx5_dir}/profile" 0644 <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=rime
Layout=

[GroupOrder]
0=Default
EOF
}

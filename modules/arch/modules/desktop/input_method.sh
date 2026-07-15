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
  local hypr_env_file="${HOME}/.config/hypr/conf/os-init-fcitx5.conf"
  log_info "配置 Fcitx5 中文输入法环境变量"

  fcitx5_env_pairs | write_file_from_stdin "${env_file}" 0644
  fcitx5_env_pairs | awk -F= '{key=$1; sub(/^[^=]*=/, "", $0); print "env = " key "," $0}' \
    | write_file_from_stdin "${hypr_env_file}" 0644
}

fcitx5_env_pairs() {
  cat <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
QT_IM_MODULES=wayland;fcitx;ibus
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
  local actual_url tmp_dir source_dir

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
    echo "+ safely merge Rime public config -> ${rime_dir}"
    echo "+ preserve custom_phrase.txt, *.userdb, sync, installation*.yaml, and user*.yaml"
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

  source_dir="${tmp_dir}/repo"
  select_rime_schema_in_file "${source_dir}/default.custom.yaml" "${RIME_SCHEMA:-luna_pinyin_simp}"
  sync_rime_config_tree "${source_dir}" "${rime_dir}"
  rm -rf "${tmp_dir}"
  log_info "Rime 配置已安装到：${rime_dir}"
  reload_rime_config
}

select_rime_schema_in_file() {
  local file="$1" schema="$2" tmp
  [[ -f "${file}" ]] || die "Rime 默认配置不存在：${file}"
  [[ "${schema}" =~ ^[A-Za-z0-9_.+-]+$ ]] || die "无效的 Rime 方案名：${schema}"
  awk -v wanted="${schema}" '
    /^[[:space:]]*-[[:space:]]*schema:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*schema:[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      if (value == wanted) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "${file}" || die "Rime 配置仓库不包含方案：${schema}"

  tmp="$(mktemp)"
  awk -v wanted="${schema}" '
    function flush_schema_list() {
      if (selected != "") print selected
      if (others != "") printf "%s", others
      selected = ""
      others = ""
    }
    /^[[:space:]]*schema_list:[[:space:]]*$/ {
      in_schema_list = 1
      print
      next
    }
    in_schema_list && /^[[:space:]]*-[[:space:]]*schema:[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*schema:[[:space:]]*/, "", value)
      sub(/[[:space:]#].*$/, "", value)
      if (value == wanted) selected = $0
      else others = others $0 ORS
      next
    }
    in_schema_list {
      flush_schema_list()
      in_schema_list = 0
    }
    { print }
    END {
      if (in_schema_list) flush_schema_list()
    }
  ' "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

sync_rime_config_tree() {
  local source_dir="$1" target_dir="$2" backup_dir
  [[ -d "${source_dir}" ]] || die "Rime 配置源目录不存在：${source_dir}"
  [[ -n "${target_dir}" && "${target_dir}" != "/" ]] || die "不安全的 Rime 配置目录：${target_dir}"
  require_cmd rsync

  backup_dir="$(state_root)/backups/rime-config/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${target_dir}" "${backup_dir}"
  rsync -a --backup --backup-dir="${backup_dir}" \
    --exclude='.git/' \
    --exclude='.gitignore' \
    --exclude='README.md' \
    --exclude='install.sh' \
    --exclude='karabiner/' \
    --exclude='custom_phrase.txt' \
    --exclude='build/' \
    --exclude='*.userdb/' \
    --exclude='sync/' \
    --exclude='installation*.yaml' \
    --exclude='user*.yaml' \
    "${source_dir}/" "${target_dir}/"

  if [[ ! -e "${target_dir}/custom_phrase.txt" && -f "${source_dir}/custom_phrase.txt" ]]; then
    cp -a "${source_dir}/custom_phrase.txt" "${target_dir}/custom_phrase.txt"
  fi
  if ! find "${backup_dir}" -mindepth 1 -print -quit | grep -q .; then
    rmdir "${backup_dir}" 2>/dev/null || true
  else
    log_warn "被更新的旧版 Rime 公共配置已备份到：${backup_dir}"
  fi
}

reload_rime_config() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ fcitx5-remote -r # 如果当前图形会话正在运行 Fcitx5"
    return 0
  fi
  if command -v fcitx5-remote >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if fcitx5-remote -r >/dev/null 2>&1; then
      log_info "已通知 Fcitx5 重新部署 Rime 配置"
      return 0
    fi
  fi
  log_warn "当前会话无法重新加载 Fcitx5；配置会在下次启动输入法或重新登录后生效"
}

desktop_rime_quick_verify() {
  local rime_dir first_schema
  [[ "${ENABLE_FCITX5:-0}" -eq 1 ]] || return 0
  need_cmd fcitx5 || return 1
  pacman -Q fcitx5-rime >/dev/null 2>&1 || return 1
  grep -Fq 'DefaultIM=rime' "${HOME}/.config/fcitx5/profile" || return 1
  grep -Fq 'QT_IM_MODULES=wayland;fcitx;ibus' "${HOME}/.config/environment.d/fcitx5.conf" || return 1
  if [[ "${INSTALL_RIME_CONFIG:-1}" -eq 1 ]]; then
    rime_dir="${RIME_CONFIG_DIR:-${HOME}/.local/share/fcitx5/rime}"
    [[ -f "${rime_dir}/default.custom.yaml" ]] || return 1
    first_schema="$(sed -n 's/^[[:space:]]*- schema:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "${rime_dir}/default.custom.yaml" | head -1)"
    [[ "${first_schema}" == "${RIME_SCHEMA:-luna_pinyin_simp}" ]] || return 1
  fi
}

configure_fcitx5_rime_profile() {
  local fcitx5_dir="${HOME}/.config/fcitx5"
  local schema="${RIME_SCHEMA:-luna_pinyin_simp}"
  local profile="${fcitx5_dir}/profile" tmp next_item

  log_info "配置 Fcitx5 默认输入法为 Rime：${schema}"

  if [[ ! -f "${profile}" ]]; then
    write_file_from_stdin "${profile}" 0644 <<'EOF'
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
    return 0
  fi

  tmp="$(mktemp)"
  awk '
    function ensure_default_im() {
      if (in_group && !default_written) print "DefaultIM=rime"
    }
    /^\[Groups\/0\]$/ {
      ensure_default_im()
      in_group = 1
      default_written = 0
      print
      next
    }
    in_group && /^\[/ {
      ensure_default_im()
      in_group = 0
    }
    in_group && /^DefaultIM=/ {
      if (!default_written) print "DefaultIM=rime"
      default_written = 1
      next
    }
    { print }
    END { ensure_default_im() }
  ' "${profile}" > "${tmp}"

  if ! awk '
    /^\[Groups\/0\/Items\/[0-9]+\]$/ { in_default_group_item = 1; next }
    /^\[/ { in_default_group_item = 0 }
    in_default_group_item && $0 == "Name=rime" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${tmp}"; then
    next_item="$(awk '
      /^\[Groups\/0\/Items\/[0-9]+\]$/ {
        value = $0
        sub(/^\[Groups\/0\/Items\//, "", value)
        sub(/\]$/, "", value)
        if (value >= max) max = value + 1
      }
      END { print max + 0 }
    ' "${tmp}")"
    printf '\n[Groups/0/Items/%s]\nName=rime\nLayout=\n' "${next_item}" >> "${tmp}"
  fi

  install_file_from_temp "${tmp}" "${profile}" 0644
  rm -f "${tmp}"
}

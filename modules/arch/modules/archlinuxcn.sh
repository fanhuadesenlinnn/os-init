#!/usr/bin/env bash
# archlinuxcn 软件源模块
# 该模块会修改 /etc/pacman.conf，执行前会自动备份。

ARCHLINUXCN_PACMAN_CONF="${ARCHLINUXCN_PACMAN_CONF:-/etc/pacman.conf}"

archlinuxcn_server_candidates() {
  local candidate seen=""
  local candidates=()
  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] && candidates+=("${candidate}")
  done < <(awk '
    /^\[archlinuxcn\][[:space:]]*$/ { in_repo=1; next }
    /^\[/ { in_repo=0 }
    in_repo && /^[[:space:]]*Server[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      print
    }
  ' "${ARCHLINUXCN_PACMAN_CONF}")
  candidates+=(
    "${ARCHLINUXCN_SERVER}"
    "https://mirrors.ustc.edu.cn/archlinuxcn/\$arch"
    "https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch"
    "https://repo.archlinuxcn.org/\$arch"
  )
  for candidate in "${candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    case " ${seen} " in
      *" ${candidate} "*) continue ;;
    esac
    seen="${seen} ${candidate}"
    printf '%s\n' "${candidate}"
  done
}

remove_archlinuxcn_siglevel() {
  local tmp_file
  tmp_file="$(mktemp)"
  awk '
    /^\[archlinuxcn\][[:space:]]*$/ { in_repo=1; print; next }
    /^\[/ { in_repo=0 }
    in_repo && /^[[:space:]]*SigLevel[[:space:]]*=/ { next }
    { print }
  ' "${ARCHLINUXCN_PACMAN_CONF}" > "${tmp_file}"
  run_sudo install -m 0644 "${tmp_file}" "${ARCHLINUXCN_PACMAN_CONF}"
  rm -f "${tmp_file}"
}

rewrite_archlinuxcn_repo() {
  local server="$1" tmp_file
  tmp_file="$(mktemp)"

  # archlinuxcn-keyring 要求仓库继承 pacman 的全局签名策略。这里同时
  # 清理旧版 OS Init 写入的 TrustAll/TrustedOnly，但不修改其他仓库。
  awk -v server="${server}" '
    BEGIN { in_repo=0; server_written=0 }
    /^\[archlinuxcn\][[:space:]]*$/ {
      in_repo=1
      server_written=0
      print
      next
    }
    /^\[/ {
      if (in_repo && server_written == 0) print "Server = " server
      in_repo=0
      print
      next
    }
    in_repo && /^[[:space:]]*SigLevel[[:space:]]*=/ { next }
    in_repo && /^[[:space:]]*Server[[:space:]]*=/ {
      if (server_written == 0) print "Server = " server
      server_written=1
      next
    }
    { print }
    END {
      if (in_repo && server_written == 0) print "Server = " server
    }
  ' "${ARCHLINUXCN_PACMAN_CONF}" > "${tmp_file}"

  run_sudo install -m 0644 "${tmp_file}" "${ARCHLINUXCN_PACMAN_CONF}"
  rm -f "${tmp_file}"
}

append_archlinuxcn_repo() {
  local server="$1" tmp_file
  tmp_file="$(mktemp)"
  cp -a "${ARCHLINUXCN_PACMAN_CONF}" "${tmp_file}"
  cat >> "${tmp_file}" <<EOF

# >>> OS Init Arch: archlinuxcn >>>
[archlinuxcn]
Server = ${server}
# <<< OS Init Arch: archlinuxcn <<<
EOF
  run_sudo install -m 0644 "${tmp_file}" "${ARCHLINUXCN_PACMAN_CONF}"
  rm -f "${tmp_file}"
}

select_working_archlinuxcn_server() {
  local server
  while IFS= read -r server; do
    [[ "${server}" == "${ARCHLINUXCN_SKIP_SERVER:-}" ]] && continue
    log_info "测试 archlinuxcn 镜像：${server}"
    rewrite_archlinuxcn_repo "${server}"
    if run_sudo pacman -Sy --noconfirm; then
      ARCHLINUXCN_ACTIVE_SERVER="${server}"
      return 0
    fi
    log_warn "archlinuxcn 镜像同步失败，尝试下一个镜像"
  done < <(archlinuxcn_server_candidates)
  die "所有 archlinuxcn 镜像均同步失败，请检查网络、代理和系统时间"
}

install_archlinuxcn() {
  if is_done "archlinuxcn"; then
    log_info "archlinuxcn 源已处理，跳过"
    return 0
  fi

  log_info "开始配置 archlinuxcn 源"
  backup_file_root "${ARCHLINUXCN_PACMAN_CONF}"

  if grep -q '^\[archlinuxcn\][[:space:]]*$' "${ARCHLINUXCN_PACMAN_CONF}"; then
    log_info "检测到已有 archlinuxcn 配置，迁移为默认签名策略"
    remove_archlinuxcn_siglevel
  else
    log_info "追加 archlinuxcn 源：${ARCHLINUXCN_SERVER}"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      echo "+ append archlinuxcn block to ${ARCHLINUXCN_PACMAN_CONF}"
    else
      append_archlinuxcn_repo "${ARCHLINUXCN_SERVER}"
    fi
  fi

  select_working_archlinuxcn_server

  log_info "安装 archlinuxcn-keyring"
  run_sudo pacman -S --needed --noconfirm archlinuxcn-keyring

  if [[ "${INSTALL_ARCHLINUXCN_MIRRORLIST:-0}" -eq 1 ]]; then
    log_info "安装 archlinuxcn-mirrorlist-git"
    run_sudo pacman -S --needed --noconfirm archlinuxcn-mirrorlist-git || \
      log_warn "archlinuxcn-mirrorlist-git 安装失败，继续使用已验证的 Server"
  fi

  if ! run_sudo pacman -Syu --noconfirm; then
    log_warn "完整同步失败，重新选择 archlinuxcn 镜像后重试"
    ARCHLINUXCN_SKIP_SERVER="${ARCHLINUXCN_ACTIVE_SERVER}"
    select_working_archlinuxcn_server
    unset ARCHLINUXCN_SKIP_SERVER
    run_sudo pacman -Syu --noconfirm
  fi

  mark_done "archlinuxcn"
  log_info "archlinuxcn 源配置完成：${ARCHLINUXCN_ACTIVE_SERVER}"
}

ensure_archlinuxcn() {
  if [[ "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]]; then
    install_archlinuxcn
  else
    log_info "当前配置未启用 archlinuxcn，跳过"
  fi
}

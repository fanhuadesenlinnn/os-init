#!/usr/bin/env bash
# archlinuxcn 软件源模块
# 该模块会修改 /etc/pacman.conf，执行前会自动备份。

harden_archlinuxcn_siglevel() {
  local tmp_file
  tmp_file="$(mktemp)"

  # 安装 keyring 后，将临时 TrustAll 调整为 TrustedOnly。
  # 这样既能解决首次安装 keyring 的信任问题，也避免长期保留过宽的签名策略。
  awk '
    BEGIN { in_repo=0; sig_seen=0 }
    /^\[archlinuxcn\]/ {
      in_repo=1
      sig_seen=0
      print
      next
    }
    /^\[/ {
      if (in_repo && sig_seen == 0) {
        print "SigLevel = Optional TrustedOnly"
      }
      in_repo=0
      sig_seen=0
      print
      next
    }
    in_repo && /^SigLevel[[:space:]]*=/ {
      print "SigLevel = Optional TrustedOnly"
      sig_seen=1
      next
    }
    { print }
    END {
      if (in_repo && sig_seen == 0) {
        print "SigLevel = Optional TrustedOnly"
      }
    }
  ' /etc/pacman.conf > "${tmp_file}"

  run_sudo install -m 0644 "${tmp_file}" /etc/pacman.conf
  rm -f "${tmp_file}"
}

install_archlinuxcn() {
  local tmp_file
  if is_done "archlinuxcn"; then
    log_info "archlinuxcn 源已处理，跳过"
    return 0
  fi

  log_info "开始配置 archlinuxcn 源"
  backup_file_root "/etc/pacman.conf"

  if grep -q '^\[archlinuxcn\]' /etc/pacman.conf; then
    log_warn "检测到 /etc/pacman.conf 已存在 archlinuxcn 配置，跳过追加"
  else
    log_info "追加 archlinuxcn 源：${ARCHLINUXCN_SERVER}"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      echo "+ append archlinuxcn block to /etc/pacman.conf"
    else
      tmp_file="$(mktemp)"
      cp -a /etc/pacman.conf "${tmp_file}"
      cat >> "${tmp_file}" <<EOF

[archlinuxcn]
SigLevel = Optional TrustAll
Server = ${ARCHLINUXCN_SERVER}
EOF
      run_sudo install -m 0644 "${tmp_file}" /etc/pacman.conf
      rm -f "${tmp_file}"
    fi
  fi

  log_info "刷新软件源并安装 archlinuxcn-keyring"
  run_sudo pacman -Sy --needed --noconfirm archlinuxcn-keyring

  harden_archlinuxcn_siglevel

  if [[ "${INSTALL_ARCHLINUXCN_MIRRORLIST:-0}" -eq 1 ]]; then
    log_info "安装 archlinuxcn-mirrorlist-git"
    run_sudo pacman -S --needed --noconfirm archlinuxcn-mirrorlist-git || \
      log_warn "archlinuxcn-mirrorlist-git 安装失败，可稍后手动安装"
  fi

  run_sudo pacman -Syu --noconfirm

  mark_done "archlinuxcn"
  log_info "archlinuxcn 源配置完成"
}

ensure_archlinuxcn() {
  if [[ "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]]; then
    install_archlinuxcn
  else
    log_info "当前配置未启用 archlinuxcn，跳过"
  fi
}

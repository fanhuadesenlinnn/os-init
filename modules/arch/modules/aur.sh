#!/usr/bin/env bash
# AUR Helper is user-scoped because makepkg refuses to run as root.

install_aur_helpers() {
  if [[ "${EUID}" -eq 0 ]]; then
    log_warn "AUR Helper 需要普通构建用户；root 模式安全跳过 paru/yay"
    mark_done "aur"
    return 0
  fi
  ensure_aur_helper || die "无法安装 paru/yay AUR Helper"
  mark_done "aur"
}

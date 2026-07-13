#!/usr/bin/env bash
# Prefer prebuilt paru/yay from archlinuxcn for both root and normal users.
# Only normal users may fall back to makepkg when the repository lacks them.

install_aur_helpers() {
  ensure_aur_helper || die "无法安装 paru/yay AUR Helper"
  mark_done "aur"
}

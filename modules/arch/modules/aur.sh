#!/usr/bin/env bash
# Prefer prebuilt paru from archlinuxcn for both root and normal users. An
# already-installed yay remains a compatible fallback but is never added as a
# second helper. Only normal users may fall back to makepkg.

install_aur_helpers() {
	ensure_aur_helper || die "无法安装 paru AUR Helper"
  mark_done "aur"
}

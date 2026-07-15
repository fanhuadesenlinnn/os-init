#!/usr/bin/env bash
# Hyprland 桌面安装后的轻量验证。

verify_hyprland() {
  log_info "验证 Hyprland 关键命令"
  run_cmd Hyprland --version || true
  run_cmd waybar --version || true
  run_cmd rofi -version || true
  run_cmd dunst --version || true
  run_cmd pacman -Q yazi || true
  run_cmd alacritty --version || true
  run_cmd foot --version || true
  run_cmd "${BROWSER_APP:-google-chrome-stable}" --version || true
  if [[ "${ENABLE_FCITX5:-0}" -eq 1 ]]; then
    run_cmd fcitx5 --version || true
    run_cmd pacman -Q fcitx5-rime || true
    if [[ "${DRY_RUN:-0}" -ne 1 ]] && ! desktop_rime_quick_verify; then
      die "Fcitx5/Rime 配置校验未通过，请运行 fcitx5-diagnose 检查当前会话"
    fi
  fi
}

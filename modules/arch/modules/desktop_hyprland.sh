#!/usr/bin/env bash
# shellcheck disable=SC1091
# Hyprland 桌面环境模块
# 负责安装 Hyprland 桌面包、按 OS Init Arch 规则安装 hyprdots 配置，并启用桌面服务。

DESKTOP_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/desktop/packages.sh
source "${DESKTOP_MODULE_DIR}/desktop/packages.sh"
# shellcheck source=modules/desktop/input_method.sh
source "${DESKTOP_MODULE_DIR}/desktop/input_method.sh"
# shellcheck source=modules/desktop/services.sh
source "${DESKTOP_MODULE_DIR}/desktop/services.sh"
# shellcheck source=modules/desktop/vm.sh
source "${DESKTOP_MODULE_DIR}/desktop/vm.sh"
# shellcheck source=modules/desktop/hyprdots.sh
source "${DESKTOP_MODULE_DIR}/desktop/hyprdots.sh"
# shellcheck source=modules/desktop/helpers.sh
source "${DESKTOP_MODULE_DIR}/desktop/helpers.sh"
# shellcheck source=modules/desktop/verify.sh
source "${DESKTOP_MODULE_DIR}/desktop/verify.sh"

install_desktop_hyprland() {
  if is_done "desktop_hyprland"; then
    log_info "Hyprland 桌面环境已处理，跳过"
    return 0
  fi

  if desktop_needs_fonts; then
    ensure_fonts
  else
    log_info "当前 Hyprland 配置不依赖字体模块，跳过字体安装"
  fi

  log_info "开始安装 Hyprland 桌面环境"
  install_hyprland_packages
  install_browser_package
  install_hyprdots_optional_packages
  install_gpu_packages_if_needed
  install_desktop_runtime_helpers
  enable_desktop_services
  enable_desktop_audio_services
  configure_rime_if_needed
  generate_hyprland_config
  configure_fcitx5_env
  backup_legacy_terminal_configs
  configure_hyprland_gpu_env
  configure_hyprland_virtualization_env
  enable_sddm_if_needed
  verify_hyprland

  mark_done "desktop_hyprland"
  log_info "Hyprland 桌面环境安装完成"
}

ensure_desktop_hyprland() {
  if ! is_done "desktop_hyprland"; then
    install_desktop_hyprland
  fi
}

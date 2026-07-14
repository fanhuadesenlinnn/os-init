#!/usr/bin/env bash
# Registry for capabilities that are genuinely Arch-specific. Cross-platform
# capabilities such as mise, Neovim, Docker, and Shell live in their
# normal OS Init modules and are composed by the Go planner.

module_key() {
  case "$1" in
    ops|ops-toolkit|ops_toolkit) echo ops_toolkit ;;
    desktop|hyprland) echo desktop_hyprland ;;
    mihomo|proxy) echo proxy ;;
    *) echo "$1" ;;
  esac
}

module_display_key() {
  case "$(module_key "$1")" in
    ops_toolkit) echo ops-toolkit ;;
    desktop_hyprland) echo desktop ;;
    proxy) echo mihomo ;;
    *) module_key "$1" ;;
  esac
}

module_desc() {
  case "$(module_key "$1")" in
    base) echo "Arch 基础环境" ;;
    aur) echo "AUR Helper" ;;
    archlinuxcn) echo "archlinuxcn 软件源" ;;
    dns) echo "系统 DNS" ;;
    git) echo "Git / GitHub CLI" ;;
    ops_toolkit) echo "Ops Toolkit" ;;
    fonts) echo "字体环境" ;;
    proxy) echo "Mihomo + MetaCubeXD 代理环境" ;;
    desktop_hyprland) echo "Hyprland 桌面环境" ;;
    *) echo "$1" ;;
  esac
}

all_modules() {
  echo "base aur archlinuxcn dns git ops_toolkit fonts proxy desktop_hyprland"
}

module_config_fingerprint() {
  local module
  module="$(module_key "$1")"
  {
    printf 'module=%s\n' "${module}"
    case "${module}" in
      base) printf 'packages=%s\n' "$(base_packages)" ;;
      aur) printf 'helpers=paru+yay\n' ;;
      archlinuxcn) printf 'server=%s\nmirrorlist=%s\n' "${ARCHLINUXCN_SERVER}" "${INSTALL_ARCHLINUXCN_MIRRORLIST:-0}" ;;
      dns) printf 'dns=%s\nfallback=%s\ndot=%s\n' "${DNS_SERVERS[*]}" "${DNS_FALLBACK_SERVERS[*]} ${DNS_FOREIGN_FALLBACK_SERVERS[*]}" "${DNS_OVER_TLS:-no}" ;;
      git) printf 'branch=main\npull_rebase=false\n' ;;
      ops_toolkit) printf 'repo=%s\nbranch=%s\ndir=%s\n' "${OPS_TOOLKIT_REPO}" "${OPS_TOOLKIT_BRANCH:-}" "${OPS_TOOLKIT_DIR}" ;;
      fonts) printf 'cn=%s\nnerd=%s\nmonaco=%s\n' "${INSTALL_CN_FONTS:-0}" "${INSTALL_NERD_FONTS:-0}" "${INSTALL_MONACO_FONT:-0}" ;;
      proxy) printf 'core=mihomo\nsource=%s\nport=%s\nui=%s\n' "${MIHOMO_CONFIG_SOURCE:-}" "${MIHOMO_MIXED_PORT:-7890}" "${ENABLE_METACUBEXD:-0}" ;;
      desktop_hyprland) printf 'gpu=%s\nmode=%s\nsddm=%s\nrime=%s\n' "${GPU_TYPE}" "${HYPRLAND_CONFIG_MODE}" "${ENABLE_SDDM:-0}" "${RIME_SCHEMA}" ;;
    esac
  } | sha256sum | awk '{print $1}'
}

module_quick_verify() {
  case "$(module_key "$1")" in
    base) need_cmd git && need_cmd curl && need_cmd rg && need_cmd tmux && [[ -f "${HOME}/.tmux.conf" ]] ;;
    aur) need_cmd paru && need_cmd yay ;;
    archlinuxcn) grep -q '^\[archlinuxcn\]' /etc/pacman.conf ;;
    dns) [[ -f /etc/systemd/resolved.conf.d/90-os-init-arch-dns.conf ]] ;;
    git) need_cmd git && need_cmd gh ;;
    ops_toolkit) [[ -d "${OPS_TOOLKIT_DIR}/.git" && -x "${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" ]] ;;
    fonts) need_cmd fc-cache ;;
    proxy) need_cmd mihomo && [[ -f "${MIHOMO_CONFIG_FILE}" ]] ;;
    desktop_hyprland) need_cmd Hyprland && [[ -d "${HOME}/.config/hypr" ]] ;;
    *) return 1 ;;
  esac
}

module_install_func() {
  case "$(module_key "$1")" in
    base) install_base ;;
    aur) install_aur_helpers ;;
    archlinuxcn) install_archlinuxcn ;;
    dns) install_dns_env ;;
    git) install_git_env ;;
    ops_toolkit) install_ops_toolkit ;;
    fonts) install_fonts ;;
    proxy) install_proxy_env ;;
    desktop_hyprland) install_desktop_hyprland ;;
    *) die "未知 Arch 模块：$1" ;;
  esac
}

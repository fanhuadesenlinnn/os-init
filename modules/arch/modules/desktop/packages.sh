#!/usr/bin/env bash
# Hyprland 桌面软件包与硬件包安装逻辑。

hyprdots_mode_enabled() {
  [[ "${HYPRLAND_CONFIG_MODE:-hyprdots}" == "hyprdots" ]]
}

validate_hyprland_config_mode() {
  case "${HYPRLAND_CONFIG_MODE:-hyprdots}" in
    hyprdots|template|skip) return 0 ;;
    *) die "未知 Hyprland 配置模式：${HYPRLAND_CONFIG_MODE}，可选值：hyprdots / template / skip" ;;
  esac
}

desktop_needs_fonts() {
  case "${HYPRLAND_CONFIG_MODE:-hyprdots}" in
    hyprdots|template) return 0 ;;
    *) [[ "${ENABLE_FCITX5:-0}" -eq 1 ]] ;;
  esac
}

desktop_needs_rime_repo() {
  [[ "${ENABLE_FCITX5:-0}" -eq 1 && "${INPUT_METHOD_ENGINE:-rime}" == "rime" && "${INSTALL_RIME_CONFIG:-1}" -eq 1 ]]
}

desktop_needs_archlinuxcn() {
  package_needs_archlinuxcn_repo "${BROWSER_PACKAGE:-google-chrome}" && return 0

  if hyprdots_mode_enabled && [[ "${INSTALL_HYPRDOTS_OBSIDIAN:-0}" -eq 1 ]]; then
    package_needs_archlinuxcn_repo obsidian && return 0
  fi

  return 1
}

detect_gpu_type() {
  local pci_info virt_type
  pci_info="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
  virt_type="$(detect_virtualization_type)"

  if grep -qi 'nvidia' <<<"${pci_info}"; then
    printf '%s\n' "nvidia"
  elif grep -qi 'vmware' <<<"${pci_info}"; then
    printf '%s\n' "vmware"
  elif [[ "${virt_type}" == "oracle" || "${virt_type}" == "virtualbox" ]] || grep -qi 'virtualbox' <<<"${pci_info}"; then
    printf '%s\n' "virtualbox"
  elif grep -qi 'virtio' <<<"${pci_info}"; then
    printf '%s\n' "virtio"
  elif grep -qi 'qxl' <<<"${pci_info}"; then
    printf '%s\n' "qxl"
  elif grep -qi 'amd|ati' <<<"${pci_info}"; then
    printf '%s\n' "amd"
  elif grep -qi 'intel' <<<"${pci_info}"; then
    printf '%s\n' "intel"
  else
    printf '%s\n' "none"
  fi
}

detect_virtualization_type() {
  local virt_type="none"

  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt_type="$(systemd-detect-virt 2>/dev/null || true)"
  fi

  [[ -n "${virt_type}" ]] || virt_type="none"
  printf '%s\n' "${virt_type}"
}

effective_gpu_type() {
  if [[ "${GPU_TYPE:-auto}" == "auto" ]]; then
    detect_gpu_type
  else
    printf '%s\n' "${GPU_TYPE}"
  fi
}

desktop_font_awesome_package() {
  printf '%s\n' "woff2-font-awesome"
}

desktop_hyprdots_packages() {
  local font_awesome_package
  font_awesome_package="$(desktop_font_awesome_package)"

  local packages=(
    brightnessctl
    btop
    cliphist
    desktop-file-utils
    dunst
    foot
    grim
    hyprland
    hyprlock
    hyprpaper
    hyprpicker
    hyprpolkitagent
    alacritty
    libnotify
    mesa
    neovide
    networkmanager
    pamixer
    pavucontrol
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    playerctl
    polkit
    qt5-wayland
    qt6-wayland
    rofi
    rtkit
    slurp
    "${font_awesome_package}"
    ttf-iosevka-nerd
    waybar
    wireplumber
    wl-clipboard
    wtype
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xdg-utils
    xorg-xwayland
    yazi
  )

  if [[ "${ENABLE_BLUETOOTH:-0}" -eq 1 ]]; then
    packages+=(bluez bluez-utils blueman)
  fi

  if [[ "${ENABLE_SDDM:-0}" -eq 1 ]]; then
    packages+=(sddm)
  fi

  printf '%s\n' "${packages[@]}"
}

desktop_template_packages() {
  local packages=(
    networkmanager
    pipewire
    wireplumber
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    mesa
    vulkan-icd-loader
    hyprland
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    qt5-wayland
    qt6-wayland
    waybar
    wofi
    alacritty
    foot
    thunar
    thunar-archive-plugin
    file-roller
    mako
    neovide
    hyprlock
    hypridle
    hyprpaper
    grim
    slurp
    wl-clipboard
    brightnessctl
    playerctl
    pavucontrol
    network-manager-applet
    polkit-kde-agent
  )

  if [[ "${ENABLE_BLUETOOTH:-0}" -eq 1 ]]; then
    packages+=(bluez bluez-utils blueman)
  fi

  if [[ "${ENABLE_SDDM:-0}" -eq 1 ]]; then
    packages+=(sddm)
  fi

  printf '%s\n' "${packages[@]}"
}

install_hyprland_packages() {
  local package packages=()

  case "${HYPRLAND_CONFIG_MODE:-hyprdots}" in
    hyprdots)
      while IFS= read -r package; do
        [[ -n "${package}" ]] && packages+=("${package}")
      done < <(desktop_hyprdots_packages)
      ;;
    template|skip)
      while IFS= read -r package; do
        [[ -n "${package}" ]] && packages+=("${package}")
      done < <(desktop_template_packages)
      ;;
    *)
      die "未知 Hyprland 配置模式：${HYPRLAND_CONFIG_MODE}"
      ;;
  esac

  log_info "安装 Hyprland 桌面软件包"
  install_packages_or_aur "${packages[@]}"

  install_input_method_packages
}

install_browser_package() {
  local package="${BROWSER_PACKAGE:-google-chrome}"
  [[ -n "${package}" ]] || die "浏览器安装包为空"

  install_package_or_aur "${package}"
}

install_hyprdots_optional_packages() {
  hyprdots_mode_enabled || return 0

  if [[ "${INSTALL_HYPRDOTS_OBSIDIAN:-0}" -eq 1 ]]; then
    log_info "安装 hyprdots 可选应用：obsidian"
    install_package_or_aur obsidian
  else
    log_info "当前配置未启用 hyprdots 可选应用：obsidian"
  fi
}

install_gpu_packages_if_needed() {
  local gpu virt_type
  gpu="$(effective_gpu_type)"
  virt_type="$(detect_virtualization_type)"

  log_info "检测到 GPU 类型：${gpu}，虚拟化环境：${virt_type}"

  case "${gpu}" in
    nvidia)
      log_warn "NVIDIA Wayland 可能需要额外配置 nvidia_drm.modeset=1"
      install_packages_or_aur nvidia nvidia-utils nvidia-settings egl-wayland vulkan-icd-loader
      ;;
    amd)
      install_packages_or_aur vulkan-radeon libva-mesa-driver mesa-vdpau vulkan-icd-loader
      ;;
    intel)
      install_packages_or_aur vulkan-intel intel-media-driver vulkan-icd-loader
      ;;
    vmware)
      log_warn "检测到 VMware 虚拟显卡；安装 VMware Tools、交互插件依赖、Mesa 检测工具和软件渲染兜底"
      install_packages_or_aur open-vm-tools gtkmm3 libxtst vulkan-swrast mesa-utils
      ;;
    virtio|qxl)
      log_warn "检测到虚拟显卡 ${gpu}；安装 QEMU/SPICE guest agent、Mesa 检测工具和软件渲染兜底"
      install_packages_or_aur qemu-guest-agent spice-vdagent vulkan-swrast mesa-utils
      ;;
    virtualbox)
      log_warn "检测到 VirtualBox 虚拟显卡；安装 VirtualBox guest utils、Mesa 检测工具和软件渲染兜底"
      install_packages_or_aur virtualbox-guest-utils vulkan-swrast mesa-utils
      ;;
    none)
      log_warn "未检测到明确 GPU 类型，跳过专用驱动包"
      ;;
    *)
      log_warn "未知 GPU 类型：${gpu}，跳过专用驱动包"
      ;;
  esac
}

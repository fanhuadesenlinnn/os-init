#!/usr/bin/env bash
# Hyprland 桌面服务启用逻辑：基础服务、虚拟机 guest、音频和 SDDM。

enable_desktop_services() {
  log_info "启用桌面基础服务"
  enable_system_service NetworkManager.service

  if [[ "${ENABLE_BLUETOOTH:-0}" -eq 1 ]]; then
    enable_system_service bluetooth.service || log_warn "蓝牙服务启用失败，可稍后手动处理"
  fi

  enable_vmware_services_if_needed
  enable_qemu_services_if_needed
  enable_virtualbox_services_if_needed
}

enable_vmware_services_if_needed() {
  [[ "$(effective_gpu_type)" == "vmware" ]] || return 0

  log_info "启用 VMware Tools 服务"
  ensure_vmware_wayland_input_support

  if systemd_system_unit_exists vmtoolsd.service; then
    enable_system_service vmtoolsd.service || \
      log_warn "vmtoolsd.service 启用失败，可稍后手动处理"
  fi

  if systemd_system_unit_exists vmware-vmblock-fuse.service; then
    enable_system_service vmware-vmblock-fuse.service || \
      log_warn "vmware-vmblock-fuse.service 启用失败，可稍后手动处理"
  fi
}

ensure_vmware_wayland_input_support() {
  [[ "$(effective_gpu_type)" == "vmware" ]] || return 0

  log_info "配置 VMware Wayland 鼠标集成所需 uinput 模块"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ modprobe uinput"
    echo "+ sudo write /etc/modules-load.d/archdevkit-vmware.conf"
    return 0
  fi

  run_sudo modprobe uinput || log_warn "uinput 模块加载失败，可稍后手动执行 sudo modprobe uinput"
  write_root_file_from_stdin /etc/modules-load.d/archdevkit-vmware.conf 0644 <<'EOF'
uinput
EOF
}

enable_qemu_services_if_needed() {
  case "$(effective_gpu_type)" in
    virtio|qxl) ;;
    *) return 0 ;;
  esac

  log_info "启用 QEMU/SPICE guest 服务"
  if systemd_system_unit_exists qemu-guest-agent.service; then
    enable_system_service qemu-guest-agent.service || \
      log_warn "qemu-guest-agent.service 启用失败，可稍后手动处理"
  fi

  if systemd_system_unit_exists spice-vdagentd.service; then
    enable_system_service spice-vdagentd.service || \
      log_warn "spice-vdagentd.service 启用失败，可稍后手动处理"
  fi
}

enable_virtualbox_services_if_needed() {
  [[ "$(effective_gpu_type)" == "virtualbox" ]] || return 0

  log_info "启用 VirtualBox guest 服务"
  if systemd_system_unit_exists vboxservice.service; then
    enable_system_service vboxservice.service || \
      log_warn "vboxservice.service 启用失败，可稍后手动处理"
  fi
}

enable_desktop_audio_services() {
  hyprdots_mode_enabled || return 0

  log_info "启用 PipeWire 用户音频服务"
  run_sudo systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || \
    log_warn "PipeWire 用户服务启用失败，可稍后手动处理"
}

enable_sddm_if_needed() {
  [[ "${ENABLE_SDDM:-0}" -eq 1 ]] || {
    log_warn "当前配置未启用 SDDM"
    return 0
  }

  if ! systemd_system_unit_exists sddm.service; then
    log_warn "未检测到 sddm.service，尝试安装 SDDM 软件包"
    install_package_or_aur sddm
    reload_systemd_system
  fi

  systemd_system_unit_exists sddm.service || \
    die "SDDM 软件包安装后仍未找到 sddm.service；请检查 sudo pacman -S sddm 的输出，或使用 --no-sddm 跳过登录管理器启用"

  log_info "启用 SDDM 登录管理器"
  enable_system_service_on_boot sddm.service || \
    die "启用 SDDM 失败；如果已有其他登录管理器占用 display-manager.service，请先禁用它后重试"
  log_warn "SDDM 已设置为开机自启，重启后在登录界面选择 Hyprland"
}

#!/usr/bin/env bash
# Hyprland 虚拟机与软件渲染配置逻辑。

virtual_gpu_3d_acceleration_available() {
  case "$(effective_gpu_type)" in
    vmware|virtio|qxl|virtualbox) ;;
    *) return 1 ;;
  esac

  local render_nodes=()
  shopt -s nullglob
  render_nodes=(/dev/dri/renderD*)
  shopt -u nullglob
  [[ "${#render_nodes[@]}" -gt 0 ]] || return 1

  if command -v eglinfo >/dev/null 2>&1; then
    local egl_output renderer_line
    egl_output="$(
      env \
        -u LIBGL_ALWAYS_SOFTWARE \
        -u MESA_LOADER_DRIVER_OVERRIDE \
        -u GALLIUM_DRIVER \
        eglinfo -B 2>/dev/null || true
    )"

    while IFS= read -r renderer_line; do
      [[ -n "${renderer_line}" ]] || continue
      grep -Eqi 'llvmpipe|softpipe|software rasterizer' <<<"${renderer_line}" && continue
      return 0
    done < <(grep -Ei 'OpenGL.*renderer|renderer:' <<<"${egl_output}" || true)
  fi

  return 1
}

vmware_force_software_renderer() {
  case "$(to_lower "${VMWARE_FORCE_SOFTWARE_RENDERER:-1}")" in
    1|true|yes|on) return 0 ;;
    0|false|no|off) return 1 ;;
    *)
      log_warn "VMWARE_FORCE_SOFTWARE_RENDERER=${VMWARE_FORCE_SOFTWARE_RENDERER} 无法识别，默认启用 VMware 软件渲染"
      return 0
      ;;
  esac
}

hyprland_needs_software_renderer() {
  case "$(effective_gpu_type)" in
    vmware)
      vmware_force_software_renderer && return 0
      virtual_gpu_3d_acceleration_available && return 1
      return 0
      ;;
    virtio|qxl|virtualbox)
      virtual_gpu_3d_acceleration_available && return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}

configure_hyprland_gpu_env() {
  local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
  local tmp_file gpu

  [[ -f "${hypr_conf}" ]] || return 0
  gpu="$(effective_gpu_type)"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    if hyprland_needs_software_renderer; then
      echo "+ enable Hyprland software renderer env for ${gpu} in ${hypr_conf}"
    else
      echo "+ remove Hyprland software renderer env for ${gpu} from ${hypr_conf}"
    fi
    return 0
  fi

  tmp_file="$(mktemp)"
  sed \
    -e '/^### OS Init Arch VM EGL fix ###$/,/^### End OS Init Arch VM EGL fix ###$/d' \
    -e '/^env = LIBGL_ALWAYS_SOFTWARE,/d' \
    -e '/^env = MESA_LOADER_DRIVER_OVERRIDE,/d' \
    -e '/^env = GALLIUM_DRIVER,/d' \
    -e '/^env = WLR_RENDERER_ALLOW_SOFTWARE,/d' \
    "${hypr_conf}" > "${tmp_file}"

  if hyprland_needs_software_renderer; then
    local with_env
    if [[ "${gpu}" == "vmware" ]] && vmware_force_software_renderer; then
      log_warn "VMware 默认使用 Hyprland llvmpipe 兜底，避免 SVGA3D 导致 Wayland GL 应用启动失败"
    else
      log_warn "未检测到可用的硬件 EGL 渲染器；为 ${gpu} 写入 Hyprland llvmpipe 兜底"
    fi
    with_env="$(mktemp)"
    {
      cat <<EOF
### OS Init Arch VM EGL fix ###
# ${gpu} virtual GPU can fail EGL initialization or native Wayland GL clients.
# Keep the desktop usable with or without virtual 3D acceleration.
env = LIBGL_ALWAYS_SOFTWARE,1
env = MESA_LOADER_DRIVER_OVERRIDE,llvmpipe
env = GALLIUM_DRIVER,llvmpipe
env = WLR_RENDERER_ALLOW_SOFTWARE,1
### End OS Init Arch VM EGL fix ###

EOF
      cat "${tmp_file}"
    } > "${with_env}"
    mv "${with_env}" "${tmp_file}"
  elif [[ "${gpu}" == "vmware" || "${gpu}" == "virtio" || "${gpu}" == "qxl" || "${gpu}" == "virtualbox" ]]; then
    log_info "检测到虚拟机可用硬件/3D 渲染；清理 Hyprland llvmpipe 兜底环境"
  fi

  install -m 0644 "${tmp_file}" "${hypr_conf}"
  rm -f "${tmp_file}"
}

configure_hyprland_virtualization_env() {
  local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
  local mode="${VM_HYPRLAND_MONITOR_MODE:-${VMWARE_HYPRLAND_MONITOR_MODE:-1920x1080@60}}"
  local tmp_file gpu
  local dynamic_resize="${VM_HYPRLAND_DYNAMIC_RESIZE:-1}"

  [[ -f "${hypr_conf}" ]] || return 0
  gpu="$(effective_gpu_type)"
  case "${gpu}" in
    vmware|virtio|qxl|virtualbox) ;;
    *) return 0 ;;
  esac

  case "$(to_lower "${dynamic_resize}")" in
    1|true|yes|on) dynamic_resize=1 ;;
    0|false|no|off) dynamic_resize=0 ;;
    *)
      log_warn "VM_HYPRLAND_DYNAMIC_RESIZE=${dynamic_resize} 无法识别，默认启用动态分辨率"
      dynamic_resize=1
      ;;
  esac

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    if [[ "${dynamic_resize}" -eq 1 ]]; then
      echo "+ keep VM Hyprland monitor dynamic in ${hypr_conf}"
    else
      echo "+ set VM Hyprland monitor fallback ${mode} in ${hypr_conf}"
    fi
    echo "+ enable VM guest agent autostart for ${gpu} in ${hypr_conf}"
    echo "+ apply low-latency Hyprland overrides for ${gpu} in ${hypr_conf}"
    return 0
  fi

  tmp_file="$(mktemp)"
  sed \
    -e '/^### OS Init Arch VM integration ###$/,/^### End OS Init Arch VM integration ###$/d' \
    -e '/^exec-once = vmware-user-suid-wrapper$/d' \
    -e '/^exec-once = .*os-init-arch-vmware-user$/d' \
    -e '/^exec-once = spice-vdagent$/d' \
    -e '/^exec-once = VBoxClient-all$/d' \
    "${hypr_conf}" > "${tmp_file}"

  local monitor_file
  monitor_file="$(mktemp)"
  if [[ "${dynamic_resize}" -eq 1 ]]; then
    sed \
      -e 's/^monitor[[:space:]]*=[[:space:]]*,.*$/monitor=,preferred,auto,1/' \
      -e 's/^monitor[[:space:]]*=[[:space:]]*Virtual-1,.*$/monitor=,preferred,auto,1/' \
      "${tmp_file}" > "${monitor_file}"
  else
    sed \
      -e 's/^monitor[[:space:]]*=[[:space:]]*,preferred,auto,\(auto\|1\)[[:space:]]*$/monitor=,'"${mode}"',auto,1/' \
      -e 's/^monitor[[:space:]]*=[[:space:]]*Virtual-1,.*/monitor=,'"${mode}"',auto,1/' \
      "${tmp_file}" > "${monitor_file}"
  fi
  mv "${monitor_file}" "${tmp_file}"

  if [[ "${dynamic_resize}" -eq 1 ]]; then
    if ! grep -Eq '^monitor[[:space:]]*=[[:space:]]*,preferred,auto,1[[:space:]]*$' "${tmp_file}"; then
      monitor_file="$(mktemp)"
      {
        printf 'monitor=,preferred,auto,1\n'
        cat "${tmp_file}"
      } > "${monitor_file}"
      mv "${monitor_file}" "${tmp_file}"
    fi
  else
    if ! grep -Eq '^monitor[[:space:]]*=[[:space:]]*,'"${mode//./\\.}"',' "${tmp_file}"; then
      monitor_file="$(mktemp)"
      {
        printf 'monitor=,%s,auto,1\n' "${mode}"
        cat "${tmp_file}"
      } > "${monitor_file}"
      mv "${monitor_file}" "${tmp_file}"
    fi
  fi

  {
    printf '\n### OS Init Arch VM integration ###\n'
    case "${gpu}" in
      vmware)
        printf '# VMware mouse/clipboard and dynamic resize for Wayland sessions.\n'
        printf 'exec-once = %s/.local/bin/os-init-arch-vmware-user\n' "${HOME}"
        ;;
      virtio|qxl)
        printf 'exec-once = spice-vdagent\n'
        ;;
      virtualbox)
        printf 'exec-once = VBoxClient-all\n'
        ;;
    esac
    if [[ "${VM_HYPRLAND_LOW_LATENCY:-1}" -eq 1 ]]; then
      cat <<'EOF'
animations {
    enabled = false
}

decoration {
    shadow {
        enabled = false
    }
    blur {
        enabled = false
    }
}

input {
    sensitivity = 0
    force_no_accel = false
}
EOF
    fi
    printf '### End OS Init Arch VM integration ###\n'
  } >> "${tmp_file}"

  install -m 0644 "${tmp_file}" "${hypr_conf}"
  rm -f "${tmp_file}"
}

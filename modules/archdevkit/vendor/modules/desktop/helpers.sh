#!/usr/bin/env bash
# 桌面会话运行时辅助脚本安装能力。

install_desktop_runtime_helpers() {
  install_terminal_helper
  install_neovide_helper
  install_vmware_user_helper_if_needed
}

install_terminal_helper() {
  local helper="${HOME}/.local/bin/archdevkit-terminal"

  log_info "安装桌面运行时辅助脚本：${helper}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${helper}"
    return 0
  fi

  mkdir -p "$(dirname "${helper}")"
  cat > "${helper}" <<'EOF'
#!/usr/bin/env bash
set -u

log_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/archdevkit"
log_file="${log_dir}/terminal.log"
mkdir -p "${log_dir}"

try_terminal() {
  local terminal="$1"
  shift

  command -v "${terminal}" >/dev/null 2>&1 || return 1
  {
    printf '[%s] trying %s\n' "$(date '+%F %T')" "${terminal}"
    "${terminal}" "$@"
  } >>"${log_file}" 2>&1 && exit 0
  printf '[%s] %s exited with status %s\n' "$(date '+%F %T')" "${terminal}" "$?" >>"${log_file}"
  return 1
}

try_terminal alacritty "$@"
try_terminal foot "$@"

notify-send "Terminal unavailable" "Install alacritty or foot." 2>/dev/null || true
exit 127
EOF
  chmod +x "${helper}"
}

install_neovide_helper() {
  local helper="${HOME}/.local/bin/neovide"

  log_info "安装 Neovide 启动包装脚本：${helper}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${helper}"
    return 0
  fi

  mkdir -p "$(dirname "${helper}")"
  cat > "${helper}" <<'EOF'
#!/usr/bin/env bash
set -u

log_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/archdevkit"
log_file="${log_dir}/neovide.log"
mkdir -p "${log_dir}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"${log_file}"
}

find_real_neovide() {
  local candidate resolved self
  self="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s\n' "${BASH_SOURCE[0]}")"

  if [[ -n "${NEOVIDE_BIN:-}" ]]; then
    if [[ -x "${NEOVIDE_BIN}" ]]; then
      printf '%s\n' "${NEOVIDE_BIN}"
      return 0
    fi
    printf 'NEOVIDE_BIN is not executable: %s\n' "${NEOVIDE_BIN}" >&2
    return 1
  fi

  while IFS= read -r candidate; do
    [[ -x "${candidate}" ]] || continue
    resolved="$(realpath "${candidate}" 2>/dev/null || printf '%s\n' "${candidate}")"
    [[ "${resolved}" == "${self}" ]] && continue
    printf '%s\n' "${candidate}"
    return 0
  done < <(type -a -p neovide 2>/dev/null)

  for candidate in /usr/bin/neovide /usr/local/bin/neovide "${HOME}/.cargo/bin/neovide"; do
    [[ -x "${candidate}" ]] || continue
    resolved="$(realpath "${candidate}" 2>/dev/null || printf '%s\n' "${candidate}")"
    [[ "${resolved}" == "${self}" ]] && continue
    printf '%s\n' "${candidate}"
    return 0
  done

  return 1
}

ensure_graphical_display() {
  local runtime_dir socket

  [[ -n "${WAYLAND_DISPLAY:-}" || -n "${WAYLAND_SOCKET:-}" || -n "${DISPLAY:-}" ]] && return 0

  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [[ -d "${runtime_dir}" ]] || return 1

  for socket in "${runtime_dir}"/wayland-*; do
    [[ -S "${socket}" ]] || continue
    export XDG_RUNTIME_DIR="${runtime_dir}"
    export WAYLAND_DISPLAY="$(basename "${socket}")"
    log "filled WAYLAND_DISPLAY=${WAYLAND_DISPLAY} from ${socket}"
    return 0
  done

  return 1
}

if ! ensure_graphical_display; then
  log "refused to start without WAYLAND_DISPLAY, WAYLAND_SOCKET or DISPLAY"
  cat >&2 <<'MESSAGE'
Neovide needs a graphical session, but this shell has no WAYLAND_DISPLAY, WAYLAND_SOCKET or DISPLAY.
Start Hyprland first (from TTY: Hyprland; from SDDM: select Hyprland and log in), then run neovide again.
If you are staying in TTY or SSH, use: nvim
MESSAGE
  exit 1
fi

neovide_bin="$(find_real_neovide)" || {
  log "real neovide binary not found"
  printf 'Neovide is not installed. Re-run: bash install.sh desktop\n' >&2
  exit 127
}

log "starting ${neovide_bin}"
exec "${neovide_bin}" "$@"
EOF
  chmod +x "${helper}"
}

install_vmware_user_helper_if_needed() {
  [[ "$(effective_gpu_type)" == "vmware" ]] || return 0

  local helper="${HOME}/.local/bin/archdevkit-vmware-user"
  log_info "安装 VMware Wayland 会话辅助脚本：${helper}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${helper}"
    return 0
  fi

  mkdir -p "$(dirname "${helper}")"
  cat > "${helper}" <<'EOF'
#!/usr/bin/env bash
set -u

log_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/archdevkit"
log_file="${log_dir}/vmware-user.log"
mkdir -p "${log_dir}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"${log_file}"
}

if pgrep -u "$(id -u)" -f '(^|[[:space:]/])vmtoolsd([[:space:]].*)?vmusr|(^|[[:space:]/])vmware-user-suid-wrapper([[:space:]]|$)|(^|[[:space:]/])vmware-user([[:space:]]|$)' >/dev/null 2>&1; then
  log "vmware user process already running"
  exit 0
fi

if ! command -v vmware-user-suid-wrapper >/dev/null 2>&1; then
  log "vmware-user-suid-wrapper not found"
  exit 0
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
wayland_display="${WAYLAND_DISPLAY:-}"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -n "${wayland_display}" && -S "${runtime_dir}/${wayland_display}" ]]; then
    break
  fi
  for socket in "${runtime_dir}"/wayland-*; do
    [[ -S "${socket}" ]] || continue
    wayland_display="$(basename "${socket}")"
    break
  done
  [[ -n "${wayland_display}" && -S "${runtime_dir}/${wayland_display}" ]] && break
  sleep 0.2
done

wayland_display="${wayland_display:-wayland-1}"

export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-${wayland_display}}"

log "starting vmware-user-suid-wrapper with WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
exec vmware-user-suid-wrapper
EOF
  chmod +x "${helper}"
}

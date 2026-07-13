#!/usr/bin/env bash
# 软件包安装公共操作：pacman、archlinuxcn 兜底、AUR helper 和 makepkg 回退。

pacman_update() {
  require_arch
  log_info "刷新并更新系统软件包"
  run_sudo pacman -Syu --noconfirm
}

pacman_install() {
  require_arch
  [[ "$#" -eq 0 ]] && return 0
  log_info "安装软件包：$*"
  run_sudo pacman -S --needed --noconfirm "$@"
}

dedupe_list() {
  local item seen=" "
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    case "${seen}" in
      *" ${item} "*) ;;
      *)
        printf '%s\n' "${item}"
        seen="${seen}${item} "
        ;;
    esac
  done
}

pacman_package_available() {
  local package="$1"
  pacman -Si "${package}" >/dev/null 2>&1
}

pacman_package_installed() {
  local package="$1"
  pacman -Q "${package}" >/dev/null 2>&1
}

package_needs_archlinuxcn_repo() {
  local package="$1"
  [[ -n "${package}" ]] || die "软件包名为空"
  [[ "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]] || return 1
  need_cmd pacman || return 1
  pacman_package_installed "${package}" && return 1
  pacman_package_available "${package}" && return 1
  return 0
}

ensure_archlinuxcn_for_package() {
  local package="$1"
  [[ -n "${package}" ]] || die "软件包名为空"
  package_needs_archlinuxcn_repo "${package}" || return 1

  log_info "当前 pacman 源未提供 ${package}，优先尝试启用 archlinuxcn 源"
  ensure_archlinuxcn
  pacman_package_available "${package}"
}

ensure_command_package() {
  local command_name="$1" package="$2"
  [[ -n "${command_name}" ]] || die "命令名为空"
  [[ -n "${package}" ]] || die "软件包名为空"

  if need_cmd "${command_name}"; then
    return 0
  fi

  log_info "安装命令依赖：${command_name}（${package}）"
  pacman_install "${package}"
}

ensure_git_command() {
  ensure_command_package git git
}

ensure_curl_command() {
  ensure_command_package curl curl
}

ensure_aur_build_tools() {
  if is_done "aur_build_tools"; then
    return 0
  fi

  log_info "确保 AUR 构建依赖：base-devel git"
  pacman_install base-devel git
  require_cmd git
  require_cmd makepkg
  mark_done "aur_build_tools"
}

aur_helper_command() {
  if need_cmd paru; then
    printf '%s' "paru"
    return 0
  fi
  if need_cmd yay; then
    printf '%s' "yay"
    return 0
  fi
  return 1
}

install_package_with_current_aur_helper() {
  local package="$1" helper
  [[ -n "${package}" ]] || die "AUR 包名为空"
  helper="$(aur_helper_command)" || return 1

  log_info "通过 ${helper} 安装软件包：${package}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ ${helper} -S --needed --noconfirm ${package}"
    return 0
  fi

  "${helper}" -S --needed --noconfirm "${package}"
}

install_aur_package_via_makepkg() {
  local package="$1" aur_url tmp_dir package_dir
  [[ -n "${package}" ]] || die "AUR 包名为空"

  ensure_aur_build_tools

  aur_url="https://aur.archlinux.org/${package}.git"
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/os-init-arch-aur-${package}.XXXXXX")"
  package_dir="${tmp_dir}/${package}"

  log_info "从 AUR 安装：${package}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ git clone ${aur_url} ${package_dir}"
    echo "+ cd ${package_dir} && makepkg -si --needed --noconfirm"
    rmdir "${tmp_dir}"
    return 0
  fi

  git clone "${aur_url}" "${package_dir}" || {
    rm -rf "${tmp_dir}"
    die "克隆 AUR 仓库失败：${aur_url}"
  }

  (cd "${package_dir}" && makepkg -si --needed --noconfirm) || {
    rm -rf "${tmp_dir}"
    die "AUR 包安装失败：${package}"
  }

  rm -rf "${tmp_dir}"
}

ensure_preferred_paru_helper() {
  need_cmd paru && return 0

  if install_package_from_pacman_prefer_archlinuxcn paru; then
    return 0
  fi
  if install_package_with_current_aur_helper paru; then
    return 0
  fi
  install_aur_package_via_makepkg paru
}

ensure_companion_yay_helper() {
  need_cmd yay && return 0

  log_info "同时安装 yay，供后续手动使用"
  if install_package_from_pacman_prefer_archlinuxcn yay; then
    return 0
  fi
  if install_package_with_current_aur_helper yay; then
    return 0
  fi

  log_warn "yay 安装失败；安装器内部仍会优先使用 paru"
  return 1
}

ensure_aur_helper() {
  local helper

  if [[ "${EUID}" -eq 0 ]]; then
    log_warn "root 模式不能运行 makepkg，跳过 AUR Helper"
    return 1
  fi

  if need_cmd paru; then
    ensure_companion_yay_helper || true
    helper="$(aur_helper_command)"
    log_info "AUR 助手已就绪：${helper}"
    return 0
  fi
  if need_cmd yay; then
    log_info "检测到 yay，尝试补装优先使用的 paru"
    if ensure_preferred_paru_helper; then
      helper="$(aur_helper_command)"
      log_info "AUR 助手已就绪：${helper}"
      return 0
    fi
    log_warn "paru 安装失败，暂时使用已有 yay"
    return 0
  fi

  log_info "未检测到 AUR 助手（paru/yay），开始准备基础 AUR 助手"

  if ensure_preferred_paru_helper; then
    helper="paru"
    ensure_companion_yay_helper || true
  elif install_package_from_pacman_prefer_archlinuxcn yay; then
    helper="yay"
  else
    log_warn "当前 pacman / archlinuxcn 源未提供 paru/yay，尝试从 AUR 引导安装 yay"
    install_aur_package_via_makepkg yay || return 1
    helper="yay"
  fi

  if helper="$(aur_helper_command)"; then
    log_info "AUR 助手已就绪：${helper}"
    return 0
  fi

  return 1
}

install_aur_package() {
  local package="$1" helper
  [[ -n "${package}" ]] || die "AUR 包名为空"

  if ensure_aur_helper; then
    helper="$(aur_helper_command || true)"
    install_package_with_current_aur_helper "${package}" && return 0
    log_warn "${helper} 安装失败，回退到 makepkg：${package}"
  fi

  install_aur_package_via_makepkg "${package}"
}

install_package_or_aur() {
  [[ "$#" -gt 0 ]] || return 0
  install_packages_or_aur "$@"
}

install_packages_or_aur() {
  local package
  local pacman_packages=()
  local missing_packages=()
  local aur_packages=()

  require_arch
  for package in "$@"; do
    [[ -n "${package}" ]] || die "软件包名为空"
  done

  while IFS= read -r package; do
    if pacman_package_installed "${package}"; then
      log_info "软件包已安装：${package}"
    elif pacman_package_available "${package}"; then
      pacman_packages+=("${package}")
    else
      missing_packages+=("${package}")
    fi
  done < <(dedupe_list "$@")

  if [[ "${#missing_packages[@]}" -gt 0 && "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]]; then
    log_info "当前 pacman 源缺少软件包：${missing_packages[*]}，尝试启用 archlinuxcn 后重试"
    ensure_archlinuxcn

    local retry_missing=()
    for package in "${missing_packages[@]}"; do
      if pacman_package_installed "${package}"; then
        log_info "软件包已安装：${package}"
      elif pacman_package_available "${package}"; then
        pacman_packages+=("${package}")
      else
        retry_missing+=("${package}")
      fi
    done
    missing_packages=("${retry_missing[@]}")
  fi

  if [[ "${#pacman_packages[@]}" -gt 0 ]]; then
    pacman_install "${pacman_packages[@]}"
  fi

  if [[ "${#missing_packages[@]}" -gt 0 ]]; then
    if [[ "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]]; then
      log_warn "当前 pacman / archlinuxcn 源仍未提供软件包：${missing_packages[*]}，最后尝试通过 yay/paru 安装"
    else
      log_warn "当前 pacman 源未提供软件包：${missing_packages[*]}，且未启用 archlinuxcn，最后尝试通过 yay/paru 安装"
    fi

    if [[ "${EUID}" -eq 0 ]]; then
      log_warn "root 模式不能构建 AUR 包，已跳过：${missing_packages[*]}"
      return 0
    fi

    for package in "${missing_packages[@]}"; do
      install_aur_package "${package}"
      aur_packages+=("${package}")
    done

    [[ "${#aur_packages[@]}" -eq "${#missing_packages[@]}" ]] || \
      die "部分 AUR 软件包安装失败：${missing_packages[*]}"
  fi
}

install_package_from_pacman_prefer_archlinuxcn() {
  local package="$1"
  [[ -n "${package}" ]] || die "软件包名为空"

  if pacman_package_installed "${package}"; then
    log_info "软件包已安装：${package}"
    return 0
  fi

  if pacman_package_available "${package}"; then
    pacman_install "${package}"
    return 0
  fi

  if ensure_archlinuxcn_for_package "${package}"; then
    log_info "archlinuxcn 源已提供软件包：${package}"
    pacman_install "${package}"
    return 0
  fi

  return 1
}

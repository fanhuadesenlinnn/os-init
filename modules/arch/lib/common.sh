#!/usr/bin/env bash
# 公共函数库：日志、确认、备份、命令执行、GitHub 代理、模块执行标记。

ARCH_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=modules/lib/github_proxy.sh
source "${ARCH_COMMON_DIR}/../../lib/github_proxy.sh"

MODULE_DONE_LIST=""

log_info()  { printf '\033[32m----> %s\033[0m\n' "$*"; }
log_warn()  { printf '\033[33m----> %s\033[0m\n' "$*"; }
log_error() { printf '\033[31m----> %s\033[0m\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }
require_cmd() { need_cmd "$1" || die "缺少命令：$1"; }
require_arch() {
  if [[ -f /etc/arch-release ]] && need_cmd pacman; then
    return 0
  fi
  die "当前脚本只支持 Arch Linux / Arch 系发行版"
}
require_normal_user() { [[ "${EUID}" -ne 0 ]] || die "请使用普通用户执行脚本，不要直接使用 root 或 sudo 执行"; }

is_orbstack_environment() {
  [[ "${OS_INIT_TARGET_ENVIRONMENT:-}" == "orbstack" ]] && return 0
  grep -qi 'orbstack' /proc/sys/kernel/osrelease 2>/dev/null
}

is_container_environment() {
  [[ "${OS_INIT_TARGET_ENVIRONMENT:-}" == "container" ]] && return 0
  [[ -e /.dockerenv || -e /run/.containerenv ]] && return 0
  grep -Eqi '(docker|containerd|kubepods|libpod|podman|lxc)' /proc/1/cgroup 2>/dev/null
}

require_host_safe_arch_target() {
  if is_container_environment && [[ "${OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER:-0}" != "1" ]]; then
    die "检测到通用容器环境；已拒绝 Arch 系统操作，以免修改宿主挂载或宿主 systemd。核对边界后可显式设置 OS_INIT_ALLOW_HOST_INTEGRATED_CONTAINER=1"
  fi
}

arch_normalize_absolute_path() {
  local input="$1" component index
  local -a parts=() normalized=()
  [[ -n "$input" && "$input" == /* && "$input" != *$'\n'* && "$input" != *$'\r'* ]] || die "路径必须是不含换行的绝对路径: $input"
  IFS='/' read -r -a parts <<< "$input"
  for component in "${parts[@]}"; do
    case "$component" in
      ''|.) ;;
      ..)
        ((${#normalized[@]} > 0)) || die "路径不能越过根目录: $input"
        index=$((${#normalized[@]} - 1)); unset 'normalized[index]'
        ;;
      *) normalized+=("$component") ;;
    esac
  done
  ((${#normalized[@]} > 0)) || { printf '/\n'; return; }
  printf '/%s' "${normalized[0]}"
  for ((index = 1; index < ${#normalized[@]}; index++)); do printf '/%s' "${normalized[index]}"; done
  printf '\n'
}

arch_require_path_within() {
  local target="$1" allowed_root="$2" label="$3" normalized_target normalized_root
  normalized_target="$(arch_normalize_absolute_path "$target")" || return 1
  normalized_root="$(arch_normalize_absolute_path "$allowed_root")" || return 1
  case "$normalized_target" in
    "$normalized_root"|"$normalized_root"/*) printf '%s\n' "$normalized_target" ;;
    *) die "$label 必须位于 $normalized_root 内: $target" ;;
  esac
}

bool_text() {
  case "${1:-0}" in
    1|true|yes|on) printf "启用" ;;
    0|false|no|off) printf "关闭" ;;
    *) printf "%s" "$1" ;;
  esac
}

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
pause() { read -r -p "按回车键继续..." _; }

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//\//\\/}"
  printf '%s' "${value}"
}

mark_done() {
  local module="$1" module_done
  for module_done in ${MODULE_DONE_LIST}; do
    [[ "${module_done}" == "${module}" ]] && return 0
  done
  MODULE_DONE_LIST="${MODULE_DONE_LIST} ${module}"
}

is_done() {
  local module="$1" module_done
  for module_done in ${MODULE_DONE_LIST}; do
    [[ "${module_done}" == "${module}" ]] && return 0
  done
  return 1
}

run_cmd() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf '+'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

run_sudo() {
  if [[ "${EUID}" -eq 0 ]]; then run_cmd "$@"; else run_cmd sudo "$@"; fi
}

backup_path() {
  local path="$1"
  [[ -n "${path}" ]] || die "备份路径为空"
  [[ -e "${path}" || -L "${path}" ]] || return 0
  local bak
  bak="${path}.bak.$(date +%Y%m%d-%H%M%S)"
  mv "${path}" "${bak}"
  log_warn "已备份：${path} -> ${bak}"
}

backup_file_root() {
  local file="$1"
  [[ -n "${file}" ]] || die "备份文件路径为空"
  [[ -e "${file}" ]] || return 0
  local bak
  bak="${file}.bak.$(date +%Y%m%d-%H%M%S)"
  run_sudo cp -a "${file}" "${bak}"
  log_warn "已备份：${file} -> ${bak}"
}

append_unique_line() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "${file}")"
  touch "${file}"
  grep -Fqx -- "${line}" "${file}" || echo "${line}" >> "${file}"
}

ask_value() {
  local prompt="$1" default_value="$2" input
  read -r -p "${prompt} [${default_value}]: " input
  printf '%s' "${input:-${default_value}}"
}

confirm_yes() {
  local prompt="$1" input
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
  read -r -p "${prompt} [Y/n]: " input
  input="$(to_lower "${input:-yes}")"
  case "${input}" in y|yes) return 0 ;; n|no) return 1 ;; *) log_warn "请输入 y/yes 或 n/no"; confirm_yes "${prompt}" ;; esac
}

confirm_no() {
  local prompt="$1" input
  [[ "${ASSUME_YES:-0}" -eq 1 ]] && return 0
  read -r -p "${prompt} [y/N]: " input
  input="$(to_lower "${input:-no}")"
  case "${input}" in y|yes) return 0 ;; n|no) return 1 ;; *) log_warn "请输入 y/yes 或 n/no"; confirm_no "${prompt}" ;; esac
}

github_proxy_url() {
  rewrite_github_url "$1"
}

run_with_github_proxy() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    [[ -n "${GITHUB_PROXY:-}" ]] && log_info "dry-run：GitHub Git 命令将使用临时代理：${GITHUB_PROXY}"
    printf '+'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  run_with_github_git_proxy "$@"
}

clone_repo_safe() {
  local repo_url="$1" target_dir="$2" branch="${3:-}" actual_url tmp_dir
  [[ -n "${repo_url}" ]] || die "仓库地址为空"
  [[ -n "${target_dir}" ]] || die "目标目录为空"
  ensure_git_command
  actual_url="$(github_proxy_url "${repo_url}")"
  tmp_dir="$(mktemp -d)"
  log_info "准备克隆仓库：${repo_url}"
  [[ "${repo_url}" != "${actual_url}" ]] && log_info "实际下载地址：${actual_url}"
  local args=(clone --depth=1)
  [[ -n "${branch}" ]] && args+=(-b "${branch}")
  args+=("${actual_url}" "${tmp_dir}/repo")
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf '+ git'; printf ' %q' "${args[@]}"; printf '\n'; rm -rf "${tmp_dir}"; return 0
  fi
  git "${args[@]}" || { rm -rf "${tmp_dir}"; die "克隆仓库失败：${repo_url}"; }
  [[ "${repo_url}" == "${actual_url}" ]] || git -C "${tmp_dir}/repo" remote set-url origin "${repo_url}"
  mkdir -p "$(dirname "${target_dir}")"
  backup_path "${target_dir}"
  mv "${tmp_dir}/repo" "${target_dir}"
  rm -rf "${tmp_dir}"
  log_info "仓库已安装到：${target_dir}"
}

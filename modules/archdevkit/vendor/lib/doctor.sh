#!/usr/bin/env bash
# Doctor 诊断：集中维护安装前环境检查和 JSON/text 输出。

DOCTOR_JSON_ITEMS=()

doctor_check() {
  local name="$1" status="$2" detail="$3"
  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    DOCTOR_JSON_ITEMS+=("${name}|${status}|${detail}")
  else
    printf "%-18s %-8s %s\n" "${name}" "${status}" "${detail}"
  fi
}

resolve_host() {
  local host="$1"
  if need_cmd getent; then
    getent hosts "${host}" >/dev/null 2>&1
  elif need_cmd dig; then
    dig +short "${host}" >/dev/null 2>&1
  elif need_cmd host; then
    host "${host}" >/dev/null 2>&1
  else
    return 1
  fi
}

doctor_check_command() {
  local command_name="$1" level="${2:-fail}" desc="${3:-}"
  if need_cmd "${command_name}"; then
    doctor_check "${command_name}" "ok" "${desc:-${command_name} 可用}"
  else
    doctor_check "${command_name}" "${level}" "缺少 ${command_name}"
  fi
}

doctor_check_state_dir() {
  local dir parent
  dir="$(state_root)"
  parent="$(dirname "${dir}")"
  if [[ -d "${dir}" && -w "${dir}" ]]; then
    doctor_check "state" "ok" "${dir} 可写"
  elif [[ -d "${dir}" ]]; then
    doctor_check "state" "warn" "${dir} 存在但当前用户不可写"
  elif [[ -d "${parent}" && -w "${parent}" ]]; then
    doctor_check "state" "ok" "状态目录尚未创建，父目录可写：${parent}"
  else
    doctor_check "state" "warn" "状态目录尚未创建，且父目录不可写或不存在：${dir}"
  fi
}

doctor_check_config_file() {
  local config_file
  config_file="${ARCHDEVKIT_CONFIG_FILE:-${HOME}/.config/archdevkit/config.env}"
  if [[ "${ARCHDEVKIT_LOAD_CONFIG_FILE:-1}" -ne 1 ]]; then
    doctor_check "config-file" "ok" "用户配置文件加载已关闭"
  elif [[ "${CONFIG_FILE_LOADED:-0}" -eq 1 ]]; then
    doctor_check "config-file" "ok" "已加载 ${config_file}"
  else
    doctor_check "config-file" "ok" "未发现用户配置文件，使用默认值：${config_file}"
  fi
}

doctor_check_config_warnings() {
  local count
  count="${#CONFIG_WARNINGS[@]}"
  if [[ "${count}" -eq 0 ]]; then
    doctor_check "config" "ok" "配置校验通过"
  else
    doctor_check "config" "warn" "存在 ${count} 条配置提示，plan/config 会显示详情"
  fi
}

doctor_check_network_host() {
  local host="$1" label="$2"
  if resolve_host "${host}"; then
    doctor_check "${label}" "ok" "${host} 可解析"
  else
    doctor_check "${label}" "warn" "${host} 解析失败或网络不可用"
  fi
}

doctor_check_pacman_lock() {
  local lock_file="/var/lib/pacman/db.lck"
  if [[ -e "${lock_file}" ]]; then
    doctor_check "pacman-lock" "warn" "检测到 ${lock_file}，请确认没有 pacman 正在运行"
  else
    doctor_check "pacman-lock" "ok" "未检测到 pacman 数据库锁"
  fi
}

doctor_check_display_manager() {
  local link target
  link="/etc/systemd/system/display-manager.service"
  if [[ ! -e "${link}" && ! -L "${link}" ]]; then
    doctor_check "display-manager" "ok" "未检测到已绑定的 display-manager.service"
    return 0
  fi

  target="$(readlink "${link}" 2>/dev/null || printf "%s" "${link}")"
  if [[ "${ENABLE_SDDM:-0}" -eq 1 && "${target}" == *sddm* ]]; then
    doctor_check "display-manager" "ok" "display-manager 已指向 SDDM"
  elif [[ "${ENABLE_SDDM:-0}" -eq 1 ]]; then
    doctor_check "display-manager" "warn" "display-manager 当前不是 SDDM：${target}"
  else
    doctor_check "display-manager" "ok" "当前配置不启用 SDDM，已有 display-manager：${target}"
  fi
}

doctor_check_mihomo_config() {
  local config_file="${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
  [[ "${PROXY_CORE:-mihomo}" == "mihomo" ]] || return 0

  if need_cmd mihomo; then
    doctor_check "mihomo-bin" "ok" "mihomo 命令可用"
  else
    doctor_check "mihomo-bin" "warn" "mihomo 尚未安装；安装 proxy 模块时会处理"
  fi

  if [[ -f "${config_file}" ]]; then
    doctor_check "mihomo-config" "ok" "已发现 ${config_file}"
  else
    doctor_check "mihomo-config" "ok" "未发现已安装配置，proxy 模块会写入：${config_file}"
  fi
}

doctor_check_base_tools_json() {
  local name command_name command_path

  while IFS=: read -r name command_name; do
    [[ -n "${name}" ]] || continue
    if command_path="$(command -v "${command_name}" 2>/dev/null)"; then
      doctor_check "tool:${name}" "ok" "${command_name} -> ${command_path}"
    else
      doctor_check "tool:${name}" "warn" "缺少命令：${command_name}"
    fi
  done < <(base_tool_commands)
}

show_doctor() {
  DOCTOR_JSON_ITEMS=()
  if [[ "${OUTPUT_JSON:-0}" -ne 1 ]]; then
    echo "----------------------------------------------------------"
    echo "[ArchDevKit 环境检查]"
  fi

  if [[ -f /etc/arch-release ]]; then
    doctor_check "arch" "ok" "检测到 Arch Linux"
  else
    doctor_check "arch" "warn" "未检测到 /etc/arch-release"
  fi
  doctor_check_command sudo fail "sudo 可用"
  doctor_check_command pacman fail "pacman 可用"
  doctor_check_command systemctl warn "systemctl 可用"
  doctor_check_command git warn "git 可用"
  doctor_check_command curl warn "curl 可用"
  doctor_check_command bash fail "bash 可用"
  doctor_check_command ruby warn "ruby 可用，scripts/test.sh 需要"
  doctor_check_command sha256sum fail "模块状态指纹需要 sha256sum"
  doctor_check_pacman_lock
  doctor_check_network_host github.com "github"
  doctor_check_network_host raw.githubusercontent.com "github-raw"
  doctor_check_network_host aur.archlinux.org "aur"
  if [[ "${ENABLE_GITHUB_PROXY:-0}" -eq 1 && -n "${GITHUB_PROXY:-}" ]]; then
    doctor_check_network_host "$(printf "%s" "${GITHUB_PROXY}" | sed -E 's#^https?://##;s#/.*$##;s#:.*$##')" "github-proxy"
  fi
  doctor_check_state_dir
  doctor_check_config_file
  doctor_check_config_warnings

  if [[ "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}" == "0.0.0.0" && -z "${MIHOMO_SECRET:-}" ]]; then
    doctor_check "mihomo-secret" "warn" "控制接口开放到 0.0.0.0 且 secret 为空"
  else
    doctor_check "mihomo-secret" "ok" "控制接口配置正常"
  fi
  doctor_check_display_manager
  doctor_check_mihomo_config
  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    doctor_check_base_tools_json
  fi

  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    local item first=1 name status detail
    printf '{'
    json_metadata_fields "doctor"; printf ','
    printf '"warnings":'; json_warnings_array; printf ','
    printf '"checks":['
    for item in "${DOCTOR_JSON_ITEMS[@]}"; do
      IFS='|' read -r name status detail <<<"${item}"
      [[ "${first}" -eq 1 ]] || printf ','
      first=0
      printf '{"name":'; json_string "${name}"
      printf ',"status":'; json_string "${status}"
      printf ',"detail":'; json_string "${detail}"
      printf '}'
    done
    printf ']}\n'
  else
    show_config_warnings_text
    echo
    show_base_tool_status_table
    echo "----------------------------------------------------------"
  fi
}

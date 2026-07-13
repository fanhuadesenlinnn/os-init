#!/usr/bin/env bash
# 失败恢复提示：安装中断时给出模块、日志和可复制的重试命令。

: "${INSTALL_RECOVERY_ACTIVE:=0}"
: "${INSTALL_PHASE:=}"
: "${CURRENT_MODULE:=}"
: "${CURRENT_MODULE_DISPLAY:=}"
: "${CURRENT_MODULE_INDEX:=0}"
: "${CURRENT_MODULE_TOTAL:=0}"

quote_cmd() {
  local arg first=1
  for arg in "$@"; do
    [[ "${first}" -eq 1 ]] || printf ' '
    first=0
    printf '%q' "${arg}"
  done
}

install_target_command() {
  quote_cmd bash install.sh install "${TARGET:-workstation}" --yes
}

install_failed_module_command() {
  [[ -n "${CURRENT_MODULE_DISPLAY:-}" ]] || return 1
  quote_cmd bash install.sh install "${CURRENT_MODULE_DISPLAY}" --force --yes
}

reset_failed_state_command() {
  if [[ -n "${CURRENT_MODULE_DISPLAY:-}" ]]; then
    quote_cmd bash install.sh reset-state "${CURRENT_MODULE_DISPLAY}"
  else
    quote_cmd bash install.sh reset-state "${TARGET:-all}"
  fi
}

show_install_failure_recovery() {
  local status="$1" line_no="${2:-unknown}" command_text="${3:-unknown}"
  echo
  echo "----------------------------------------------------------"
  echo "[安装中断]"
  echo "目标: ${TARGET:-unknown}"
  if [[ -n "${CURRENT_MODULE:-}" ]]; then
    echo "失败模块: ${CURRENT_MODULE_DISPLAY:-${CURRENT_MODULE}} ($(module_desc "${CURRENT_MODULE}")，${CURRENT_MODULE_INDEX}/${CURRENT_MODULE_TOTAL})"
  elif [[ -n "${INSTALL_PHASE:-}" ]]; then
    echo "失败阶段: ${INSTALL_PHASE}"
  fi
  echo "退出码: ${status}"
  echo "位置: line ${line_no}"
  echo "失败命令: ${command_text}"
  [[ -n "${OS_INIT_ARCH_LOG_FILE:-}" ]] && echo "日志文件: ${OS_INIT_ARCH_LOG_FILE}"
  echo
  echo "建议:"
  if [[ -n "${OS_INIT_ARCH_LOG_FILE:-}" ]]; then
    echo "  1. 查看最近日志：tail -n 120 $(printf '%q' "${OS_INIT_ARCH_LOG_FILE}")"
    echo "  2. 修复问题后继续执行：$(install_target_command)"
  else
    echo "  1. 修复问题后继续执行：$(install_target_command)"
  fi
  if [[ -n "${CURRENT_MODULE:-}" ]]; then
    echo "  - 只重跑失败模块：$(install_failed_module_command)"
  fi
  echo "  - 清理相关状态：$(reset_failed_state_command)"
  echo "----------------------------------------------------------"
}

install_error_trap() {
  local status="$1" line_no="$2" command_text="$3"
  [[ "${INSTALL_RECOVERY_ACTIVE:-0}" -eq 1 ]] || return "${status}"
  trap - ERR
  INSTALL_RECOVERY_ACTIVE=0
  show_install_failure_recovery "${status}" "${line_no}" "${command_text}"
  exit "${status}"
}

enable_install_recovery() {
  INSTALL_RECOVERY_ACTIVE=1
  trap 'install_error_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR
}

disable_install_recovery() {
  INSTALL_RECOVERY_ACTIVE=0
  INSTALL_PHASE=""
  CURRENT_MODULE=""
  CURRENT_MODULE_DISPLAY=""
  CURRENT_MODULE_INDEX=0
  CURRENT_MODULE_TOTAL=0
  trap - ERR
}

set_install_phase() {
  INSTALL_PHASE="$1"
}

set_current_module() {
  CURRENT_MODULE="$(module_key "$1")"
  CURRENT_MODULE_DISPLAY="$(module_display_key "${CURRENT_MODULE}")"
  CURRENT_MODULE_INDEX="$2"
  CURRENT_MODULE_TOTAL="$3"
  INSTALL_PHASE="module"
}

clear_current_module() {
  CURRENT_MODULE=""
  CURRENT_MODULE_DISPLAY=""
  CURRENT_MODULE_INDEX=0
  CURRENT_MODULE_TOTAL=0
}

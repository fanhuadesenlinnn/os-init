#!/usr/bin/env bash
# 模块状态：安装成功记录、状态校验、跳过判断和 status 输出。

state_root() {
  printf "%s" "${OS_INIT_ARCH_STATE_DIR:-${HOME}/.local/state/os-init/arch}"
}

state_enabled() {
  [[ "${OS_INIT_ARCH_USE_STATE:-1}" -eq 1 && "${NO_STATE:-0}" -ne 1 ]]
}

state_prepare_dirs() {
  state_enabled || return 0
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  mkdir -p "$(state_root)/modules" "$(state_root)/logs"
}

module_state_file() {
  printf "%s/modules/%s.state" "$(state_root)" "$(module_key "$1")"
}

read_state_value() {
  local file="$1" key="$2"
  [[ -f "${file}" ]] || return 1
  awk -F= -v key="${key}" '$1 == key {print substr($0, length(key) + 2); exit}' "${file}"
}

module_state_valid() {
  local module file expected_hash actual_status actual_hash
  module="$(module_key "$1")"
  state_enabled || return 1
  file="$(module_state_file "${module}")"
  [[ -f "${file}" ]] || return 1

  actual_status="$(read_state_value "${file}" "status" || true)"
  actual_hash="$(read_state_value "${file}" "config_hash" || true)"
  expected_hash="$(module_config_fingerprint "${module}")"
  [[ "${actual_status}" == "success" && "${actual_hash}" == "${expected_hash}" ]] || return 1
  module_quick_verify "${module}"
}

state_collect_module() {
  local module="$1" file status hash expected
  module="$(module_key "${module}")"
  file="$(module_state_file "${module}")"
  status="missing"
  hash="-"
  expected="$(module_config_fingerprint "${module}")"

  STATE_MODULE="${module}"
  STATE_DISPLAY="$(module_display_key "${module}")"
  STATE_FILE="${file}"
  STATE_STATUS="${status}"
  STATE_CHECK="missing"
  STATE_REASON="未找到状态文件"
  STATE_SUGGESTION="需要安装时执行：bash install.sh install $(module_display_key "${module}") --yes"
  STATE_INSTALLED_AT="-"
  STATE_SCRIPT_COMMIT="-"
  STATE_CONFIG_HASH="${hash}"
  STATE_EXPECTED_HASH="${expected}"

  [[ -f "${file}" ]] || return 0

  status="$(read_state_value "${file}" "status" || echo unknown)"
  hash="$(read_state_value "${file}" "config_hash" || echo unknown)"
  STATE_STATUS="${status}"
  STATE_CONFIG_HASH="${hash}"
  STATE_INSTALLED_AT="$(read_state_value "${file}" "installed_at" || echo unknown)"
  STATE_SCRIPT_COMMIT="$(read_state_value "${file}" "script_commit" || echo unknown)"

  if [[ "${status}" != "success" ]]; then
    STATE_CHECK="check-failed"
    STATE_REASON="状态文件记录的状态不是 success"
    STATE_SUGGESTION="建议执行：bash install.sh install $(module_display_key "${module}") --force --yes"
    return 0
  fi

  if [[ "${hash}" != "${expected}" ]]; then
    STATE_CHECK="changed"
    STATE_REASON="当前配置指纹和上次成功安装时不同"
    STATE_SUGGESTION="确认变更后执行：bash install.sh install $(module_display_key "${module}") --force --yes"
    return 0
  fi

  if module_quick_verify "${module}"; then
    STATE_CHECK="ok"
    STATE_REASON="状态文件、配置指纹和轻量校验都通过"
    STATE_SUGGESTION="无需处理"
  else
    STATE_CHECK="check-failed"
    STATE_REASON="配置指纹未变化，但轻量校验未通过"
    STATE_SUGGESTION="先执行：bash install.sh doctor；需要重装时执行：bash install.sh install $(module_display_key "${module}") --force --yes"
  fi
}

mark_module_installed() {
  local module file commit
  module="$(module_key "$1")"
  state_enabled || return 0
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  state_prepare_dirs
  file="$(module_state_file "${module}")"
  commit="$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || printf unknown)"
  {
    printf 'module=%s\n' "${module}"
    printf 'status=success\n'
    printf 'installed_at=%s\n' "$(date -Iseconds)"
    printf 'script_commit=%s\n' "${commit}"
    printf 'config_hash=%s\n' "$(module_config_fingerprint "${module}")"
  } > "${file}"
}

mark_skipped() {
  local module existing
  module="$(module_key "$1")"
  for existing in ${MODULE_SKIPPED_LIST}; do
    [[ "${existing}" == "${module}" ]] && return 0
  done
  MODULE_SKIPPED_LIST="${MODULE_SKIPPED_LIST} ${module}"
}

is_skipped() {
  local module existing
  module="$(module_key "$1")"
  for existing in ${MODULE_SKIPPED_LIST}; do
    [[ "${existing}" == "${module}" ]] && return 0
  done
  return 1
}

reset_module_state() {
  local target="$1" module file
  state_prepare_dirs
  if [[ "${target}" == "all" ]]; then
    rm -f "$(state_root)"/modules/*.state 2>/dev/null || true
    log_info "已清除所有模块状态"
    return 0
  fi
  for module in $(modules_for_target "${target}"); do
    file="$(module_state_file "${module}")"
    rm -f "${file}"
    log_info "已清除模块状态：$(module_display_key "${module}")"
  done
}

state_status_text() {
  local module
  echo "----------------------------------------------------------"
  echo "[OS Init Arch 模块状态]"
  echo "状态目录: $(state_root)"
  echo
  printf "%-18s %-10s %-10s %s\n" "模块" "状态" "校验" "说明"
  for module in "$@"; do
    state_collect_module "${module}"
    printf "%-18s %-10s %-10s %s\n" "${STATE_DISPLAY}" "${STATE_STATUS}" "${STATE_CHECK}" "$(module_desc "${STATE_MODULE}")"
  done

  if [[ "${STATUS_VERBOSE:-0}" -eq 1 ]]; then
    echo
    echo "[状态详情]"
    for module in "$@"; do
      state_collect_module "${module}"
      echo "- ${STATE_DISPLAY}: ${STATE_REASON}"
      echo "  状态文件: ${STATE_FILE}"
      echo "  安装时间: ${STATE_INSTALLED_AT}"
      echo "  脚本提交: ${STATE_SCRIPT_COMMIT}"
      echo "  记录指纹: ${STATE_CONFIG_HASH}"
      echo "  当前指纹: ${STATE_EXPECTED_HASH}"
      echo "  建议动作: ${STATE_SUGGESTION}"
    done
  fi
  echo "----------------------------------------------------------"
}

state_status_json() {
  local module first=1
  printf '{'
  json_metadata_fields "status"; printf ','
  printf '"stateDir":'; json_string "$(state_root)"; printf ','
  printf '"warnings":'; json_warnings_array; printf ','
  printf '"modules":['
  for module in "$@"; do
    state_collect_module "${module}"
    [[ "${first}" -eq 1 ]] || printf ','
    first=0
    printf '{"key":'; json_string "${STATE_MODULE}"
    printf ',"name":'; json_string "${STATE_DISPLAY}"
    printf ',"status":'; json_string "${STATE_STATUS}"
    printf ',"check":'; json_string "${STATE_CHECK}"
    if [[ "${STATUS_VERBOSE:-0}" -eq 1 ]]; then
      printf ',"reason":'; json_string "${STATE_REASON}"
      printf ',"suggestion":'; json_string "${STATE_SUGGESTION}"
      printf ',"stateFile":'; json_string "${STATE_FILE}"
      printf ',"installedAt":'; json_string "${STATE_INSTALLED_AT}"
      printf ',"scriptCommit":'; json_string "${STATE_SCRIPT_COMMIT}"
      printf ',"configHash":'; json_string "${STATE_CONFIG_HASH}"
      printf ',"expectedConfigHash":'; json_string "${STATE_EXPECTED_HASH}"
    fi
    printf '}'
  done
  printf ']}\n'
}

show_status() {
  local modules=() target="${TARGET:-all}"
  if [[ "${target}" == "all" ]]; then
    read -r -a modules <<<"$(all_modules)"
  else
    read -r -a modules <<<"$(modules_for_target "${target}")"
  fi

  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    state_status_json "${modules[@]}"
  else
    state_status_text "${modules[@]}"
  fi
}

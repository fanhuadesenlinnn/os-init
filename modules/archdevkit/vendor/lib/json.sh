#!/usr/bin/env bash
# JSON 输出辅助：为 plan/status/doctor 提供稳定、可复用的机器输出格式。

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

json_bool() {
  case "${1:-0}" in
    1|true|yes|on) printf "true" ;;
    *) printf "false" ;;
  esac
}

json_metadata_fields() {
  local command_name="$1"
  printf '"schemaVersion":'; json_string "${ARCHDEVKIT_JSON_SCHEMA_VERSION:-1}"; printf ','
  printf '"command":'; json_string "${command_name}"; printf ','
  printf '"generatedAt":'; json_string "$(date -Iseconds)"
}

json_warnings_array() {
  local warning first=1
  printf '['
  [[ "${#CONFIG_WARNINGS[@]}" -gt 0 ]] || {
    printf ']'
    return 0
  }
  for warning in "${CONFIG_WARNINGS[@]}"; do
    [[ "${first}" -eq 1 ]] || printf ','
    first=0
    json_string "${warning}"
  done
  printf ']'
}

show_config_warnings_text() {
  local warning
  [[ "${#CONFIG_WARNINGS[@]}" -gt 0 ]] || return 0
  echo
  echo "配置提示:"
  for warning in "${CONFIG_WARNINGS[@]}"; do
    echo "  - ${warning}"
  done
}

#!/usr/bin/env bash

plan_has_module() {
  local modules_text="$1" wanted module
  wanted="$(module_key "$2")"
  for module in ${modules_text}; do
    [[ "$(module_key "${module}")" == "${wanted}" ]] && return 0
  done
  return 1
}

modules_for_target() {
  case "$1" in
    base|aur|dns|archlinuxcn|git|ops|ops-toolkit|ops_toolkit|fonts) module_key "$1" ;;
    proxy|sing-box) echo proxy ;;
    desktop|hyprland) echo desktop_hyprland ;;
    *) die "未知 Arch 能力：$1" ;;
  esac
}

plan_needs_git_command() {
  local modules_text="$1"
  plan_has_module "${modules_text}" ops_toolkit && return 0
  plan_has_module "${modules_text}" desktop_hyprland && desktop_needs_rime_repo && return 0
  return 1
}

show_plan_json() {
  local title="$1" modules_text="$2" module first=1
  printf '{"target":'; json_string "${title}"
  printf ',"stateDir":'; json_string "$(state_root)"
  printf ',"modules":['
  for module in ${modules_text}; do
    [[ "${first}" -eq 1 ]] || printf ','
    first=0
    printf '{"key":'; json_string "$(module_key "${module}")"
    printf ',"description":'; json_string "$(module_desc "${module}")"
    printf '}'
  done
  printf ']}\n'
}

show_plan() {
  local title="$1" modules_text="$2" module impact
  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    show_plan_json "${title}" "${modules_text}"
    return
  fi
  echo "----------------------------------------------------------"
  echo "[Arch 能力执行计划]"
  echo "目标: ${title}"
  for module in ${modules_text}; do
    echo "  - $(module_display_key "${module}"): $(module_desc "${module}")"
    while IFS= read -r impact; do
      [[ -n "${impact}" ]] && echo "      ${impact}"
    done < <(module_impacts "${module}")
  done
  echo "----------------------------------------------------------"
}

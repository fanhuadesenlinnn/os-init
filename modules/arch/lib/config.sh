#!/usr/bin/env bash
# Load only Arch-specific settings from the shared OS Init config file.

CONFIG_FILE_LOADED=0
CONFIG_LOAD_WARNINGS=()
CONFIG_WARNINGS=()

config_file_path() {
  printf "%s" "${OS_INIT_ARCH_CONFIG_FILE:-${HOME}/.config/os-init/config.env}"
}

config_scalar_keys() {
  cat <<'EOF'
ASSUME_YES DRY_RUN OS_INIT_ARCH_USE_STATE OS_INIT_ARCH_STATE_DIR OS_INIT_ARCH_LOAD_CONFIG_FILE OS_INIT_ARCH_CONFIG_FILE OS_INIT_ARCH_JSON_SCHEMA_VERSION
ENABLE_CHINA_MIRROR ENABLE_GITHUB_PROXY GITHUB_PROXY
ENABLE_DNS DNS_DNSSEC DNS_OVER_TLS DNS_CACHE DNS_LLMNR DNS_MULTICAST_DNS DNS_CONFIGURE_NETWORKMANAGER DNS_LINK_RESOLV_CONF DNS_RESTART_NETWORKMANAGER
INSTALL_ARCHLINUXCN ARCHLINUXCN_SERVER INSTALL_ARCHLINUXCN_MIRRORLIST
ENABLE_OPS_TOOLKIT OPS_TOOLKIT_REPO OPS_TOOLKIT_BRANCH OPS_TOOLKIT_DIR OPS_TOOLKIT_BIN_DIR OPS_TOOLKIT_COMMAND
INSTALL_CN_FONTS INSTALL_NERD_FONTS INSTALL_MONACO_FONT MONACO_AS_SYSTEM_FONT SYSTEM_FONT_FAMILY SYSTEM_MONOSPACE_FONT_FAMILY SYSTEM_CJK_FONT_FAMILY SYSTEM_EMOJI_FONT_FAMILY MONACO_FONT_PACKAGE
ENABLE_SDDM ENABLE_BLUETOOTH ENABLE_FCITX5 INPUT_METHOD_ENGINE RIME_SCHEMA INSTALL_RIME_CONFIG RIME_CONFIG_REPO RIME_CONFIG_BRANCH RIME_CONFIG_DIR GPU_TYPE VMWARE_HYPRLAND_MONITOR_MODE VMWARE_FORCE_SOFTWARE_RENDERER VM_HYPRLAND_MONITOR_MODE VM_HYPRLAND_DYNAMIC_RESIZE VM_HYPRLAND_LOW_LATENCY HYPRLAND_CONFIG_MODE HYPRDOTS_SOURCE_DIR HYPRDOTS_SOURCE_COMMIT HYPRDOTS_LOCAL_BIN_DIR HYPRDOTS_WALLPAPER_DIR INSTALL_HYPRDOTS_OBSIDIAN TERMINAL_APP APP_LAUNCHER FILE_MANAGER BROWSER_PACKAGE BROWSER_APP
PROXY_AUTO_ENABLE_SERVICE MIHOMO_PACKAGE MIHOMO_SERVICE_NAME MIHOMO_CONFIG_DIR MIHOMO_CONFIG_FILE MIHOMO_CONFIG_SOURCE MIHOMO_MIXED_PORT MIHOMO_ALLOW_LAN MIHOMO_BIND_ADDRESS MIHOMO_CONTROLLER_HOST MIHOMO_CONTROLLER_PORT MIHOMO_DNS_LISTEN MIHOMO_SECRET MIHOMO_STATE_DIR MIHOMO_EXTERNAL_UI_DIR ENABLE_METACUBEXD METACUBEXD_PACKAGE METACUBEXD_WEB_ROOT
EOF
}

config_list_keys() {
  echo "DNS_SERVERS DNS_FALLBACK_SERVERS DNS_FOREIGN_FALLBACK_SERVERS HYPRDOTS_CONFIG_MODULES"
}

config_bool_keys() {
  cat <<'EOF'
ASSUME_YES DRY_RUN OS_INIT_ARCH_USE_STATE OS_INIT_ARCH_LOAD_CONFIG_FILE ENABLE_CHINA_MIRROR ENABLE_GITHUB_PROXY
ENABLE_DNS DNS_CONFIGURE_NETWORKMANAGER DNS_LINK_RESOLV_CONF DNS_RESTART_NETWORKMANAGER INSTALL_ARCHLINUXCN INSTALL_ARCHLINUXCN_MIRRORLIST ENABLE_OPS_TOOLKIT
INSTALL_CN_FONTS INSTALL_NERD_FONTS INSTALL_MONACO_FONT MONACO_AS_SYSTEM_FONT ENABLE_SDDM ENABLE_BLUETOOTH ENABLE_FCITX5 INSTALL_RIME_CONFIG
VMWARE_FORCE_SOFTWARE_RENDERER VM_HYPRLAND_DYNAMIC_RESIZE VM_HYPRLAND_LOW_LATENCY INSTALL_HYPRDOTS_OBSIDIAN PROXY_AUTO_ENABLE_SERVICE MIHOMO_ALLOW_LAN ENABLE_METACUBEXD
EOF
}

word_list_has() {
  local wanted="$1" item
  local items=()
  read -r -a items <<< "$2"
  for item in "${items[@]}"; do
    [[ "${item}" == "${wanted}" ]] && return 0
  done
  return 1
}

trim_config_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "${value}"
}

strip_optional_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]] ||
       [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf "%s" "${value}"
}

config_scalar_allowed() {
  word_list_has "$1" "$(config_scalar_keys)"
}

config_list_allowed() {
  word_list_has "$1" "$(config_list_keys)"
}

add_config_load_warning() {
  CONFIG_LOAD_WARNINGS+=("$1")
}

add_config_warning() {
  CONFIG_WARNINGS+=("$1")
}

assign_config_list() {
  local key="$1" value="$2" item
  local values=()
  value="${value//,/ }"
  for item in ${value}; do
    [[ -n "${item}" ]] && values+=("${item}")
  done
  case "${key}" in
    DNS_SERVERS) DNS_SERVERS=("${values[@]}") ;;
    DNS_FALLBACK_SERVERS) DNS_FALLBACK_SERVERS=("${values[@]}") ;;
    DNS_FOREIGN_FALLBACK_SERVERS) DNS_FOREIGN_FALLBACK_SERVERS=("${values[@]}") ;;
    HYPRDOTS_CONFIG_MODULES)
      # shellcheck disable=SC2034
      HYPRDOTS_CONFIG_MODULES=("${values[@]}")
      ;;
  esac
}

apply_config_assignment() {
  local key="$1" value="$2"
  if config_scalar_allowed "${key}"; then
    printf -v "${key}" "%s" "${value}"
  elif config_list_allowed "${key}"; then
    assign_config_list "${key}" "${value}"
  fi
  # Other keys belong to normal OS Init modules and are intentionally ignored.
}

load_user_config_file() {
  local config_file line key value line_no=0
  case "$(to_lower "${OS_INIT_ARCH_LOAD_CONFIG_FILE:-1}")" in
    1|true|yes|y|on) ;;
    *) return 0 ;;
  esac
  config_file="$(config_file_path)"
  [[ -f "${config_file}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_no=$((line_no + 1))
    line="$(trim_config_value "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" != *=* ]]; then
      add_config_load_warning "配置文件第 ${line_no} 行缺少 =，已忽略"
      continue
    fi
    key="$(trim_config_value "${line%%=*}")"
    value="$(strip_optional_quotes "$(trim_config_value "${line#*=}")")"
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      add_config_load_warning "配置文件第 ${line_no} 行键名非法，已忽略：${key}"
      continue
    fi
    apply_config_assignment "${key}" "${value}"
  done < "${config_file}"
  # Used by doctor.sh after this file is sourced by the entry point.
  # shellcheck disable=SC2034
  CONFIG_FILE_LOADED=1
}

parse_config_file_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--config-file 需要路径"
        OS_INIT_ARCH_CONFIG_FILE="$2"
        OS_INIT_ARCH_LOAD_CONFIG_FILE=1
        shift 2
        ;;
      --config-file=*) OS_INIT_ARCH_CONFIG_FILE="${1#*=}"; OS_INIT_ARCH_LOAD_CONFIG_FILE=1; shift ;;
      --no-config-file) OS_INIT_ARCH_LOAD_CONFIG_FILE=0; shift ;;
      *) shift ;;
    esac
  done
}

normalize_bool_var() {
  local key="$1" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "$(to_lower "${value}")" in
    1|true|yes|y|on|enable|enabled) printf -v "${key}" "%s" 1 ;;
    0|false|no|n|off|disable|disabled) printf -v "${key}" "%s" 0 ;;
    *) die "${key} 仅支持布尔值；当前值：${value}" ;;
  esac
}

validate_repo_url_var() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "${value}" in
    http://*|https://*|git@*|ssh://*) ;;
    *) die "${desc} 必须是 Git URL 或 http(s) URL：${key}=${value}" ;;
  esac
}

validate_source_reference() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "${value}" in http://*|https://*) return 0 ;; esac
  [[ -e "${value}" ]] || add_config_warning "${desc} 本地路径当前不存在：${value}"
}

validate_port_var() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${desc} 必须是数字端口：${key}=${value}"
  (( value >= 1 && value <= 65535 )) || die "${desc} 端口范围必须是 1-65535：${key}=${value}"
}

validate_dns_list() {
  local key="$1" desc="$2" count=0
  case "${key}" in
    DNS_SERVERS) count="${#DNS_SERVERS[@]}" ;;
    DNS_FALLBACK_SERVERS) count="${#DNS_FALLBACK_SERVERS[@]}" ;;
    DNS_FOREIGN_FALLBACK_SERVERS) count="${#DNS_FOREIGN_FALLBACK_SERVERS[@]}" ;;
  esac
  (( count > 0 )) || die "${desc} 不能为空：${key}"
}

validate_config() {
  local key
  CONFIG_WARNINGS=()
  if (( ${#CONFIG_LOAD_WARNINGS[@]} > 0 )); then
    CONFIG_WARNINGS=("${CONFIG_LOAD_WARNINGS[@]}")
  fi
  for key in $(config_bool_keys); do normalize_bool_var "${key}"; done

  case "${DNS_OVER_TLS:-no}" in no|opportunistic|yes) ;; *) die "DNS_OVER_TLS 仅支持 no / opportunistic / yes" ;; esac
  case "${GPU_TYPE:-auto}" in auto|intel|amd|nvidia|vmware|virtio|qxl|virtualbox|none) ;; *) die "GPU_TYPE 不支持：${GPU_TYPE}" ;; esac
  case "${INPUT_METHOD_ENGINE:-rime}" in rime|pinyin) ;; *) die "INPUT_METHOD_ENGINE 仅支持 rime / pinyin" ;; esac
  validate_hyprland_config_mode

  if [[ "${ENABLE_DNS:-0}" -eq 1 ]]; then
    validate_dns_list DNS_SERVERS "DNS 服务器列表"
    validate_dns_list DNS_FALLBACK_SERVERS "DNS fallback 列表"
    validate_dns_list DNS_FOREIGN_FALLBACK_SERVERS "DNS 国外 fallback 列表"
  fi
  validate_repo_url_var OPS_TOOLKIT_REPO "Ops Toolkit 仓库"
  [[ -n "${OPS_TOOLKIT_DIR:-}" && -n "${OPS_TOOLKIT_BIN_DIR:-}" && -n "${OPS_TOOLKIT_COMMAND:-}" ]] || die "Ops Toolkit 路径和命令不能为空"
  if [[ "${INSTALL_RIME_CONFIG:-0}" -eq 1 ]]; then validate_repo_url_var RIME_CONFIG_REPO "Rime 配置仓库"; fi
  [[ -n "${BROWSER_PACKAGE:-}" && -n "${BROWSER_APP:-}" ]] || die "浏览器安装包和启动命令不能为空"
  validate_port_var MIHOMO_MIXED_PORT "Mihomo mixed-port"
  validate_port_var MIHOMO_CONTROLLER_PORT "Mihomo 控制接口"
  [[ "${MIHOMO_DNS_LISTEN:-}" == *:* ]] || die "MIHOMO_DNS_LISTEN 需要包含 host:port"
  validate_source_reference MIHOMO_CONFIG_SOURCE "Mihomo 配置来源"
  if [[ "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}" == "0.0.0.0" && -z "${MIHOMO_SECRET:-}" ]]; then
    add_config_warning "Mihomo 控制接口监听 0.0.0.0 且 secret 为空，局域网可访问控制 API"
  fi
}

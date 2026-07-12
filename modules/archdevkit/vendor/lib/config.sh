#!/usr/bin/env bash
# 配置层：加载用户配置、归一化默认值，并在安装前做轻量校验。

CONFIG_FILE_LOADED=0
CONFIG_LOAD_WARNINGS=()
CONFIG_WARNINGS=()

config_file_path() {
  printf "%s" "${ARCHDEVKIT_CONFIG_FILE:-${HOME}/.config/archdevkit/config.env}"
}

config_scalar_keys() {
  cat <<'EOF'
ASSUME_YES DRY_RUN ARCHDEVKIT_DEFAULT_PROFILE ARCHDEVKIT_USE_STATE ARCHDEVKIT_STATE_DIR ARCHDEVKIT_LOAD_CONFIG_FILE ARCHDEVKIT_CONFIG_FILE ARCHDEVKIT_JSON_SCHEMA_VERSION
ENABLE_CHINA_MIRROR ENABLE_GITHUB_PROXY GITHUB_PROXY NPM_REGISTRY PIP_INDEX_URL PIP_TRUSTED_HOST UV_DEFAULT_INDEX GOPROXY NODE_MIRROR_URL GO_DOWNLOAD_MIRROR
ENABLE_DNS DNS_DNSSEC DNS_OVER_TLS DNS_CACHE DNS_LLMNR DNS_MULTICAST_DNS DNS_CONFIGURE_NETWORKMANAGER DNS_LINK_RESOLV_CONF DNS_RESTART_NETWORKMANAGER
INSTALL_ARCHLINUXCN ARCHLINUXCN_SERVER INSTALL_ARCHLINUXCN_MIRRORLIST
RUNTIME_MANAGER NODE_VERSION PYTHON_VERSION GO_VERSION ENABLE_COREPACK
ENABLE_OPS_TOOLKIT OPS_TOOLKIT_REPO OPS_TOOLKIT_BRANCH OPS_TOOLKIT_DIR OPS_TOOLKIT_BIN_DIR OPS_TOOLKIT_COMMAND
NVIM_REPO NVIM_BRANCH NVIM_CONFIG_DIR SYNC_NVIM_PLUGINS
INSTALL_OH_MY_ZSH SHELL_PROMPT_ENGINE INSTALL_POWERLEVEL10K INSTALL_P10K_CONFIG SET_ZSH_AS_DEFAULT OS_INIT_TERMINAL_STYLE OS_INIT_TERMINAL_ENABLE_ALIASES OS_INIT_TERMINAL_BAT_THEME OH_MY_ZSH_REPO ZSH_AUTOSUGGESTIONS_REPO ZSH_SYNTAX_HIGHLIGHTING_REPO POWERLEVEL10K_REPO ZSH_THEME_NAME ZSH_PLUGINS P10K_CONFIG_SOURCE
INSTALL_CN_FONTS INSTALL_NERD_FONTS INSTALL_MONACO_FONT MONACO_AS_SYSTEM_FONT SYSTEM_FONT_FAMILY SYSTEM_MONOSPACE_FONT_FAMILY SYSTEM_CJK_FONT_FAMILY SYSTEM_EMOJI_FONT_FAMILY MONACO_FONT_PACKAGE
ENABLE_DOCKER_SERVICE ADD_USER_TO_DOCKER_GROUP CONFIGURE_DOCKER_MIRRORS
ENABLE_SDDM ENABLE_BLUETOOTH ENABLE_FCITX5 INPUT_METHOD_ENGINE RIME_SCHEMA INSTALL_RIME_CONFIG RIME_CONFIG_REPO RIME_CONFIG_BRANCH RIME_CONFIG_DIR GPU_TYPE VMWARE_HYPRLAND_MONITOR_MODE VMWARE_FORCE_SOFTWARE_RENDERER VM_HYPRLAND_MONITOR_MODE VM_HYPRLAND_DYNAMIC_RESIZE VM_HYPRLAND_LOW_LATENCY HYPRLAND_CONFIG_MODE HYPRDOTS_SOURCE_DIR HYPRDOTS_SOURCE_COMMIT HYPRDOTS_LOCAL_BIN_DIR HYPRDOTS_WALLPAPER_DIR INSTALL_HYPRDOTS_OBSIDIAN TERMINAL_APP APP_LAUNCHER FILE_MANAGER BROWSER_PACKAGE BROWSER_APP
ENABLE_PROXY PROXY_CORE PROXY_AUTO_ENABLE_SERVICE MIHOMO_PACKAGE MIHOMO_SERVICE_NAME MIHOMO_CONFIG_DIR MIHOMO_CONFIG_FILE MIHOMO_CONFIG_SOURCE MIHOMO_MIXED_PORT MIHOMO_ALLOW_LAN MIHOMO_BIND_ADDRESS MIHOMO_CONTROLLER_HOST MIHOMO_CONTROLLER_PORT MIHOMO_DNS_LISTEN MIHOMO_SECRET MIHOMO_STATE_DIR MIHOMO_EXTERNAL_UI_DIR ENABLE_METACUBEXD METACUBEXD_PACKAGE METACUBEXD_WEB_ROOT SING_BOX_PACKAGE SING_BOX_CONFIG_DIR SING_BOX_CONFIG_FILE SING_BOX_CONFIG_SOURCE SING_BOX_MIXED_PORT
EOF
}

config_list_keys() {
  cat <<'EOF'
DNS_SERVERS DNS_FALLBACK_SERVERS DNS_FOREIGN_FALLBACK_SERVERS DOCKER_MIRRORS HYPRDOTS_CONFIG_MODULES
EOF
}

config_bool_keys() {
  cat <<'EOF'
ASSUME_YES DRY_RUN ARCHDEVKIT_USE_STATE ARCHDEVKIT_LOAD_CONFIG_FILE ENABLE_CHINA_MIRROR ENABLE_GITHUB_PROXY ENABLE_DNS DNS_CONFIGURE_NETWORKMANAGER DNS_LINK_RESOLV_CONF DNS_RESTART_NETWORKMANAGER INSTALL_ARCHLINUXCN INSTALL_ARCHLINUXCN_MIRRORLIST ENABLE_COREPACK ENABLE_OPS_TOOLKIT SYNC_NVIM_PLUGINS INSTALL_OH_MY_ZSH INSTALL_POWERLEVEL10K INSTALL_P10K_CONFIG SET_ZSH_AS_DEFAULT OS_INIT_TERMINAL_ENABLE_ALIASES INSTALL_CN_FONTS INSTALL_NERD_FONTS INSTALL_MONACO_FONT MONACO_AS_SYSTEM_FONT ENABLE_DOCKER_SERVICE ADD_USER_TO_DOCKER_GROUP CONFIGURE_DOCKER_MIRRORS ENABLE_SDDM ENABLE_BLUETOOTH ENABLE_FCITX5 INSTALL_RIME_CONFIG VMWARE_FORCE_SOFTWARE_RENDERER VM_HYPRLAND_DYNAMIC_RESIZE VM_HYPRLAND_LOW_LATENCY INSTALL_HYPRDOTS_OBSIDIAN ENABLE_PROXY PROXY_AUTO_ENABLE_SERVICE MIHOMO_ALLOW_LAN ENABLE_METACUBEXD
EOF
}

word_list_has() {
  local wanted="$1" item
  while IFS= read -r item; do
    for item in ${item}; do
      [[ "${item}" == "${wanted}" ]] && return 0
    done
  done
  return 1
}

config_scalar_allowed() {
  config_scalar_keys | word_list_has "$1"
}

config_list_allowed() {
  config_list_keys | word_list_has "$1"
}

config_escape_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf "%s" "${value}"
}

config_join_list() {
  local IFS=,
  printf "%s" "$*"
}

config_value_for_key() {
  local key="$1"
  case "${key}" in
    DNS_SERVERS) config_join_list "${DNS_SERVERS[@]}" ;;
    DNS_FALLBACK_SERVERS) config_join_list "${DNS_FALLBACK_SERVERS[@]}" ;;
    DNS_FOREIGN_FALLBACK_SERVERS) config_join_list "${DNS_FOREIGN_FALLBACK_SERVERS[@]}" ;;
    DOCKER_MIRRORS) config_join_list "${DOCKER_MIRRORS[@]}" ;;
    HYPRDOTS_CONFIG_MODULES) config_join_list "${HYPRDOTS_CONFIG_MODULES[@]}" ;;
    *)
      printf "%s" "${!key-}"
      ;;
  esac
}

config_write_key() {
  local key="$1" value
  value="$(config_value_for_key "${key}")"
  printf '%s="%s"\n' "${key}" "$(config_escape_value "${value}")"
}

config_write_section() {
  local title="$1" key
  shift
  printf '\n# %s\n' "${title}"
  for key in "$@"; do
    config_write_key "${key}"
  done
}

config_write_effective() {
  cat <<'EOF'
# ArchDevKit 用户配置
# 由 bash install.sh config init 生成。
# 修改这里会覆盖 install_vars 中的默认值；未写出的键继续使用项目默认值。
EOF

  config_write_section "全局行为" \
    ARCHDEVKIT_DEFAULT_PROFILE ARCHDEVKIT_USE_STATE ARCHDEVKIT_STATE_DIR

  config_write_section "中国大陆网络" \
    ENABLE_CHINA_MIRROR ENABLE_GITHUB_PROXY GITHUB_PROXY NPM_REGISTRY PIP_INDEX_URL PIP_TRUSTED_HOST \
    UV_DEFAULT_INDEX GOPROXY NODE_MIRROR_URL GO_DOWNLOAD_MIRROR

  config_write_section "DNS" \
    ENABLE_DNS DNS_SERVERS DNS_FALLBACK_SERVERS DNS_FOREIGN_FALLBACK_SERVERS DNS_DNSSEC DNS_OVER_TLS \
    DNS_CACHE DNS_LLMNR DNS_MULTICAST_DNS DNS_CONFIGURE_NETWORKMANAGER DNS_LINK_RESOLV_CONF DNS_RESTART_NETWORKMANAGER

  config_write_section "软件源和运行时" \
    INSTALL_ARCHLINUXCN ARCHLINUXCN_SERVER INSTALL_ARCHLINUXCN_MIRRORLIST \
    RUNTIME_MANAGER NODE_VERSION PYTHON_VERSION GO_VERSION ENABLE_COREPACK

  config_write_section "Ops Toolkit" \
    ENABLE_OPS_TOOLKIT OPS_TOOLKIT_REPO OPS_TOOLKIT_BRANCH OPS_TOOLKIT_DIR OPS_TOOLKIT_BIN_DIR OPS_TOOLKIT_COMMAND

  config_write_section "Neovim / Shell / 字体 / Docker" \
    NVIM_REPO NVIM_BRANCH NVIM_CONFIG_DIR SYNC_NVIM_PLUGINS \
    INSTALL_OH_MY_ZSH SHELL_PROMPT_ENGINE INSTALL_POWERLEVEL10K INSTALL_P10K_CONFIG SET_ZSH_AS_DEFAULT \
    OS_INIT_TERMINAL_STYLE OS_INIT_TERMINAL_ENABLE_ALIASES OS_INIT_TERMINAL_BAT_THEME ZSH_THEME_NAME ZSH_PLUGINS \
    INSTALL_CN_FONTS INSTALL_NERD_FONTS INSTALL_MONACO_FONT MONACO_AS_SYSTEM_FONT \
    ENABLE_DOCKER_SERVICE ADD_USER_TO_DOCKER_GROUP CONFIGURE_DOCKER_MIRRORS DOCKER_MIRRORS

  config_write_section "Hyprland 桌面" \
    ENABLE_SDDM ENABLE_BLUETOOTH ENABLE_FCITX5 INPUT_METHOD_ENGINE RIME_SCHEMA INSTALL_RIME_CONFIG \
    RIME_CONFIG_REPO RIME_CONFIG_BRANCH RIME_CONFIG_DIR GPU_TYPE VMWARE_FORCE_SOFTWARE_RENDERER \
    VM_HYPRLAND_MONITOR_MODE VM_HYPRLAND_DYNAMIC_RESIZE VM_HYPRLAND_LOW_LATENCY HYPRLAND_CONFIG_MODE \
    INSTALL_HYPRDOTS_OBSIDIAN HYPRDOTS_CONFIG_MODULES TERMINAL_APP APP_LAUNCHER FILE_MANAGER BROWSER_PACKAGE BROWSER_APP

  config_write_section "Proxy" \
    ENABLE_PROXY PROXY_CORE PROXY_AUTO_ENABLE_SERVICE MIHOMO_PACKAGE MIHOMO_SERVICE_NAME MIHOMO_CONFIG_DIR \
    MIHOMO_CONFIG_FILE MIHOMO_CONFIG_SOURCE MIHOMO_MIXED_PORT MIHOMO_ALLOW_LAN MIHOMO_BIND_ADDRESS \
    MIHOMO_CONTROLLER_HOST MIHOMO_CONTROLLER_PORT MIHOMO_DNS_LISTEN MIHOMO_SECRET MIHOMO_STATE_DIR \
    MIHOMO_EXTERNAL_UI_DIR ENABLE_METACUBEXD METACUBEXD_PACKAGE METACUBEXD_WEB_ROOT \
    SING_BOX_PACKAGE SING_BOX_CONFIG_DIR SING_BOX_CONFIG_FILE SING_BOX_CONFIG_SOURCE SING_BOX_MIXED_PORT
}

config_init_file() {
  local config_file tmp_file
  config_file="$(config_file_path)"

  if [[ -e "${config_file}" && "${FORCE_INSTALL:-0}" -ne 1 ]]; then
    die "配置文件已存在：${config_file}；如需覆盖请加 --force"
  fi

  log_info "生成用户配置文件：${config_file}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${config_file}"
    return 0
  fi

  mkdir -p "$(dirname "${config_file}")"
  tmp_file="$(mktemp)"
  config_write_effective > "${tmp_file}"
  install -m 0600 "${tmp_file}" "${config_file}"
  rm -f "${tmp_file}"
}

config_validate_command() {
  log_info "配置校验通过"
  show_config_warnings_text
}

show_config() {
  echo "----------------------------------------------------------"
  echo "[当前安装配置]"
  echo "执行用户:             ${USER}"
  echo "默认目标:             ${ARCHDEVKIT_DEFAULT_PROFILE:-workstation}"
  echo "dry-run:              $(bool_text "${DRY_RUN}")"
  echo "自动确认:             $(bool_text "${ASSUME_YES}")"
  echo "用户配置文件:         $(config_file_path)"
  echo "已加载用户配置:       $(bool_text "${CONFIG_FILE_LOADED}")"
  echo "模块状态目录:         $(state_root)"
  echo "JSON schema:          ${ARCHDEVKIT_JSON_SCHEMA_VERSION:-1}"
  echo
  echo "[中国大陆网络]"
  echo "启用国内源:           $(bool_text "${ENABLE_CHINA_MIRROR}")"
  echo "npm 源:               ${NPM_REGISTRY}"
  echo "pip 源:               ${PIP_INDEX_URL}"
  echo "mise Node 镜像:       ${NODE_MIRROR_URL}"
  echo "mise Go 镜像:         ${GO_DOWNLOAD_MIRROR}"
  echo "uv 源:                ${UV_DEFAULT_INDEX}"
  echo "Go module 代理:       ${GOPROXY}"
  echo "启用 GitHub 代理:     $(bool_text "${ENABLE_GITHUB_PROXY}")"
  echo "GitHub 代理地址:      ${GITHUB_PROXY}"
  echo "系统 DNS:             $(bool_text "${ENABLE_DNS}")"
  echo "DNS 服务器:           ${DNS_SERVERS[*]}"
  echo "DNS fallback:         ${DNS_FALLBACK_SERVERS[*]}"
  echo "DNS 国外 fallback:    ${DNS_FOREIGN_FALLBACK_SERVERS[*]}"
  echo "DNSOverTLS:           ${DNS_OVER_TLS}"
  echo "HTTPS_PROXY:          ${HTTPS_PROXY:-未设置}"
  echo "HTTP_PROXY:           ${HTTP_PROXY:-未设置}"
  echo "ALL_PROXY:            ${ALL_PROXY:-未设置}"
  echo
  echo "[Runtime]"
  echo "系统包:               mise"
  echo "管理工具:             ${RUNTIME_MANAGER}（统一安装并管理语言运行时）"
  echo "mise Node.js 目标:    ${NODE_VERSION}"
  echo "mise Python 目标:     ${PYTHON_VERSION}"
  echo "mise Go 目标:         ${GO_VERSION}"
  echo "Corepack:             $(bool_text "${ENABLE_COREPACK}")"
  echo
  echo "[Ops Toolkit]"
  echo "随 dev/workstation 安装: $(bool_text "${ENABLE_OPS_TOOLKIT}")"
  echo "仓库:                 ${OPS_TOOLKIT_REPO}"
  echo "实际下载地址:         $(github_proxy_url "${OPS_TOOLKIT_REPO}")"
  echo "分支:                 ${OPS_TOOLKIT_BRANCH:-默认分支}"
  echo "本地目录:             ${OPS_TOOLKIT_DIR}"
  echo "命令目录:             ${OPS_TOOLKIT_BIN_DIR}"
  echo "调度命令:             ${OPS_TOOLKIT_COMMAND}"
  echo
  echo "[Neovim]"
  echo "配置仓库:             ${NVIM_REPO}"
  echo "实际下载地址:         $(github_proxy_url "${NVIM_REPO}")"
  echo "配置分支:             ${NVIM_BRANCH:-默认分支}"
  echo "同步插件:             $(bool_text "${SYNC_NVIM_PLUGINS}")"
  echo
  echo "[Zsh / 字体 / Docker / Hyprland]"
  echo "提示符引擎:           ${SHELL_PROMPT_ENGINE:-starship}"
  echo "终端样式:             ${OS_INIT_TERMINAL_STYLE:-auto}"
  echo "终端 alias:           $(bool_text "${OS_INIT_TERMINAL_ENABLE_ALIASES:-1}")"
  echo "Powerlevel10k:        $(bool_text "${INSTALL_POWERLEVEL10K}")"
  echo "p10k 配置:            $(bool_text "${INSTALL_P10K_CONFIG}")"
  echo "切换默认 shell:       $(bool_text "${SET_ZSH_AS_DEFAULT}")"
  echo "Monaco 字体:          $(bool_text "${INSTALL_MONACO_FONT}")"
  echo "Docker 镜像源:        $(bool_text "${CONFIGURE_DOCKER_MIRRORS}")"
  echo "Hyprland SDDM:        $(bool_text "${ENABLE_SDDM}")"
  echo "GPU 类型:             ${GPU_TYPE}"
  echo "VMware 软件渲染:      $(bool_text "${VMWARE_FORCE_SOFTWARE_RENDERER:-1}")"
  echo "VM 动态分辨率:        $(bool_text "${VM_HYPRLAND_DYNAMIC_RESIZE:-1}")"
  echo "VM 低延迟配置:        $(bool_text "${VM_HYPRLAND_LOW_LATENCY:-1}")"
  echo "VM 显示 fallback:     ${VM_HYPRLAND_MONITOR_MODE:-${VMWARE_HYPRLAND_MONITOR_MODE:-1920x1080@60}}"
  echo "Hyprland 配置模式:    ${HYPRLAND_CONFIG_MODE}"
  if hyprdots_mode_enabled; then
    echo "hyprdots 来源提交:    ${HYPRDOTS_SOURCE_COMMIT:-unknown}"
    echo "hyprdots 配置目录:    ${HYPRDOTS_SOURCE_DIR}"
    echo "hyprdots 本地脚本:    ${HYPRDOTS_LOCAL_BIN_DIR}"
    echo "hyprdots 壁纸目录:    ${HYPRDOTS_WALLPAPER_DIR}"
    echo "hyprdots Obsidian:    $(bool_text "${INSTALL_HYPRDOTS_OBSIDIAN}")"
  fi
  echo "浏览器安装包:         ${BROWSER_PACKAGE}"
  echo "浏览器启动命令:       ${BROWSER_APP}"
  echo "终端启动命令:         ${TERMINAL_APP}"
  echo "Neovide 包装命令:     ${HOME}/.local/bin/neovide"
  echo "输入法框架:           Fcitx5 $(bool_text "${ENABLE_FCITX5}")"
  echo "输入法引擎:           ${INPUT_METHOD_ENGINE}"
  echo "Rime 默认方案:        ${RIME_SCHEMA}"
  echo "Rime 配置仓库:        ${RIME_CONFIG_REPO:-不安装}"
  echo "Rime 配置分支:        ${RIME_CONFIG_BRANCH:-默认分支}"
  echo "Rime 配置目录:        ${RIME_CONFIG_DIR}"
  echo "安装 Rime 配置:       $(bool_text "${INSTALL_RIME_CONFIG}")"
  echo
  echo "[Proxy]"
  echo "随 dev/workstation 安装: $(bool_text "${ENABLE_PROXY}")"
  echo "代理核心:             ${PROXY_CORE}"
  echo "自动启用服务:         $(bool_text "${PROXY_AUTO_ENABLE_SERVICE}")"
  echo "Mihomo 包:            ${MIHOMO_PACKAGE}"
  echo "Mihomo 系统服务:      ${MIHOMO_SERVICE_NAME:-mihomo.service}"
  echo "Mihomo 配置目录:      ${MIHOMO_CONFIG_DIR:-/etc/mihomo}"
  echo "Mihomo 配置文件:      ${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
  echo "Mihomo 配置来源:      ${MIHOMO_CONFIG_SOURCE:-生成基础模板}"
  echo "Mihomo 规则源:        原始 URL（不配置代理前缀）"
  echo "Mihomo mixed-port:    ${MIHOMO_MIXED_PORT}"
  echo "Mihomo allow-lan:     $(bool_text "${MIHOMO_ALLOW_LAN}")"
  echo "Mihomo bind-address:  ${MIHOMO_BIND_ADDRESS}"
  echo "Mihomo 控制接口:      http://${MIHOMO_CONTROLLER_HOST}:${MIHOMO_CONTROLLER_PORT}"
  echo "Mihomo DNS 监听:      ${MIHOMO_DNS_LISTEN}"
  if [[ "${PROXY_CORE:-mihomo}" == "mihomo" ]]; then
    echo "MetaCubeXD:           $(bool_text "${ENABLE_METACUBEXD}")"
    echo "MetaCubeXD UI 目录:   ${MIHOMO_EXTERNAL_UI_DIR:-${MIHOMO_STATE_DIR:-/var/lib/mihomo}/ui}"
    echo "MetaCubeXD 地址:      http://${MIHOMO_CONTROLLER_HOST}:${MIHOMO_CONTROLLER_PORT}/ui/"
  fi
  echo "sing-box 包:          ${SING_BOX_PACKAGE}"
  echo "sing-box 配置来源:    ${SING_BOX_CONFIG_SOURCE:-生成基础模板}"
  echo "sing-box mixed-port:  ${SING_BOX_MIXED_PORT}"
  show_config_warnings_text
  echo "----------------------------------------------------------"
}

trim_config_value() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$1"
}

strip_optional_quotes() {
  local value="$1" first last length
  length="${#value}"
  if [[ "${length}" -ge 2 ]]; then
    first="${value:0:1}"
    last="${value:length-1:1}"
    if [[ ( "${first}" == '"' && "${last}" == '"' ) || ( "${first}" == "'" && "${last}" == "'" ) ]]; then
      value="${value:1:length-2}"
    fi
  fi
  printf "%s" "${value}"
}

add_config_load_warning() {
  CONFIG_LOAD_WARNINGS+=("$1")
}

add_config_warning() {
  CONFIG_WARNINGS+=("$1")
}

split_config_list() {
  local value="$1" item
  CONFIG_SPLIT_VALUES=()
  value="${value//,/ }"
  for item in ${value}; do
    [[ -n "${item}" ]] && CONFIG_SPLIT_VALUES+=("${item}")
  done
}

assign_config_list() {
  local key="$1"
  if [[ "${#CONFIG_SPLIT_VALUES[@]}" -eq 0 ]]; then
    case "${key}" in
      DNS_SERVERS) DNS_SERVERS=() ;;
      DNS_FALLBACK_SERVERS) DNS_FALLBACK_SERVERS=() ;;
      DNS_FOREIGN_FALLBACK_SERVERS) DNS_FOREIGN_FALLBACK_SERVERS=() ;;
      DOCKER_MIRRORS) DOCKER_MIRRORS=() ;;
      HYPRDOTS_CONFIG_MODULES) HYPRDOTS_CONFIG_MODULES=() ;;
      *) return 1 ;;
    esac
    return 0
  fi
  case "${key}" in
    DNS_SERVERS) DNS_SERVERS=("${CONFIG_SPLIT_VALUES[@]}") ;;
    DNS_FALLBACK_SERVERS) DNS_FALLBACK_SERVERS=("${CONFIG_SPLIT_VALUES[@]}") ;;
    DNS_FOREIGN_FALLBACK_SERVERS) DNS_FOREIGN_FALLBACK_SERVERS=("${CONFIG_SPLIT_VALUES[@]}") ;;
    DOCKER_MIRRORS) DOCKER_MIRRORS=("${CONFIG_SPLIT_VALUES[@]}") ;;
    HYPRDOTS_CONFIG_MODULES)
      # shellcheck disable=SC2034
      HYPRDOTS_CONFIG_MODULES=("${CONFIG_SPLIT_VALUES[@]}")
      ;;
    *) return 1 ;;
  esac
}

apply_config_assignment() {
  local key="$1" value="$2"
  if config_scalar_allowed "${key}"; then
    printf -v "${key}" "%s" "${value}"
    return 0
  fi
  if config_list_allowed "${key}"; then
    split_config_list "${value}"
    assign_config_list "${key}"
    return 0
  fi
  add_config_load_warning "配置文件忽略不支持的键：${key}"
}

load_user_config_file() {
  local config_file line key value line_no=0
  case "$(to_lower "${ARCHDEVKIT_LOAD_CONFIG_FILE:-1}")" in
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
    value="$(trim_config_value "${line#*=}")"
    value="$(strip_optional_quotes "${value}")"
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      add_config_load_warning "配置文件第 ${line_no} 行键名非法，已忽略：${key}"
      continue
    fi
    apply_config_assignment "${key}" "${value}"
  done < "${config_file}"

  # shellcheck disable=SC2034
  CONFIG_FILE_LOADED=1
}

parse_config_file_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--config-file 需要路径"
        ARCHDEVKIT_CONFIG_FILE="$2"
        ARCHDEVKIT_LOAD_CONFIG_FILE=1
        shift 2
        ;;
      --config-file=*)
        ARCHDEVKIT_CONFIG_FILE="${1#*=}"
        [[ -n "${ARCHDEVKIT_CONFIG_FILE}" ]] || die "--config-file 需要路径"
        ARCHDEVKIT_LOAD_CONFIG_FILE=1
        shift
        ;;
      --no-config-file)
        ARCHDEVKIT_LOAD_CONFIG_FILE=0
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
}

normalize_bool_var() {
  local key="$1" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "$(to_lower "${value}")" in
    1|true|yes|y|on|enable|enabled) printf -v "${key}" "%s" "1" ;;
    0|false|no|n|off|disable|disabled) printf -v "${key}" "%s" "0" ;;
    *) die "${key} 仅支持布尔值：1/0、true/false、yes/no、on/off；当前值：${value}" ;;
  esac
}

normalize_config() {
  local key
  for key in $(config_bool_keys); do
    normalize_bool_var "${key}"
  done
}

require_non_empty_config() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ -n "${value}" ]] || die "${desc} 不能为空：${key}"
}

validate_http_url_var() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "${value}" in
    http://*|https://*) ;;
    *) die "${desc} 必须是 http(s) URL：${key}=${value}" ;;
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

validate_port_var() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${desc} 必须是数字端口：${key}=${value}"
  (( value >= 1 && value <= 65535 )) || die "${desc} 端口范围必须是 1-65535：${key}=${value}"
}

validate_source_reference() {
  local key="$1" desc="$2" value
  value="${!key-}"
  [[ -n "${value}" ]] || return 0
  case "${value}" in
    http://*|https://*) return 0 ;;
  esac
  [[ -e "${value}" ]] || add_config_warning "${desc} 本地路径当前不存在，安装时会失败：${value}"
}

validate_dns_list() {
  local key="$1" desc="$2" item
  local values=()
  case "${key}" in
    DNS_SERVERS) values=("${DNS_SERVERS[@]}") ;;
    DNS_FALLBACK_SERVERS) values=("${DNS_FALLBACK_SERVERS[@]}") ;;
    DNS_FOREIGN_FALLBACK_SERVERS) values=("${DNS_FOREIGN_FALLBACK_SERVERS[@]}") ;;
    *) die "未知 DNS 列表：${key}" ;;
  esac
  [[ "${#values[@]}" -gt 0 ]] || die "${desc} 不能为空：${key}"
  for item in "${values[@]}"; do
    [[ -n "${item}" ]] || die "${desc} 中包含空值：${key}"
  done
}

validate_mihomo_dns_listen() {
  local listen="${MIHOMO_DNS_LISTEN:-}"
  [[ -n "${listen}" ]] || die "MIHOMO_DNS_LISTEN 不能为空"
  if [[ "${listen}" != *:* ]]; then
    die "MIHOMO_DNS_LISTEN 需要包含 host:port：${listen}"
  fi
  local port="${listen##*:}"
  [[ "${port}" =~ ^[0-9]+$ ]] || die "MIHOMO_DNS_LISTEN 端口必须是数字：${listen}"
  (( port >= 1 && port <= 65535 )) || die "MIHOMO_DNS_LISTEN 端口范围必须是 1-65535：${listen}"
}

validate_config() {
  CONFIG_WARNINGS=()
  if [[ "${#CONFIG_LOAD_WARNINGS[@]}" -gt 0 ]]; then
    CONFIG_WARNINGS=("${CONFIG_LOAD_WARNINGS[@]}")
  fi
  normalize_config

  case "${ARCHDEVKIT_DEFAULT_PROFILE:-workstation}" in
    base|dns|archlinuxcn|git|ops|ops-toolkit|ops_toolkit|runtime|nvim|docker|fonts|shell|zsh|desktop|hyprland|proxy|dev|workstation) ;;
    *) die "ARCHDEVKIT_DEFAULT_PROFILE 不支持：${ARCHDEVKIT_DEFAULT_PROFILE}" ;;
  esac
  case "${PROXY_CORE:-mihomo}" in
    mihomo|sing-box) ;;
    *) die "PROXY_CORE 仅支持 mihomo / sing-box：${PROXY_CORE}" ;;
  esac
  case "${SHELL_PROMPT_ENGINE:-starship}" in
    starship|powerlevel10k|p10k|basic) ;;
    *) die "SHELL_PROMPT_ENGINE 仅支持 starship / powerlevel10k / basic：${SHELL_PROMPT_ENGINE}" ;;
  esac
  case "${OS_INIT_TERMINAL_STYLE:-auto}" in
    auto|rich|simple|plain|none|off|0|false|disable|disabled) ;;
    *) die "OS_INIT_TERMINAL_STYLE 仅支持 auto / rich / simple / plain / none：${OS_INIT_TERMINAL_STYLE}" ;;
  esac
  case "${DNS_OVER_TLS:-no}" in
    no|opportunistic|yes) ;;
    *) die "DNS_OVER_TLS 仅支持 no / opportunistic / yes：${DNS_OVER_TLS}" ;;
  esac
  case "${GPU_TYPE:-auto}" in
    auto|intel|amd|nvidia|vmware|virtio|qxl|virtualbox|none) ;;
    *) die "GPU_TYPE 不支持：${GPU_TYPE}" ;;
  esac
  case "${RUNTIME_MANAGER:-mise}" in
    mise) ;;
    *) add_config_warning "当前只实现了 mise runtime 管理器，RUNTIME_MANAGER=${RUNTIME_MANAGER} 会被安装逻辑按 mise 处理" ;;
  esac
  case "${INPUT_METHOD_ENGINE:-rime}" in
    rime|pinyin) ;;
    *) die "INPUT_METHOD_ENGINE 仅支持 rime / pinyin：${INPUT_METHOD_ENGINE}" ;;
  esac

  validate_hyprland_config_mode

  if [[ "${ENABLE_DNS:-0}" -eq 1 ]]; then
    validate_dns_list DNS_SERVERS "DNS 服务器列表"
    validate_dns_list DNS_FALLBACK_SERVERS "DNS fallback 列表"
    validate_dns_list DNS_FOREIGN_FALLBACK_SERVERS "DNS 国外 fallback 列表"
  fi

  if [[ "${ENABLE_CHINA_MIRROR:-0}" -eq 1 ]]; then
    validate_http_url_var NPM_REGISTRY "npm 源"
    validate_http_url_var PIP_INDEX_URL "pip 源"
    validate_http_url_var UV_DEFAULT_INDEX "uv 源"
    validate_http_url_var NODE_MIRROR_URL "Node 下载镜像"
    validate_http_url_var GO_DOWNLOAD_MIRROR "Go 下载镜像"
  fi
  if [[ "${ENABLE_GITHUB_PROXY:-0}" -eq 1 ]]; then
    validate_http_url_var GITHUB_PROXY "GitHub 代理"
  fi
  validate_repo_url_var OPS_TOOLKIT_REPO "Ops Toolkit 仓库"
  require_non_empty_config OPS_TOOLKIT_DIR "Ops Toolkit 本地目录"
  require_non_empty_config OPS_TOOLKIT_BIN_DIR "Ops Toolkit 命令目录"
  require_non_empty_config OPS_TOOLKIT_COMMAND "Ops Toolkit 调度命令"
  [[ "${OPS_TOOLKIT_COMMAND}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "OPS_TOOLKIT_COMMAND 需要以字母或数字开头，只能包含字母、数字、点、下划线和短横线：${OPS_TOOLKIT_COMMAND}"
  validate_repo_url_var NVIM_REPO "Neovim 配置仓库"
  if [[ "${INSTALL_RIME_CONFIG:-0}" -eq 1 ]]; then
    validate_repo_url_var RIME_CONFIG_REPO "Rime 配置仓库"
  fi

  if [[ "${CONFIGURE_DOCKER_MIRRORS:-0}" -eq 1 && "${#DOCKER_MIRRORS[@]}" -eq 0 ]]; then
    die "CONFIGURE_DOCKER_MIRRORS=1 时 DOCKER_MIRRORS 不能为空"
  fi

  require_non_empty_config BROWSER_PACKAGE "浏览器安装包"
  require_non_empty_config BROWSER_APP "浏览器启动命令"

  if [[ "${PROXY_CORE:-mihomo}" == "mihomo" ]]; then
    validate_port_var MIHOMO_MIXED_PORT "Mihomo mixed-port"
    validate_port_var MIHOMO_CONTROLLER_PORT "Mihomo 控制接口"
    validate_mihomo_dns_listen
    validate_source_reference MIHOMO_CONFIG_SOURCE "Mihomo 配置来源"
    if [[ ( "${TARGET:-}" == "proxy" || ( "${TARGET:-}" =~ ^(dev|workstation)$ && "${ENABLE_PROXY:-0}" -eq 1 ) ) && \
          "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}" == "0.0.0.0" && -z "${MIHOMO_SECRET:-}" ]]; then
      add_config_warning "Mihomo 控制接口监听 0.0.0.0 且 secret 为空；这是当前默认值，但局域网可访问控制 API"
    fi
  else
    validate_port_var SING_BOX_MIXED_PORT "sing-box mixed-port"
    validate_source_reference SING_BOX_CONFIG_SOURCE "sing-box 配置来源"
  fi
}

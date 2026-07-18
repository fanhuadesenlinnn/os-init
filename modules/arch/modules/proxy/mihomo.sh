#!/usr/bin/env bash
# Mihomo 安装、配置渲染、systemd 适配和 MetaCubeXD 部署。

bool_to_yaml() {
  case "${1:-0}" in
    1|true|yes|on) printf "true" ;;
    *) printf "false" ;;
  esac
}

quote_yaml_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

mihomo_unit_file() {
  local service="${1:-${MIHOMO_SERVICE_NAME:-mihomo.service}}" unit_file

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf "/usr/lib/systemd/system/%s" "${service}"
    return 0
  fi

  unit_file="$(systemctl show -P FragmentPath "${service}" 2>/dev/null || true)"
  [[ -n "${unit_file}" ]] && printf "%s" "${unit_file}"
}

mihomo_unit_setting_value() {
  local unit_file="$1" key="$2"
  [[ -n "${unit_file}" && -r "${unit_file}" ]] || return 1
  sed -n "s/^${key}=//p" "${unit_file}" | tail -n 1
}

mihomo_unit_has_setting() {
  local unit_file="$1" pattern="$2"
  [[ -n "${unit_file}" && -r "${unit_file}" ]] || return 1
  grep -Eq "${pattern}" "${unit_file}"
}

mihomo_state_dir() {
  local service="${MIHOMO_SERVICE_NAME:-mihomo.service}" unit_file state_name

  [[ -n "${MIHOMO_STATE_DIR:-}" ]] && {
    printf "%s" "${MIHOMO_STATE_DIR}"
    return 0
  }

  unit_file="$(mihomo_unit_file "${service}")"
  if [[ -n "${unit_file}" ]]; then
    state_name="$(mihomo_unit_setting_value "${unit_file}" "StateDirectory" | awk '{print $1}')"
    if [[ -n "${state_name}" ]]; then
      if [[ "${state_name}" == /* ]]; then
        printf "%s" "${state_name}"
      else
        printf "/var/lib/%s" "${state_name}"
      fi
      return 0
    fi
  fi

  printf "/var/lib/mihomo"
}

mihomo_safe_external_ui_dir() {
  local state_dir requested
  state_dir="$(mihomo_state_dir)"
  requested="${MIHOMO_EXTERNAL_UI_DIR:-${state_dir}/ui}"

  state_dir="$(arch_require_path_within "$state_dir" /var/lib/mihomo MIHOMO_STATE_DIR)"
  arch_require_path_within "$requested" "$state_dir" MIHOMO_EXTERNAL_UI_DIR
}

warn_mihomo_exposure() {
  if [[ "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}" == "0.0.0.0" && -z "${MIHOMO_SECRET:-}" ]]; then
    log_warn "Mihomo 控制接口监听 0.0.0.0 且 MIHOMO_SECRET 为空，局域网可访问控制 API"
    log_warn "如需开放 MetaCubeXD，建议在 install_vars 设置 MIHOMO_SECRET"
  fi
}

render_mihomo_config_template() {
  local template="$1" target="$2"
  local allow_lan secret external_ui_line external_ui_dir

  warn_mihomo_exposure
  allow_lan="$(sed_escape_replacement "$(bool_to_yaml "${MIHOMO_ALLOW_LAN:-0}")")"
  secret="$(sed_escape_replacement "$(quote_yaml_string "${MIHOMO_SECRET:-}")")"
  if [[ "${ENABLE_METACUBEXD:-0}" -eq 1 ]]; then
    external_ui_dir="$(mihomo_safe_external_ui_dir)"
    external_ui_line="$(sed_escape_replacement "external-ui: ${external_ui_dir}")"
  else
    external_ui_line=""
  fi

  render_template_root_file "${template}" "${target}" 0600 \
    -e "s/__MIHOMO_MIXED_PORT__/$(sed_escape_replacement "${MIHOMO_MIXED_PORT:-7890}")/g" \
    -e "s/__MIHOMO_ALLOW_LAN__/${allow_lan}/g" \
    -e "s/__MIHOMO_BIND_ADDRESS__/$(sed_escape_replacement "${MIHOMO_BIND_ADDRESS:-127.0.0.1}")/g" \
    -e "s/__MIHOMO_CONTROLLER_HOST__/$(sed_escape_replacement "${MIHOMO_CONTROLLER_HOST:-127.0.0.1}")/g" \
    -e "s/__MIHOMO_CONTROLLER_PORT__/$(sed_escape_replacement "${MIHOMO_CONTROLLER_PORT:-9090}")/g" \
    -e "s/__MIHOMO_DNS_LISTEN__/$(sed_escape_replacement "${MIHOMO_DNS_LISTEN:-127.0.0.1:1053}")/g" \
    -e "s/__MIHOMO_SECRET_YAML__/${secret}/g" \
    -e "s/__METACUBEXD_EXTERNAL_UI_LINE__/${external_ui_line}/g"
}

render_default_mihomo_config() {
  render_mihomo_config_template "${SCRIPT_DIR}/files/mihomo/config.yaml.tpl" "$1"
}

mihomo_config_has_placeholder_subscription() {
  local config_file="$1"
  [[ -e "${config_file}" ]] || return 1

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    return 1
  fi

  if [[ -r "${config_file}" ]]; then
    grep -Fq "https://example.com/your-subscription-url" "${config_file}"
  else
    run_sudo grep -Fq "https://example.com/your-subscription-url" "${config_file}"
  fi
}

inspect_mihomo_systemd_service() {
  local service="${MIHOMO_SERVICE_NAME:-mihomo.service}" unit_file
  unit_file="$(mihomo_unit_file "${service}")"

  if [[ -z "${unit_file}" ]]; then
    log_warn "未找到 ${service} 的 systemd unit，稍后启用服务可能失败"
    return 0
  fi

  log_info "检测 Mihomo systemd unit：${unit_file}"
  if mihomo_unit_has_setting "${unit_file}" '^StateDirectory=' && \
     mihomo_unit_has_setting "${unit_file}" '^LoadCredential=.*config\.ya?ml'; then
    log_info "检测到 ${service} 使用 StateDirectory + LoadCredential，按服务运行目录校验配置"
  else
    log_warn "${service} 未使用预期的 StateDirectory + LoadCredential 模式，请留意发行版包差异"
  fi
}

mihomo_stop_failed_service() {
  local service="${MIHOMO_SERVICE_NAME:-mihomo.service}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo systemctl disable --now ${service}"
    echo "+ sudo systemctl reset-failed ${service}"
    return 0
  fi

  run_sudo systemctl disable --now "${service}" || true
  run_sudo systemctl reset-failed "${service}" || true
}

mihomo_test_config_for_service() {
  local config_file="$1" state_dir
  [[ -n "${config_file}" ]] || die "Mihomo 配置文件为空"
  state_dir="$(mihomo_state_dir)"

  state_dir="$(arch_require_path_within "$state_dir" /var/lib/mihomo MIHOMO_STATE_DIR)"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo mihomo -t -f ${config_file} -d ${state_dir}"
    return 0
  fi

  require_cmd mihomo
  run_sudo mkdir -p "${state_dir}"
  run_sudo mihomo -t -f "${config_file}" -d "${state_dir}"
}

mihomo_service_ready() {
  local config_file="${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"

  inspect_mihomo_systemd_service

  if mihomo_config_has_placeholder_subscription "${config_file}"; then
    log_warn "Mihomo 配置仍使用示例订阅地址，不能保证服务启动成功"
    log_warn "请先替换 proxy-providers.airport.url，或使用 --mihomo-config 指定自己的配置"
    mihomo_stop_failed_service
    return 1
  fi

  log_info "按 mihomo.service 的运行方式测试配置"
  if mihomo_test_config_for_service "${config_file}"; then
    return 0
  fi

  log_warn "Mihomo 配置测试失败，已跳过自动启动服务，避免 systemd 反复重启"
  log_warn "可查看详细日志：sudo journalctl -u ${MIHOMO_SERVICE_NAME:-mihomo.service} -n 80 --no-pager"
  mihomo_stop_failed_service
  return 1
}

install_mihomo() {
  local package="${MIHOMO_PACKAGE:-mihomo}"
  log_info "安装 Mihomo 核心：${package}"
  install_package_or_aur "${package}"
}

configure_mihomo() {
  local config_file="${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
  local config_dir="${MIHOMO_CONFIG_DIR:-$(dirname "${config_file}")}"

  log_info "配置 Mihomo：${config_file}"
  run_sudo mkdir -p "${config_dir}" "${config_dir}/providers" "${config_dir}/ruleset"
  if is_default_mihomo_config_source; then
    render_default_mihomo_config "${config_file}"
  elif [[ "${MIHOMO_CONFIG_SOURCE:-}" == *.tpl && "${MIHOMO_CONFIG_SOURCE:-}" != http://* && "${MIHOMO_CONFIG_SOURCE:-}" != https://* ]]; then
    render_mihomo_config_template "${MIHOMO_CONFIG_SOURCE}" "${config_file}"
  elif proxy_config_source_to_root_file "${MIHOMO_CONFIG_SOURCE:-}" "${config_file}" 0600; then
    :
  else
    render_default_mihomo_config "${config_file}"
  fi
}

install_metacubexd() {
  local package="${METACUBEXD_PACKAGE:-metacubexd-bin}"
  local source_root="${METACUBEXD_WEB_ROOT:-/usr/share/metacubexd}"
  local target_root
  target_root="$(mihomo_safe_external_ui_dir)"

  log_info "安装 MetaCubeXD 面板：${package}"
  install_package_or_aur "${package}"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo install MetaCubeXD UI ${source_root} -> ${target_root}"
    return 0
  fi

  [[ -f "${source_root}/index.html" ]] || \
    log_warn "未找到 MetaCubeXD 静态入口：${source_root}/index.html，请检查面板包安装路径"

  if [[ -f "${source_root}/index.html" ]]; then
    run_sudo rm -rf "${target_root}"
    run_sudo mkdir -p "$(dirname "${target_root}")"
    run_sudo cp -a "${source_root}" "${target_root}"
    log_info "MetaCubeXD UI 已安装到：${target_root}"
  fi
}

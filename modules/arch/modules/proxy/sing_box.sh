#!/usr/bin/env bash
# sing-box installation with a user service for normal users and a system
# service when root itself is the target user.

render_sing_box_config_template() {
  local template="$1" target="$2"

  render_template_file "${template}" "${target}" 0600 \
    -e "s/__SING_BOX_MIXED_PORT__/$(sed_escape_replacement "${SING_BOX_MIXED_PORT:-7890}")/g"
}

render_default_sing_box_config() {
  render_sing_box_config_template "${SCRIPT_DIR}/files/sing-box/config.json.tpl" "$1"
}

install_sing_box() {
  local package="${SING_BOX_PACKAGE:-sing-box}"
  log_info "安装 sing-box 核心：${package}"
  install_package_or_aur "${package}"
}

configure_sing_box() {
  local config_file="${SING_BOX_CONFIG_FILE:-${HOME}/.config/sing-box/config.json}"
  local config_dir="${SING_BOX_CONFIG_DIR:-$(dirname "${config_file}")}"
  local service_dir="${HOME}/.config/systemd/user"
  local service_file="${service_dir}/os-init-arch-sing-box.service"

  if [[ "${EUID}" -eq 0 ]]; then
    service_dir="/etc/systemd/system"
    service_file="${service_dir}/os-init-arch-sing-box.service"
  fi

  log_info "配置 sing-box：${config_file}"
  mkdir -p "${config_dir}"
  if is_default_sing_box_config_source; then
    render_default_sing_box_config "${config_file}"
  elif [[ "${SING_BOX_CONFIG_SOURCE:-}" == *.tpl && "${SING_BOX_CONFIG_SOURCE:-}" != http://* && "${SING_BOX_CONFIG_SOURCE:-}" != https://* ]]; then
    render_sing_box_config_template "${SING_BOX_CONFIG_SOURCE}" "${config_file}"
  elif proxy_config_source_to_file "${SING_BOX_CONFIG_SOURCE:-}" "${config_file}"; then
    :
  else
    render_default_sing_box_config "${config_file}"
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    run_sudo mkdir -p "${service_dir}"
  else
    mkdir -p "${service_dir}"
  fi
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${service_file}"
    return 0
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    write_root_file_from_stdin "${service_file}" 0644 <<EOF
[Unit]
Description=OS Init Arch sing-box Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${config_dir}
ExecStart=/usr/bin/sing-box run -c ${config_file}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    return 0
  fi

  backup_path "${service_file}"
  cat > "${service_file}" <<EOF
[Unit]
Description=OS Init Arch sing-box Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${config_dir}
ExecStart=/usr/bin/sing-box run -c ${config_file}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
}

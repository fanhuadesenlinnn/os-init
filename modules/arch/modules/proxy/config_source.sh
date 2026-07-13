#!/usr/bin/env bash
# Proxy 配置来源：支持本地文件、模板和远程 URL。

proxy_config_source_to_file() {
  local source="$1" target="$2" actual_source tmp_file
  [[ -n "${target}" ]] || die "代理配置目标文件为空"

  [[ -n "${source}" ]] || return 1
  actual_source="$(github_proxy_url "${source}")"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ install config ${actual_source} -> ${target}"
    return 0
  fi

  tmp_file="$(mktemp)"
  case "${actual_source}" in
    http://*|https://*)
      ensure_curl_command
      log_info "下载代理配置：${source}"
      [[ "${source}" != "${actual_source}" ]] && log_info "实际下载地址：${actual_source}"
      curl -fL "${actual_source}" -o "${tmp_file}" || {
        rm -f "${tmp_file}"
        die "下载代理配置失败：${source}"
      }
      ;;
    *)
      [[ -f "${actual_source}" ]] || die "代理配置文件不存在：${source}"
      cp -a "${actual_source}" "${tmp_file}"
      ;;
  esac

  install_file_from_temp "${tmp_file}" "${target}" 0600
  rm -f "${tmp_file}"
}

is_default_sing_box_config_source() {
  case "${SING_BOX_CONFIG_SOURCE:-}" in
    ""|"${SCRIPT_DIR}/files/sing-box/config.json.tpl")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

#!/usr/bin/env bash
# Hyprland 模板与 hyprdots 配置安装能力。

render_hyprland_template() {
  local template="$1" target="$2" tmp_file
  local browser_app terminal_app file_manager app_launcher

  [[ -f "${template}" ]] || die "Hyprland 模板不存在：${template}"
  [[ -n "${target}" ]] || die "Hyprland 模板目标为空"

  browser_app="$(sed_escape_replacement "${BROWSER_APP:-google-chrome-stable}")"
  terminal_app="$(sed_escape_replacement "${TERMINAL_APP:-alacritty}")"
  file_manager="$(sed_escape_replacement "${FILE_MANAGER:-yazi}")"
  app_launcher="$(sed_escape_replacement "${APP_LAUNCHER:-rofi}")"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ render ${template} -> ${target}"
    return 0
  fi

  mkdir -p "$(dirname "${target}")"
  tmp_file="$(mktemp)"
  sed \
    -e "s/__TERMINAL_APP__/${terminal_app}/g" \
    -e "s/__FILE_MANAGER__/${file_manager}/g" \
    -e "s/__APP_LAUNCHER__/${app_launcher}/g" \
    -e "s/__BROWSER_APP__/${browser_app}/g" \
    "${template}" > "${tmp_file}"

  backup_path "${target}"
  install -m 0644 "${tmp_file}" "${target}"
  rm -f "${tmp_file}"
}

install_hyprland_templates() {
  local template_dir="${SCRIPT_DIR}/files/hyprland"

  render_hyprland_template "${template_dir}/hyprland.conf.tpl" "${HOME}/.config/hypr/hyprland.conf"
  render_hyprland_template "${template_dir}/waybar.config.tpl" "${HOME}/.config/waybar/config"
  render_hyprland_template "${template_dir}/waybar.style.css.tpl" "${HOME}/.config/waybar/style.css"
  render_hyprland_template "${template_dir}/mako.config.tpl" "${HOME}/.config/mako/config"
  render_hyprland_template "${template_dir}/wofi.config.tpl" "${HOME}/.config/wofi/config"
  render_hyprland_template "${template_dir}/alacritty.toml.tpl" "${HOME}/.config/alacritty/alacritty.toml"
}

generate_hyprland_config() {
  case "${HYPRLAND_CONFIG_MODE:-hyprdots}" in
    hyprdots)
      install_hyprdots_config
      ;;
    template)
      log_info "生成 Hyprland 默认配置"
      install_hyprland_templates
      ;;
    skip)
      log_warn "当前 Hyprland 配置模式为 skip，跳过配置安装"
      ;;
    *)
      die "未知 Hyprland 配置模式：${HYPRLAND_CONFIG_MODE}"
      ;;
  esac
}

hyprdots_module_target() {
  printf '%s/.config/%s' "${HOME}" "$1"
}

install_hyprdots_config() {
  local source_root="${HYPRDOTS_SOURCE_DIR:-${SCRIPT_DIR}/files/hyprdots}"
  local module

  [[ -d "${source_root}" ]] || die "hyprdots 配置源不存在：${source_root}"

  log_info "安装 hyprdots 配置模块，来源提交：${HYPRDOTS_SOURCE_COMMIT:-unknown}"
  for module in "${HYPRDOTS_CONFIG_MODULES[@]}"; do
    install_hyprdots_config_module "${source_root}" "${module}"
  done

  disable_hyprland_lua_entrypoint
  install_hyprdots_local_bin "${source_root}"
  ensure_hyprdots_wallpaper_dir
  ensure_hyprpaper_config
  apply_hyprdots_runtime_overrides
  ensure_waybar_runtime_files
}

install_hyprdots_config_module() {
  local source_root="$1" module="$2"
  local source="${source_root}/${module}"
  local target
  target="$(hyprdots_module_target "${module}")"

  if [[ ! -d "${source}" ]]; then
    log_warn "hyprdots 模块不存在，跳过：${module}"
    return 0
  fi

  log_info "安装 hyprdots 配置模块：${module}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ backup ${target}"
    echo "+ cp -a ${source} ${target}"
    return 0
  fi

  mkdir -p "${HOME}/.config"
  backup_path "${target}"
  cp -a "${source}" "${target}"
  make_hyprdots_scripts_executable "${target}"
}

disable_hyprland_lua_entrypoint() {
  local lua_entry="${HOME}/.config/hypr/hyprland.lua"
  local disabled_entry="${lua_entry}.disabled"

  [[ -e "${lua_entry}" || -L "${lua_entry}" ]] || return 0

  log_warn "检测到 Hyprland Lua 入口配置，禁用它以使用 hyprland.conf 启动：${lua_entry}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ mv ${lua_entry} ${disabled_entry}"
    return 0
  fi

  backup_path "${disabled_entry}"
  mv "${lua_entry}" "${disabled_entry}"
}

backup_legacy_terminal_configs() {
  local kitty_config="${HOME}/.config/kitty"

  [[ -e "${kitty_config}" || -L "${kitty_config}" ]] || return 0

  log_warn "检测到旧版 Kitty 配置，已切换到 Alacritty/foot，将备份并停用：${kitty_config}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ backup ${kitty_config}"
    return 0
  fi

  backup_path "${kitty_config}"
}

make_hyprdots_scripts_executable() {
  local target="$1"
  [[ -d "${target}" ]] || return 0
  find "${target}" -type f -name "*.sh" -exec chmod +x {} +
}

install_hyprdots_local_bin() {
  local source_root="$1"
  local source="${source_root}/bin"
  local target="${HYPRDOTS_LOCAL_BIN_DIR:-${HOME}/.local/bin}"

  [[ -d "${source}" ]] || {
    log_warn "hyprdots bin 目录不存在，跳过：${source}"
    return 0
  }

  log_info "安装 hyprdots 本地脚本：${target}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ mkdir -p ${target}"
    echo "+ cp -a ${source}/. ${target}/"
    echo "+ chmod +x ${target}/*"
    return 0
  fi

  mkdir -p "${target}"
  cp -a "${source}/." "${target}/"
  find "${target}" -maxdepth 1 -type f -exec chmod +x {} +
}

ensure_hyprdots_wallpaper_dir() {
  local dir="${HYPRDOTS_WALLPAPER_DIR:-${HOME}/Pictures/Wallpaper}"
  log_info "确保壁纸目录存在：${dir}"
  run_cmd mkdir -p "${dir}"
}

ensure_hyprpaper_config() {
  local config_path="${HOME}/.config/hypr/hyprpaper.conf"

  [[ -f "${config_path}" ]] && return 0

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${config_path}"
    return 0
  fi

  mkdir -p "$(dirname "${config_path}")"
  cat > "${config_path}" <<'EOF'
splash = false
EOF
}

hyprdots_menu_command() {
  case "${APP_LAUNCHER:-rofi}" in
    rofi) printf 'rofi -show run' ;;
    wofi) printf 'wofi --show drun' ;;
    *) printf '%s' "${APP_LAUNCHER}" ;;
  esac
}

apply_hyprdots_runtime_overrides() {
  local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
  local terminal file_manager menu browser note_app

  [[ "${DRY_RUN:-0}" -eq 1 ]] && {
    echo "+ render OS Init Arch overrides into ${hypr_conf}"
    return 0
  }

  terminal="$(sed_escape_replacement "${TERMINAL_APP:-alacritty}")"
  file_manager="$(sed_escape_replacement "${FILE_MANAGER:-yazi}")"
  menu="$(sed_escape_replacement "$(hyprdots_menu_command)")"
  browser="$(sed_escape_replacement "${BROWSER_APP:-google-chrome-stable}")"
  if [[ "${INSTALL_HYPRDOTS_OBSIDIAN:-0}" -eq 1 ]]; then
    note_app="$(sed_escape_replacement "obsidian")"
  else
    note_app="$(sed_escape_replacement ":")"
  fi

  if [[ -f "${hypr_conf}" ]]; then
    local tmp_file
    tmp_file="$(mktemp)"
    sed \
      -e "s/^[$]terminal = .*/\$terminal = ${terminal}/" \
      -e "s/^[$]fileManager = .*/\$fileManager = ${file_manager}/" \
      -e "s/^[$]menu = .*/\$menu = ${menu}/" \
      -e "s/^[$]browser = .*/\$browser = ${browser}/" \
      -e "s/^[$]note = .*/\$note = ${note_app}/" \
      "${hypr_conf}" > "${tmp_file}"

    if [[ "${INSTALL_HYPRDOTS_OBSIDIAN:-0}" -ne 1 ]]; then
      sed \
        -e '/^windowrule = match:class obsidian/s/^/# /' \
        "${tmp_file}" > "${tmp_file}.obsidian"
      mv "${tmp_file}.obsidian" "${tmp_file}"
    fi

    if [[ "${ENABLE_FCITX5:-0}" -ne 1 ]]; then
      sed \
        -e '/^exec-once = fcitx5 -d/s/^/# /' \
        -e '/^[[:space:]]*source = .*os-init-fcitx5\.conf/s/^/# /' \
        "${tmp_file}" > "${tmp_file}.fcitx"
      mv "${tmp_file}.fcitx" "${tmp_file}"
    fi

    install -m 0644 "${tmp_file}" "${hypr_conf}"
    rm -f "${tmp_file}"
  fi
}

ensure_waybar_runtime_files() {
  local waybar_dir="${HOME}/.config/waybar"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ link ${waybar_dir}/config -> config_new.jsonc"
    echo "+ link ${waybar_dir}/config.jsonc -> config_new.jsonc"
    echo "+ link ${waybar_dir}/style.css -> style_new.css"
    return 0
  fi

  if [[ -d "${waybar_dir}" ]]; then
    (
      cd "${waybar_dir}" || return 0
      [[ -f config_new.jsonc ]] && ln -sfn config_new.jsonc config
      [[ -f config_new.jsonc ]] && ln -sfn config_new.jsonc config.jsonc
      [[ -f style_new.css ]] && ln -sfn style_new.css style.css
    )
  fi
}

#!/usr/bin/env bash
# 安装计划生成与展示：目标展开、计划依赖判断和 plan 输出。

plan_has_module() {
  local modules_text="$1" wanted m
  wanted="$(module_key "$2")"
  for m in ${modules_text}; do
    [[ "$(module_key "${m}")" == "${wanted}" ]] && return 0
  done
  return 1
}

append_plan_module() {
  local modules_text="$1" module="$2" wanted existing
  wanted="$(module_key "${module}")"
  for existing in ${modules_text}; do
    [[ "$(module_key "${existing}")" == "${wanted}" ]] && {
      echo "${modules_text}"
      return 0
    }
  done

  if [[ -z "${modules_text}" ]]; then
    echo "${wanted}"
  else
    echo "${modules_text} ${wanted}"
  fi
}

modules_for_shell() {
  local modules=""
  if shell_needs_fonts; then
    modules="$(append_plan_module "${modules}" "fonts")"
  fi
  modules="$(append_plan_module "${modules}" "shell")"
  echo "${modules}"
}

modules_for_desktop() {
  local modules=""
  if desktop_needs_archlinuxcn; then
    modules="$(append_plan_module "${modules}" "archlinuxcn")"
  fi
  if desktop_needs_fonts; then
    modules="$(append_plan_module "${modules}" "fonts")"
  fi
  modules="$(append_plan_module "${modules}" "desktop")"
  echo "${modules}"
}

modules_for_proxy() {
  local modules=""
  if proxy_needs_archlinuxcn; then
    modules="$(append_plan_module "${modules}" "archlinuxcn")"
  fi
  modules="$(append_plan_module "${modules}" "proxy")"
  echo "${modules}"
}

modules_for_dev() {
  local module modules=""

  modules="$(append_plan_module "${modules}" "base")"
  if [[ "${INSTALL_ARCHLINUXCN:-0}" -eq 1 ]]; then
    modules="$(append_plan_module "${modules}" "archlinuxcn")"
  fi
  if [[ "${ENABLE_DNS:-0}" -eq 1 ]]; then
    modules="$(append_plan_module "${modules}" "dns")"
  fi
  modules="$(append_plan_module "${modules}" "git")"
  if [[ "${ENABLE_OPS_TOOLKIT:-0}" -eq 1 ]]; then
    modules="$(append_plan_module "${modules}" "ops-toolkit")"
  fi
  modules="$(append_plan_module "${modules}" "runtime")"
  modules="$(append_plan_module "${modules}" "nvim")"
  modules="$(append_plan_module "${modules}" "docker")"
  modules="$(append_plan_module "${modules}" "fonts")"
  modules="$(append_plan_module "${modules}" "shell")"

  if [[ "${ENABLE_PROXY:-0}" -eq 1 ]]; then
    for module in $(modules_for_proxy); do
      modules="$(append_plan_module "${modules}" "${module}")"
    done
  fi

  echo "${modules}"
}

modules_for_workstation() {
  local module modules

  modules="$(modules_for_dev)"
  for module in $(modules_for_desktop); do
    modules="$(append_plan_module "${modules}" "${module}")"
  done

  echo "${modules}"
}

modules_for_target() {
  case "$1" in
    base|dns|archlinuxcn|git|ops|ops-toolkit|ops_toolkit|runtime|nvim|docker|fonts) module_key "$1" ;;
    shell|zsh) modules_for_shell ;;
    proxy) modules_for_proxy ;;
    desktop|hyprland) modules_for_desktop ;;
    dev) modules_for_dev ;;
    workstation) modules_for_workstation ;;
    *) die "未知安装目标：$1" ;;
  esac
}

plan_uses_github_proxy() {
  local modules_text="$1"

  plan_has_module "${modules_text}" "nvim" && return 0
  plan_has_module "${modules_text}" "ops-toolkit" && return 0
  if plan_has_module "${modules_text}" "shell" && shell_needs_repo_clone; then
    return 0
  fi
  if plan_has_module "${modules_text}" "desktop" && desktop_needs_rime_repo; then
    return 0
  fi

  return 1
}

plan_needs_git_command() {
  local modules_text="$1"

  plan_has_module "${modules_text}" "nvim" && return 0
  plan_has_module "${modules_text}" "ops-toolkit" && return 0
  if plan_has_module "${modules_text}" "shell" && shell_needs_repo_clone; then
    return 0
  fi
  if plan_has_module "${modules_text}" "desktop" && desktop_needs_rime_repo; then
    return 0
  fi

  return 1
}

show_plan_json() {
  local title="$1" modules_text="$2" module first=1
  printf '{'
  json_metadata_fields "plan"; printf ','
  printf '"target":'; json_string "${title}"; printf ','
  printf '"stateEnabled":'; json_bool "$(state_enabled && echo 1 || echo 0)"; printf ','
  printf '"force":'; json_bool "${FORCE_INSTALL}"; printf ','
  printf '"stateDir":'; json_string "$(state_root)"; printf ','
  printf '"warnings":'; json_warnings_array; printf ','
  printf '"modules":['
  for module in ${modules_text}; do
    [[ "${first}" -eq 1 ]] || printf ','
    first=0
    printf '{"name":'; json_string "$(module_display_key "${module}")"
    printf ',"key":'; json_string "$(module_key "${module}")"
    printf ',"description":'; json_string "$(module_desc "${module}")"
    printf '}'
  done
  printf ']}'
  printf '\n'
}

show_plan() {
  local title="$1" modules_text="$2"
  if [[ "${OUTPUT_JSON:-0}" -eq 1 ]]; then
    show_plan_json "${title}" "${modules_text}"
    return 0
  fi

  echo "----------------------------------------------------------"
  echo "[本次安装计划]"
  echo "安装目标: ${title}"
  echo "状态目录: $(state_root)"
  echo "模块状态: $(state_enabled && echo "启用" || echo "关闭")"
  echo "强制重跑: $(bool_text "${FORCE_INSTALL}")"
  echo "恢复模式: $(bool_text "${RESUME_INSTALL}")"
  show_config_warnings_text
  echo
  echo "将执行模块:"
  local m
  for m in ${modules_text}; do
    echo "  - $(module_display_key "${m}") ($(module_desc "${m}"))"
  done
  echo
  echo "主要影响:"
  local impact
  for m in ${modules_text}; do
    while IFS= read -r impact; do
      [[ -n "${impact}" ]] || continue
      echo "  - $(module_display_key "${m}"): ${impact}"
    done < <(module_impacts "${m}")
  done
  echo
  echo "关键配置:"
  echo "  软件安装:         按模块批量执行 pacman -S --needed，缺包再兜底 archlinuxcn/AUR"
  if plan_has_module "${modules_text}" "base"; then
    echo "  系统更新:         base 模块会刷新并执行 pacman -Syu"
    echo "  基础工具:         $(base_packages)"
    echo "  AUR 助手:         优先使用 paru，同时安装 yay 供手动使用"
  fi
  if plan_has_module "${modules_text}" "archlinuxcn"; then
    echo "  archlinuxcn 源:   ${ARCHLINUXCN_SERVER}"
    echo "  mirrorlist 包:    $(bool_text "${INSTALL_ARCHLINUXCN_MIRRORLIST}")"
  fi
  if plan_has_module "${modules_text}" "dns"; then
    echo "  系统 DNS:         systemd-resolved"
    echo "  DNS 服务器:       ${DNS_SERVERS[*]}"
    echo "  DNS fallback:     ${DNS_FALLBACK_SERVERS[*]}"
    echo "  DNS 国外 fallback: ${DNS_FOREIGN_FALLBACK_SERVERS[*]}"
    echo "  DNSOverTLS:       ${DNS_OVER_TLS}"
  fi
  if plan_has_module "${modules_text}" "git"; then
    echo "  Git 默认分支:     main"
    echo "  GitHub CLI:       安装 gh，登录需稍后手动执行 gh auth login"
  fi
  if plan_has_module "${modules_text}" "runtime"; then
    echo "  系统运行时:       pacman 安装 nodejs/npm/python/python-pip/go"
    echo "  系统包:           mise nodejs npm python python-pip go$( [[ "${ENABLE_COREPACK:-0}" -eq 1 ]] && printf ' corepack' )"
    echo "  管理工具:         ${RUNTIME_MANAGER}（只配置，不默认执行 mise use）"
    echo "  mise 目标版本:    node ${NODE_VERSION} / python ${PYTHON_VERSION} / go ${GO_VERSION}"
    echo "  npm 目标版本:     ${NPM_VERSION}（仅保留配置兼容）"
    echo "  npm 源:           ${NPM_REGISTRY}"
    echo "  pip 源:           ${PIP_INDEX_URL}"
    echo "  Node 下载镜像:    ${NODE_MIRROR_URL}（手动 mise use）"
    echo "  Go 下载镜像:      ${GO_DOWNLOAD_MIRROR}（手动 mise use）"
    echo "  Python 下载镜像:  ${PYTHON_BUILD_MIRROR_URL}（手动 mise use）"
    echo "  pyenv 实际仓库:   $(mise_pyenv_repo_url)"
    echo "  Corepack:         $(bool_text "${ENABLE_COREPACK}")"
  fi
  if plan_uses_github_proxy "${modules_text}"; then
    echo "  GitHub 代理:      $(bool_text "${ENABLE_GITHUB_PROXY}")"
    echo "  GitHub 代理地址:  ${GITHUB_PROXY}"
  fi
  if plan_needs_git_command "${modules_text}" && \
    ! plan_has_module "${modules_text}" "git" && \
    ! plan_has_module "${modules_text}" "base"; then
    echo "  Git 命令依赖:     如缺失会按需安装 git 包"
  fi
  if plan_has_module "${modules_text}" "ops-toolkit"; then
    echo "  Ops Toolkit 仓库: ${OPS_TOOLKIT_REPO}"
    echo "  Ops Toolkit 实际: $(github_proxy_url "${OPS_TOOLKIT_REPO}")"
    echo "  Ops Toolkit 目录: ${OPS_TOOLKIT_DIR}"
    echo "  Ops 命令入口:     ${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}"
  fi
  if plan_has_module "${modules_text}" "nvim"; then
    echo "  Neovim 仓库:      ${NVIM_REPO}"
    echo "  Neovim 实际下载:  $(github_proxy_url "${NVIM_REPO}")"
    echo "  插件同步:         $(bool_text "${SYNC_NVIM_PLUGINS}")"
  fi
  if plan_has_module "${modules_text}" "docker"; then
    echo "  Docker 服务:      $(bool_text "${ENABLE_DOCKER_SERVICE}")"
    echo "  加入 docker 组:   $(bool_text "${ADD_USER_TO_DOCKER_GROUP}")"
    echo "  Docker 镜像源:    $(bool_text "${CONFIGURE_DOCKER_MIRRORS}")"
  fi
  if plan_has_module "${modules_text}" "fonts"; then
    echo "  中文/Emoji 字体:  $(bool_text "${INSTALL_CN_FONTS}")"
    echo "  Nerd Font:        $(bool_text "${INSTALL_NERD_FONTS}")"
    echo "  Monaco 字体:      $(bool_text "${INSTALL_MONACO_FONT}")"
  fi
  if plan_has_module "${modules_text}" "shell"; then
    echo "  Oh My Zsh:        $(bool_text "${INSTALL_OH_MY_ZSH}")"
    echo "  Powerlevel10k:    $(bool_text "${INSTALL_POWERLEVEL10K}")"
    echo "  p10k 配置:        $(bool_text "${INSTALL_P10K_CONFIG}")"
    echo "  切换默认 shell:   $(bool_text "${SET_ZSH_AS_DEFAULT}")"
  fi
  if plan_has_module "${modules_text}" "desktop"; then
    echo "  Hyprland SDDM:    $(bool_text "${ENABLE_SDDM}")"
    echo "  GPU 类型:         ${GPU_TYPE}"
    echo "  VMware 软件渲染:  $(bool_text "${VMWARE_FORCE_SOFTWARE_RENDERER:-1}")"
    echo "  VM 动态分辨率:    $(bool_text "${VM_HYPRLAND_DYNAMIC_RESIZE:-1}")"
    echo "  VM 低延迟配置:    $(bool_text "${VM_HYPRLAND_LOW_LATENCY:-1}")"
    echo "  Hyprland 配置:    ${HYPRLAND_CONFIG_MODE}"
    if hyprdots_mode_enabled; then
      echo "  hyprdots 提交:    ${HYPRDOTS_SOURCE_COMMIT:-unknown}"
      echo "  Obsidian:         $(bool_text "${INSTALL_HYPRDOTS_OBSIDIAN}")"
    fi
    echo "  Neovide:          安装并写入 ~/.local/bin/neovide 包装命令"
    echo "  浏览器包/命令:    ${BROWSER_PACKAGE} / ${BROWSER_APP}"
    echo "  输入法:           Fcitx5 $(bool_text "${ENABLE_FCITX5}") / ${INPUT_METHOD_ENGINE}"
    if [[ "${INPUT_METHOD_ENGINE:-rime}" == "rime" ]]; then
      echo "  Rime 方案:        ${RIME_SCHEMA}"
      echo "  Rime 配置:        $(bool_text "${INSTALL_RIME_CONFIG}") / ${RIME_CONFIG_REPO:-未设置}"
    fi
  fi
  if plan_has_module "${modules_text}" "proxy"; then
    echo "  Proxy 核心:       ${PROXY_CORE}"
    echo "  自动启用服务:     $(bool_text "${PROXY_AUTO_ENABLE_SERVICE}")"
    if [[ "${PROXY_CORE:-mihomo}" == "mihomo" ]]; then
      echo "  Mihomo 配置:      ${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
      echo "  Mihomo 服务:      ${MIHOMO_SERVICE_NAME:-mihomo.service}"
      echo "  规则源:           原始 URL（不配置代理前缀）"
      echo "  MetaCubeXD:       $(bool_text "${ENABLE_METACUBEXD}")"
    else
      echo "  sing-box 配置:    ${SING_BOX_CONFIG_FILE:-${HOME}/.config/sing-box/config.json}"
      echo "  sing-box 服务:    archdevkit-sing-box.service"
    fi
  fi
  echo "----------------------------------------------------------"
}

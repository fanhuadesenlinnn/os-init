#!/usr/bin/env bash
# 模块注册表：集中维护模块名称、描述、影响范围、状态指纹、校验和执行入口。

module_desc() {
  case "$(module_key "$1")" in
    base) echo "基础环境" ;;
    dns) echo "系统 DNS" ;;
    archlinuxcn) echo "archlinuxcn 软件源" ;;
    git) echo "Git / GitHub CLI" ;;
    ops_toolkit) echo "Ops Toolkit 运维脚本命令" ;;
    runtime) echo "系统 Node/npm/Python/Go + mise 版本管理器" ;;
    nvim) echo "Neovim + 个人配置" ;;
    docker) echo "Docker / Compose" ;;
    fonts) echo "字体环境" ;;
    shell_zsh) echo "Zsh / Oh My Zsh / Powerlevel10k" ;;
    desktop_hyprland) echo "Hyprland 桌面环境" ;;
    proxy) echo "Proxy 代理环境" ;;
    *) echo "$1" ;;
  esac
}

module_key() {
  case "$1" in
    ops|ops-toolkit|ops_toolkit) echo "ops_toolkit" ;;
    shell|zsh) echo "shell_zsh" ;;
    desktop|hyprland) echo "desktop_hyprland" ;;
    *) echo "$1" ;;
  esac
}

module_display_key() {
  case "$(module_key "$1")" in
    shell_zsh) echo "shell" ;;
    desktop_hyprland) echo "desktop" ;;
    ops_toolkit) echo "ops-toolkit" ;;
    *) module_key "$1" ;;
  esac
}

all_modules() {
  echo "base dns archlinuxcn git ops_toolkit runtime nvim docker fonts shell_zsh proxy desktop_hyprland"
}

module_impacts() {
  case "$(module_key "$1")" in
    base)
      echo "刷新 pacman 数据库并安装基础命令行工具"
      echo "paru/yay AUR 助手"
      ;;
    dns)
      echo "/etc/systemd/resolved.conf.d/90-archdevkit-dns.conf"
      echo "/etc/NetworkManager/conf.d/90-archdevkit-dns.conf"
      echo "/etc/resolv.conf"
      echo "systemd-resolved.service"
      ;;
    archlinuxcn)
      echo "/etc/pacman.conf"
      echo "archlinuxcn-keyring / archlinuxcn-mirrorlist-git"
      ;;
    git)
      echo "全局 git config"
      echo "git / github-cli / openssh"
      ;;
    ops_toolkit)
      echo "${OPS_TOOLKIT_DIR}"
      echo "${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}"
      echo "${OPS_TOOLKIT_BIN_DIR}/<script-name>"
      ;;
    runtime)
      echo "${HOME}/.bashrc"
      echo "${HOME}/.zshrc"
      echo "${HOME}/.config/archdevkit/mise-china.env"
      echo "nodejs / npm / python / go / mise"
      ;;
    nvim)
      echo "${NVIM_CONFIG_DIR}"
      ;;
    docker)
      echo "/etc/docker/daemon.json"
      echo "docker.service"
      echo "docker 用户组"
      ;;
    fonts)
      echo "系统字体包和 fontconfig"
      echo "${HOME}/.config/gtk-3.0/settings.ini"
      echo "${HOME}/.config/gtk-4.0/settings.ini"
      ;;
    shell_zsh)
      echo "${HOME}/.zshrc"
      echo "${HOME}/.p10k.zsh"
      echo "默认 shell"
      ;;
    proxy)
      case "${PROXY_CORE:-mihomo}" in
        mihomo)
          echo "${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}"
          echo "${MIHOMO_EXTERNAL_UI_DIR:-${MIHOMO_STATE_DIR:-/var/lib/mihomo}/ui}"
          echo "${MIHOMO_SERVICE_NAME:-mihomo.service}"
          ;;
        sing-box)
          echo "${SING_BOX_CONFIG_FILE:-${HOME}/.config/sing-box/config.json}"
          echo "${HOME}/.config/systemd/user/archdevkit-sing-box.service"
          ;;
      esac
      echo "${HOME}/.bashrc / ${HOME}/.zshrc proxy env template"
      ;;
    desktop_hyprland)
      echo "${HOME}/.config/hypr"
      echo "${HOME}/.config/waybar / rofi / dunst / yazi / btop / alacritty"
      echo "${HOME}/.local/bin"
      echo "sddm.service / guest agent services"
      ;;
  esac
}

module_config_fingerprint() {
  local module tmux_config
  module="$(module_key "$1")"
  {
    printf 'module=%s\n' "${module}"
    case "${module}" in
      base)
        printf 'packages=%s\n' "$(base_packages)"
        printf 'aur_helpers=paru+yay\n'
        tmux_config="${SCRIPT_DIR}/files/tmux/tmux.conf"
        if [[ -f "${tmux_config}" ]]; then
          printf 'tmux_config=%s\n' "$(sha256sum "${tmux_config}" | awk '{print $1}')"
        else
          printf 'tmux_config=missing\n'
        fi
        ;;
      dns)
        printf 'dns=%s\n' "${DNS_SERVERS[*]}"
        printf 'fallback=%s\n' "${DNS_FALLBACK_SERVERS[*]} ${DNS_FOREIGN_FALLBACK_SERVERS[*]}"
        printf 'dot=%s\n' "${DNS_OVER_TLS:-no}"
        ;;
      archlinuxcn)
        printf 'server=%s\n' "${ARCHLINUXCN_SERVER}"
        printf 'mirrorlist=%s\n' "${INSTALL_ARCHLINUXCN_MIRRORLIST:-0}"
        ;;
      runtime)
        printf 'runtime=%s\nnode=%s\npython=%s\ngo=%s\nnpm=%s\n' \
          "${RUNTIME_MANAGER}" "${NODE_VERSION}" "${PYTHON_VERSION}" "${GO_VERSION}" "${NPM_VERSION}"
        printf 'mirrors=%s|%s|%s\n' "${NODE_MIRROR_URL}" "${GO_DOWNLOAD_MIRROR}" "${PYTHON_BUILD_MIRROR_URL}"
        ;;
      ops_toolkit)
        printf 'repo=%s\nbranch=%s\ndir=%s\nbin=%s\ncommand=%s\n' \
          "${OPS_TOOLKIT_REPO}" "${OPS_TOOLKIT_BRANCH:-}" "${OPS_TOOLKIT_DIR}" "${OPS_TOOLKIT_BIN_DIR}" "${OPS_TOOLKIT_COMMAND}"
        ;;
      nvim)
        printf 'repo=%s\nbranch=%s\nsync=%s\n' "${NVIM_REPO}" "${NVIM_BRANCH:-}" "${SYNC_NVIM_PLUGINS:-0}"
        ;;
      docker)
        printf 'service=%s\ngroup=%s\nmirrors=%s\n' \
          "${ENABLE_DOCKER_SERVICE:-0}" "${ADD_USER_TO_DOCKER_GROUP:-0}" "${DOCKER_MIRRORS[*]}"
        ;;
      fonts)
        printf 'cn=%s\nnerd=%s\nmonaco=%s\n' \
          "${INSTALL_CN_FONTS:-0}" "${INSTALL_NERD_FONTS:-0}" "${INSTALL_MONACO_FONT:-0}"
        ;;
      shell_zsh)
        printf 'ohmyzsh=%s\np10k=%s\nplugins=%s\n' \
          "${INSTALL_OH_MY_ZSH:-0}" "${INSTALL_POWERLEVEL10K:-0}" "${ZSH_PLUGINS:-}"
        ;;
      proxy)
        printf 'core=%s\nmihomo=%s\nsingbox=%s\nmetacubexd=%s\n' \
          "${PROXY_CORE:-mihomo}" "${MIHOMO_CONFIG_SOURCE:-}" "${SING_BOX_CONFIG_SOURCE:-}" "${ENABLE_METACUBEXD:-0}"
        ;;
      desktop_hyprland)
        printf 'gpu=%s\nmode=%s\nsddm=%s\nbrowser=%s\nrime=%s\n' \
          "${GPU_TYPE}" "${HYPRLAND_CONFIG_MODE}" "${ENABLE_SDDM:-0}" "${BROWSER_PACKAGE}/${BROWSER_APP}" "${RIME_SCHEMA}"
        ;;
    esac
  } | sha256sum | awk '{print $1}'
}

module_quick_verify() {
  local module
  module="$(module_key "$1")"
  case "${module}" in
    base)
      need_cmd git && need_cmd curl && need_cmd jq && need_cmd rg && \
        need_cmd tmux && [[ -f "${HOME}/.tmux.conf" ]]
      ;;
    dns) [[ -f /etc/systemd/resolved.conf.d/90-archdevkit-dns.conf ]] ;;
    archlinuxcn) [[ -r /etc/pacman.conf ]] && grep -q '^\[archlinuxcn\]' /etc/pacman.conf ;;
    git) need_cmd git && need_cmd gh ;;
    ops_toolkit) [[ -d "${OPS_TOOLKIT_DIR}/.git" && -x "${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" ]] ;;
    runtime) need_cmd mise && need_cmd node && need_cmd npm && need_cmd python && need_cmd go ;;
    nvim) need_cmd nvim && [[ -d "${NVIM_CONFIG_DIR}" ]] ;;
    docker) need_cmd docker ;;
    fonts) need_cmd fc-cache ;;
    shell_zsh) need_cmd zsh && [[ -f "${HOME}/.zshrc" ]] ;;
    proxy)
      case "${PROXY_CORE:-mihomo}" in
        mihomo) need_cmd mihomo && [[ -e "${MIHOMO_CONFIG_FILE:-/etc/mihomo/config.yaml}" ]] ;;
        sing-box) need_cmd sing-box && [[ -e "${SING_BOX_CONFIG_FILE:-${HOME}/.config/sing-box/config.json}" ]] ;;
      esac
      ;;
    desktop_hyprland) need_cmd Hyprland && [[ -d "${HOME}/.config/hypr" ]] ;;
    *) return 1 ;;
  esac
}

module_install_func() {
  case "$(module_key "$1")" in
    base) install_base ;;
    dns) install_dns_env ;;
    archlinuxcn) install_archlinuxcn ;;
    git) install_git_env ;;
    ops_toolkit) install_ops_toolkit ;;
    runtime) install_runtime_env ;;
    nvim) install_nvim_env ;;
    docker) install_docker_env ;;
    fonts) install_fonts ;;
    shell_zsh) install_shell_zsh ;;
    desktop_hyprland) install_desktop_hyprland ;;
    proxy) install_proxy_env ;;
    *) die "未知模块：$1" ;;
  esac
}

menu_target_overview() {
  echo
  echo "[可安装模块]"
  printf "  %-12s %s\n" "base" "基础环境：编译依赖、同步工具、网络/IO 排障、现代 CLI 工具和 paru/yay"
  printf "  %-12s %s\n" "dns" "系统 DNS：配置 systemd-resolved、NetworkManager DNS 后端和国内/国外 fallback DNS"
  printf "  %-12s %s\n" "archlinuxcn" "软件源：启用 archlinuxcn 源、keyring 和可选 mirrorlist"
  printf "  %-12s %s\n" "git" "Git 环境：安装 git、gh、openssh，并写入基础 Git 配置"
  printf "  %-12s %s\n" "ops-toolkit" "运维脚本：克隆 ops-toolkit，并写入稳定命令入口"
  printf "  %-12s %s\n" "runtime" "开发运行时：安装 nodejs、npm、python、go、mise、corepack，并配置国内镜像"
  printf "  %-12s %s\n" "nvim" "Neovim：安装 Neovim，拉取个人配置，并按需同步插件"
  printf "  %-12s %s\n" "docker" "Docker：安装 docker/compose，配置镜像源、服务和用户组"
  printf "  %-12s %s\n" "fonts" "字体：中文字体、Emoji、Nerd Font、Monaco 和 fontconfig/GTK 字体设置"
  printf "  %-12s %s\n" "shell" "Shell：安装 Zsh、Oh My Zsh、Powerlevel10k、插件和默认 shell 设置"
  printf "  %-12s %s\n" "proxy" "代理：安装 Mihomo 或 sing-box，配置 MetaCubeXD 和 shell 代理环境模板"
  printf "  %-12s %s\n" "desktop" "桌面：安装 Hyprland、SDDM、Fcitx5/Rime、浏览器、终端和 hyprdots 配置"
  echo
  echo "[组合目标]"
  printf "  %-12s %s\n" "dev" "开发环境套餐：base + archlinuxcn + dns + git + ops-toolkit + runtime + nvim + docker + fonts + shell + proxy"
  printf "  %-12s %s\n" "workstation" "完整工作站套餐：dev + desktop"
  printf "  %-12s %s\n" "custom" "自定义入口：先选一个起点，再按后续问题微调关键开关"
  echo
}

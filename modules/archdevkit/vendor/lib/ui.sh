#!/usr/bin/env bash
# 交互式输入辅助：短输入框、编号菜单和默认值处理。

ui_trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <<<"$1"
}

ask_value_default() {
  local prompt="$1" current="$2" answer
  printf "%s [%s]: " "${prompt}" "${current}" >&2
  IFS= read -r answer || answer=""
  printf "%s" "${answer:-${current}}"
}

ask_bool_default() {
  local prompt="$1" current="$2" answer
  if [[ "${current:-0}" -eq 1 ]]; then
    printf "%s [Y/n]: " "${prompt}" >&2
    IFS= read -r answer || answer=""
    case "${answer}" in
      n|N|no|NO|No) printf "0" ;;
      *) printf "1" ;;
    esac
  else
    printf "%s [y/N]: " "${prompt}" >&2
    IFS= read -r answer || answer=""
    case "${answer}" in
      y|Y|yes|YES|Yes) printf "1" ;;
      *) printf "0" ;;
    esac
  fi
}

ask_menu_default() {
  local title="$1" current="$2"
  shift 2

  local item key desc answer default_index="" default_prompt
  local keys=()
  local descriptions=()
  local index=0

  for item in "$@"; do
    key="${item%%|*}"
    desc="${item#*|}"
    keys+=("${key}")
    descriptions+=("${desc}")
    index=$((index + 1))
    [[ "${key}" == "${current}" ]] && default_index="${index}"
  done

  while true; do
    printf '\n[%s]\n\n' "${title}" >&2
    for index in "${!keys[@]}"; do
      printf "  %2d. %-14s %s\n" "$((index + 1))" "${keys[index]}" "${descriptions[index]}" >&2
    done

    if [[ -n "${default_index}" ]]; then
      default_prompt="${default_index}"
      printf '\n默认：%s. %s\n' "${default_index}" "${current}" >&2
    else
      default_prompt="${current}"
      printf '\n默认：%s\n' "${current}" >&2
    fi
    printf "请选择%s [%s]: " "${title}" "${default_prompt}" >&2

    IFS= read -r answer || answer=""
    answer="$(ui_trim "${answer}")"
    [[ -z "${answer}" ]] && {
      printf "%s" "${current}"
      return 0
    }

    if [[ "${answer}" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#keys[@]} )); then
      printf "%s" "${keys[answer - 1]}"
      return 0
    fi

    for key in "${keys[@]}"; do
      if [[ "${answer}" == "${key}" ]]; then
        printf "%s" "${key}"
        return 0
      fi
    done

    log_warn "请输入编号或可选名称" >&2
  done
}

ask_choice_default() {
  local prompt="$1" current="$2" choices="$3" choice
  local items=()
  for choice in ${choices}; do
    items+=("${choice}|${choice}")
  done
  ask_menu_default "${prompt}" "${current}" "${items[@]}"
}

show_menu() {
  clear || true
  echo "----------------------------------------------------------"
  echo "[ArchDevKit 交互式安装向导]"
  echo "直接回车会使用 install_vars 中的默认值。"
  echo "----------------------------------------------------------"

  TARGET="$(
    ask_menu_default "安装目标" "${TARGET}" \
      "base|基础环境：基础命令行工具、同步/排障工具和 paru/yay" \
      "dev|开发环境：base + archlinuxcn + dns + git + runtime + nvim + docker + fonts + shell + proxy" \
      "workstation|完整工作站：dev + Hyprland 桌面" \
      "custom|自定义入口：先选起点，再按后续问题微调" \
      "dns|系统 DNS：systemd-resolved、NetworkManager DNS 后端和 fallback DNS" \
      "archlinuxcn|软件源：archlinuxcn 源、keyring 和可选 mirrorlist" \
      "git|Git 环境：git、gh、openssh 和基础 Git 配置" \
      "ops-toolkit|运维脚本：ops-toolkit 仓库和稳定命令入口" \
      "runtime|开发运行时：mise 管理 Node 24、Python 3.13、Go 1.24" \
      "nvim|Neovim：安装 Neovim、个人配置和可选插件同步" \
      "docker|Docker：docker/compose、镜像源、服务和用户组" \
      "fonts|字体：中文字体、Emoji、Nerd Font、Monaco 和 fontconfig" \
      "shell|Shell：Zsh、Oh My Zsh、Starship 终端样式、插件和默认 shell" \
      "desktop|桌面：Hyprland、SDDM、Fcitx5/Rime、浏览器、终端和 hyprdots" \
      "proxy|代理：Mihomo 或 sing-box、MetaCubeXD 和 shell 代理环境模板"
  )"
  if [[ "${TARGET}" == "custom" ]]; then
    TARGET="$(
      ask_menu_default "自定义起点" "workstation" \
        "base|基础环境" \
        "dev|开发环境套餐" \
        "workstation|完整工作站套餐" \
        "dns|只配置系统 DNS" \
        "archlinuxcn|只配置 archlinuxcn 源" \
        "git|只安装 Git 环境" \
        "ops-toolkit|只安装 Ops Toolkit 运维脚本" \
        "runtime|只安装开发运行时" \
        "nvim|只安装 Neovim" \
        "docker|只安装 Docker" \
        "fonts|只安装字体环境" \
        "shell|只安装 Shell 环境" \
        "desktop|只安装 Hyprland 桌面" \
        "proxy|只安装代理环境"
    )"
  fi

  if [[ "${TARGET}" == "dev" || "${TARGET}" == "workstation" ]]; then
    INSTALL_ARCHLINUXCN="$(ask_bool_default "启用 archlinuxcn 源" "${INSTALL_ARCHLINUXCN:-1}")"
    ENABLE_DNS="$(ask_bool_default "配置系统 DNS" "${ENABLE_DNS:-1}")"
    ENABLE_OPS_TOOLKIT="$(ask_bool_default "安装 Ops Toolkit" "${ENABLE_OPS_TOOLKIT:-1}")"
    ENABLE_PROXY="$(ask_bool_default "安装 Proxy 模块" "${ENABLE_PROXY:-1}")"
  fi

  if [[ "${TARGET}" == "proxy" || ( "${TARGET}" =~ ^(dev|workstation)$ && "${ENABLE_PROXY:-0}" -eq 1 ) ]]; then
    PROXY_CORE="$(
      ask_menu_default "代理核心" "${PROXY_CORE:-mihomo}" \
        "mihomo|Mihomo/Clash.Meta 兼容核心，适合规则分流和 MetaCubeXD" \
        "sing-box|sing-box 用户服务，配置更轻量"
    )"
    PROXY_AUTO_ENABLE_SERVICE="$(ask_bool_default "安装后自动启用代理服务" "${PROXY_AUTO_ENABLE_SERVICE:-1}")"
    if [[ "${PROXY_CORE}" == "mihomo" ]]; then
      ENABLE_METACUBEXD="$(ask_bool_default "安装 MetaCubeXD 面板" "${ENABLE_METACUBEXD:-1}")"
    fi
  fi

  if [[ "${TARGET}" == "desktop" || "${TARGET}" == "workstation" ]]; then
    GPU_TYPE="$(
      ask_menu_default "GPU 类型" "${GPU_TYPE:-auto}" \
        "auto|自动检测" \
        "intel|Intel 核显" \
        "amd|AMD 显卡" \
        "nvidia|NVIDIA 显卡" \
        "vmware|VMware 虚拟机" \
        "virtio|QEMU/KVM virtio" \
        "qxl|QEMU/KVM QXL" \
        "virtualbox|VirtualBox 虚拟机" \
        "none|不安装专用显卡/虚拟机包"
    )"
    ENABLE_SDDM="$(ask_bool_default "启用 SDDM 登录管理器" "${ENABLE_SDDM:-1}")"
    HYPRLAND_CONFIG_MODE="$(
      ask_menu_default "Hyprland 配置模式" "${HYPRLAND_CONFIG_MODE:-hyprdots}" \
        "hyprdots|安装项目内置 hyprdots 配置" \
        "template|安装轻量默认模板" \
        "skip|只安装软件包，不写入桌面配置"
    )"
    ENABLE_FCITX5="$(ask_bool_default "启用 Fcitx5 输入法" "${ENABLE_FCITX5:-1}")"
    if [[ "${ENABLE_FCITX5:-0}" -eq 1 ]]; then
      INPUT_METHOD_ENGINE="$(
        ask_menu_default "输入法引擎" "${INPUT_METHOD_ENGINE:-rime}" \
          "rime|Fcitx5 + Rime，适合个人方案和可同步配置" \
          "pinyin|Fcitx5 拼音，少配置、轻量使用"
      )"
      if [[ "${INPUT_METHOD_ENGINE}" == "rime" ]]; then
        RIME_SCHEMA="$(ask_value_default "Rime 默认方案" "${RIME_SCHEMA:-luna_pinyin_simp}")"
        INSTALL_RIME_CONFIG="$(ask_bool_default "安装 Rime 配置仓库" "${INSTALL_RIME_CONFIG:-1}")"
      fi
    fi
    BROWSER_PACKAGE="$(ask_value_default "浏览器安装包" "${BROWSER_PACKAGE:-google-chrome}")"
    BROWSER_APP="$(ask_value_default "浏览器启动命令" "${BROWSER_APP:-google-chrome-stable}")"
  fi

  validate_config
  confirm_and_run_target "${TARGET}"
}

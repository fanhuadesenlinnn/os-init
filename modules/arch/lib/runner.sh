#!/usr/bin/env bash
# 安装执行层：安装前检查、模块运行、日志和完成摘要。

run_plan() {
  local modules_text="$1" total index=0 module display
  state_prepare_dirs
  total="$(wc -w <<<"${modules_text}" | tr -d ' ')"
  for module in ${modules_text}; do
    module="$(module_key "${module}")"
    display="$(module_display_key "${module}")"
    index=$((index + 1))
    if [[ "${FORCE_INSTALL:-0}" -ne 1 ]] && module_state_valid "${module}"; then
      log_info "[${index}/${total}] ${display} 已安装且校验通过，跳过"
      mark_done "${module}"
      mark_skipped "${module}"
      continue
    fi

    log_info "[${index}/${total}] 开始处理 ${display}：$(module_desc "${module}")"
    set_current_module "${module}" "${index}" "${total}"
    module_install_func "${module}"
    mark_module_installed "${module}"
    clear_current_module
    log_info "[${index}/${total}] ${display} 处理完成"
  done
}

start_run_log() {
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  state_prepare_dirs
  OS_INIT_ARCH_LOG_FILE="$(state_root)/logs/$(date +%Y%m%d-%H%M%S)-${TARGET:-install}.log"
  exec > >(tee -a "${OS_INIT_ARCH_LOG_FILE}") 2>&1
  log_info "本次安装日志：${OS_INIT_ARCH_LOG_FILE}"
}

preflight_install() {
  local modules_text="$1"
  log_info "执行安装前检查"
  require_arch
  require_cmd pacman
  if [[ "${EUID}" -ne 0 ]]; then
    require_cmd sudo
  fi
  if plan_needs_git_command "${modules_text}" && ! need_cmd git; then
    log_warn "当前缺少 git，相关模块会在执行时按需安装 git 包"
  fi
}

show_summary() {
  echo
  echo "----------------------------------------------------------"
  echo "[执行完成]"
  [[ -n "${OS_INIT_ARCH_LOG_FILE:-}" ]] && echo "日志文件: ${OS_INIT_ARCH_LOG_FILE}"
  echo "已处理模块:"
  local key display_key
  for key in $(all_modules); do
    display_key="$(module_display_key "${key}")"
    is_done "${key}" && echo "  - ${display_key} ($(module_desc "${key}"))$(is_skipped "${key}" && printf '：已跳过')"
  done
  echo
  echo "后续建议:"
  local tip_no=0 done_count=0
  for key in $(all_modules); do
    is_done "${key}" && done_count=$((done_count + 1))
  done
  add_summary_tip() {
    tip_no=$((tip_no + 1))
    echo "${tip_no}. $*"
  }

  if is_done "base" && [[ "${done_count}" -eq 1 ]]; then
    add_summary_tip "基础工具已经就绪；可继续选择其他 Arch 能力，或在 OS Init 主菜单中使用 dev/workstation 套餐。"
    add_summary_tip "如果刚完成系统大版本更新，建议重启一次后再继续安装桌面或显卡相关模块。"
  fi
  if is_done "archlinuxcn"; then
    add_summary_tip "archlinuxcn 源已配置；若后续软件查不到，先执行 sudo pacman -Syu 再重试。"
  fi
  if is_done "dns"; then
    add_summary_tip "系统 DNS 已交给 systemd-resolved；查看状态可执行：resolvectl status。"
  fi
  if is_done "git"; then
    add_summary_tip "如需使用 GitHub CLI 登录，执行：gh auth login && gh auth setup-git。"
  fi
  if is_done "ops_toolkit"; then
    add_summary_tip "Ops Toolkit 命令入口：${OPS_TOOLKIT_COMMAND} list；仓库目录：${OPS_TOOLKIT_DIR}。"
    add_summary_tip "后续脚本更新可执行：cd ${OPS_TOOLKIT_DIR} && git pull --ff-only，既有命令入口保持不变。"
  fi
  if is_done "fonts"; then
    add_summary_tip "字体缓存已刷新；若终端或浏览器仍未显示新字体，重启对应应用即可。"
  fi
  if is_done "desktop_hyprland"; then
    if [[ "${ENABLE_SDDM:-0}" -eq 1 ]]; then
      add_summary_tip "SDDM 已启用；重启后在登录界面选择 Hyprland 会话。"
    else
      add_summary_tip "Hyprland 已安装但未启用 SDDM；可用 Hyprland 命令从 tty 手动启动会话。"
    fi
  fi
  if is_done "proxy"; then
    add_summary_tip "sing-box 配置文件：${SING_BOX_CONFIG_FILE:-${HOME}/.config/sing-box/config.json}。"
    if [[ "${EUID}" -eq 0 ]]; then
      add_summary_tip "sing-box 服务状态可用 systemctl status os-init-arch-sing-box 查看。"
    else
      add_summary_tip "sing-box 服务状态可用 systemctl --user status os-init-arch-sing-box 查看。"
    fi
  fi
  add_summary_tip "查看模块状态可执行：bash install.sh status。"
  if [[ "${tip_no}" -eq 0 ]]; then
    add_summary_tip "没有额外动作需要处理。"
  fi
  echo "----------------------------------------------------------"
}

confirm_and_run_target() {
  local target="$1" modules_text
  modules_text="$(modules_for_target "${target}")"
  show_plan "${target}" "${modules_text}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_warn "当前为 dry-run 模式，只显示计划，不执行安装"
    return 0
  fi
  if [[ "${ASSUME_YES:-0}" -eq 1 ]] || confirm_yes "是否按以上计划继续安装？"; then
    start_run_log
    enable_install_recovery
    set_install_phase "preflight"
    preflight_install "${modules_text}"
    run_plan "${modules_text}"
    disable_install_recovery
    show_summary
  else
    log_warn "已取消安装：${target}"
  fi
}

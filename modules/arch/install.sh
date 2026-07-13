#!/usr/bin/env bash
# Variables and functions are intentionally shared across the sourced
# capability files; ShellCheck cannot infer those cross-file uses here.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

# OS Init Arch 主入口
# 负责加载依赖、解析参数，并把用户动作分发到对应层。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/install_vars"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/files.sh"
source "${SCRIPT_DIR}/lib/packages.sh"
source "${SCRIPT_DIR}/lib/systemd.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/modules/base.sh"
source "${SCRIPT_DIR}/modules/aur.sh"
source "${SCRIPT_DIR}/modules/dns.sh"
source "${SCRIPT_DIR}/modules/archlinuxcn.sh"
source "${SCRIPT_DIR}/modules/git.sh"
source "${SCRIPT_DIR}/modules/ops_toolkit.sh"
source "${SCRIPT_DIR}/modules/fonts.sh"
source "${SCRIPT_DIR}/modules/desktop_hyprland.sh"
source "${SCRIPT_DIR}/modules/proxy.sh"
source "${SCRIPT_DIR}/lib/module_registry.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/plan.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/ui.sh"
source "${SCRIPT_DIR}/lib/doctor.sh"
source "${SCRIPT_DIR}/lib/recovery.sh"
source "${SCRIPT_DIR}/lib/runner.sh"

ACTION="menu"
TARGET=""
TARGET_SET=0
FORCE_INSTALL=0
NO_STATE=0
RESUME_INSTALL=0
OUTPUT_JSON=0
STATUS_VERBOSE=0
OS_INIT_ARCH_LOG_FILE=""
MODULE_SKIPPED_LIST=""

show_help() {
  cat <<'EOF'
OS Init Arch - Arch Linux 工作站初始化工具

用法：
  bash install.sh
  bash install.sh menu
  bash install.sh plan [base|aur|dns|archlinuxcn|git|ops-toolkit|fonts|sing-box|desktop]
  bash install.sh install [base|aur|dns|archlinuxcn|git|ops-toolkit|fonts|sing-box|desktop]
  bash install.sh status [module] [--verbose]
  bash install.sh doctor
  bash install.sh reset-state [module|all]

常用参数：
  -y, --yes                 自动确认
  --dry-run                 只显示计划，不执行
  --force                   忽略模块状态，强制重跑目标模块；config init 时覆盖已有配置
  --resume                  从状态记录继续，已成功模块自动跳过
  --no-state                不读取或写入模块状态
  --json                    plan/status/doctor 输出 JSON
  --verbose, -v             status 输出状态文件、指纹和建议动作详情
  --config-file PATH        加载指定 OS Init 配置文件
  --no-config-file          不加载用户配置文件
  --no-github-proxy         不使用 GitHub 代理
  --github-proxy URL        指定 GitHub 代理
  --ops-toolkit-repo URL    指定 Ops Toolkit 仓库
  --ops-toolkit-branch NAME 指定 Ops Toolkit 分支
  --ops-toolkit-dir PATH    指定 Ops Toolkit 本地仓库目录
  --ops-bin-dir PATH        指定 Ops Toolkit 命令目录
  --dns-over-tls MODE       systemd-resolved DNSOverTLS：no / opportunistic / yes
  --no-sddm                 不启用 SDDM
  --nvidia                  安装 NVIDIA Wayland 相关包
  --gpu TYPE                指定 GPU 类型：auto / intel / amd / nvidia / vmware / virtio / qxl / virtualbox / none
  --vm-dynamic-resize       虚拟机使用动态分辨率
  --no-vm-dynamic-resize    虚拟机使用固定 fallback 分辨率
  --vm-monitor-mode MODE    指定虚拟机固定 fallback 分辨率
  --monaco                  安装 Monaco 字体
  --browser-package NAME    指定桌面浏览器安装包
  --browser-app COMMAND     指定桌面浏览器启动命令
  --hyprland-config-mode MODE 指定 Hyprland 配置模式：hyprdots / template / skip
  --with-obsidian          安装 hyprdots 可选应用 Obsidian
  --no-obsidian            不安装 hyprdots 可选应用 Obsidian
  --rime-schema NAME        指定 Rime 默认方案
  --rime-repo URL           指定 Rime 配置仓库
  --rime-branch NAME        指定 Rime 配置分支
  --no-rime-config          不安装 Rime 配置仓库
  --sing-box-config PATH/URL 指定 sing-box 配置文件或 URL
EOF
}

parse_args() {
  local token
  while [[ $# -gt 0 ]]; do
    token="$1"
    case "${token}" in
      menu|help|plan|install|status|doctor|reset-state)
        ACTION="${token}"; shift ;;
      all)
        if [[ "${ACTION}" == "status" || "${ACTION}" == "reset-state" ]]; then
          TARGET="all"
          TARGET_SET=1
          shift
        else
          die "all 只能用于 status 或 reset-state"
        fi
        ;;
      base|aur|dns|archlinuxcn|git|ops|ops-toolkit|ops_toolkit|fonts|desktop|hyprland|proxy)
        TARGET="${token}"
        TARGET_SET=1
        [[ "${ACTION}" == "menu" ]] && ACTION="install"
        shift ;;
      sing-box)
        TARGET="proxy"
        TARGET_SET=1
        [[ "${ACTION}" == "menu" ]] && ACTION="install"
        shift ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force|--reinstall) FORCE_INSTALL=1; shift ;;
      --update) FORCE_INSTALL=1; shift ;;
      --uninstall) die "Arch 系统能力暂不支持批量卸载；请使用对应通用模块的卸载能力" ;;
      --resume) RESUME_INSTALL=1; shift ;;
      --no-state) NO_STATE=1; shift ;;
      --json) OUTPUT_JSON=1; shift ;;
      --verbose|-v) STATUS_VERBOSE=1; shift ;;
      --config-file)
        [[ $# -ge 2 && -n "${2:-}" ]] || die "--config-file 需要路径"
        OS_INIT_ARCH_CONFIG_FILE="${2}"
        OS_INIT_ARCH_LOAD_CONFIG_FILE=1
        shift 2
        ;;
      --config-file=*)
        OS_INIT_ARCH_CONFIG_FILE="${1#*=}"
        [[ -n "${OS_INIT_ARCH_CONFIG_FILE}" ]] || die "--config-file 需要路径"
        OS_INIT_ARCH_LOAD_CONFIG_FILE=1
        shift
        ;;
      --no-config-file) OS_INIT_ARCH_LOAD_CONFIG_FILE=0; shift ;;
      --no-china) ENABLE_CHINA_MIRROR=0; shift ;;
      --no-github-proxy) ENABLE_GITHUB_PROXY=0; shift ;;
      --github-proxy) GITHUB_PROXY="${2:-}"; ENABLE_GITHUB_PROXY=1; shift 2 ;;
      --github-proxy=*) GITHUB_PROXY="${1#*=}"; ENABLE_GITHUB_PROXY=1; shift ;;
      --dns) ENABLE_DNS=1; shift ;;
      --no-dns) ENABLE_DNS=0; shift ;;
      --with-ops-toolkit) ENABLE_OPS_TOOLKIT=1; shift ;;
      --no-ops-toolkit) ENABLE_OPS_TOOLKIT=0; shift ;;
      --ops-toolkit-repo) OPS_TOOLKIT_REPO="${2:-}"; ENABLE_OPS_TOOLKIT=1; shift 2 ;;
      --ops-toolkit-repo=*) OPS_TOOLKIT_REPO="${1#*=}"; ENABLE_OPS_TOOLKIT=1; shift ;;
      --ops-toolkit-branch) OPS_TOOLKIT_BRANCH="${2:-}"; ENABLE_OPS_TOOLKIT=1; shift 2 ;;
      --ops-toolkit-branch=*) OPS_TOOLKIT_BRANCH="${1#*=}"; ENABLE_OPS_TOOLKIT=1; shift ;;
      --ops-toolkit-dir) OPS_TOOLKIT_DIR="${2:-}"; shift 2 ;;
      --ops-toolkit-dir=*) OPS_TOOLKIT_DIR="${1#*=}"; shift ;;
      --ops-bin-dir) OPS_TOOLKIT_BIN_DIR="${2:-}"; shift 2 ;;
      --ops-bin-dir=*) OPS_TOOLKIT_BIN_DIR="${1#*=}"; shift ;;
      --dns-over-tls) DNS_OVER_TLS="${2:-no}"; shift 2 ;;
      --dns-over-tls=*) DNS_OVER_TLS="${1#*=}"; shift ;;
      --no-sddm) ENABLE_SDDM=0; shift ;;
      --sddm) ENABLE_SDDM=1; shift ;;
      --nvidia) GPU_TYPE="nvidia"; shift ;;
      --gpu) GPU_TYPE="${2:-auto}"; shift 2 ;;
      --gpu=*) GPU_TYPE="${1#*=}"; shift ;;
      --vm-dynamic-resize) VM_HYPRLAND_DYNAMIC_RESIZE=1; shift ;;
      --no-vm-dynamic-resize) VM_HYPRLAND_DYNAMIC_RESIZE=0; shift ;;
      --vm-monitor-mode) VM_HYPRLAND_MONITOR_MODE="${2:-1920x1080@60}"; VMWARE_HYPRLAND_MONITOR_MODE="${VM_HYPRLAND_MONITOR_MODE}"; shift 2 ;;
      --vm-monitor-mode=*) VM_HYPRLAND_MONITOR_MODE="${1#*=}"; VMWARE_HYPRLAND_MONITOR_MODE="${VM_HYPRLAND_MONITOR_MODE}"; shift ;;
      --monaco) INSTALL_MONACO_FONT=1; shift ;;
      --no-monaco) INSTALL_MONACO_FONT=0; shift ;;
      --browser-package) BROWSER_PACKAGE="${2:-}"; shift 2 ;;
      --browser-package=*) BROWSER_PACKAGE="${1#*=}"; shift ;;
      --browser-app) BROWSER_APP="${2:-}"; shift 2 ;;
      --browser-app=*) BROWSER_APP="${1#*=}"; shift ;;
      --hyprland-config-mode) HYPRLAND_CONFIG_MODE="${2:-hyprdots}"; shift 2 ;;
      --hyprland-config-mode=*) HYPRLAND_CONFIG_MODE="${1#*=}"; shift ;;
      --with-obsidian) INSTALL_HYPRDOTS_OBSIDIAN=1; shift ;;
      --no-obsidian) INSTALL_HYPRDOTS_OBSIDIAN=0; shift ;;
      --rime-schema) RIME_SCHEMA="${2:-}"; INPUT_METHOD_ENGINE="rime"; shift 2 ;;
      --rime-schema=*) RIME_SCHEMA="${1#*=}"; INPUT_METHOD_ENGINE="rime"; shift ;;
      --rime-repo) RIME_CONFIG_REPO="${2:-}"; INSTALL_RIME_CONFIG=1; INPUT_METHOD_ENGINE="rime"; shift 2 ;;
      --rime-repo=*) RIME_CONFIG_REPO="${1#*=}"; INSTALL_RIME_CONFIG=1; INPUT_METHOD_ENGINE="rime"; shift ;;
      --rime-branch) RIME_CONFIG_BRANCH="${2:-}"; INSTALL_RIME_CONFIG=1; INPUT_METHOD_ENGINE="rime"; shift 2 ;;
      --rime-branch=*) RIME_CONFIG_BRANCH="${1#*=}"; INSTALL_RIME_CONFIG=1; INPUT_METHOD_ENGINE="rime"; shift ;;
      --no-rime-config) INSTALL_RIME_CONFIG=0; shift ;;
      --sing-box-config) SING_BOX_CONFIG_SOURCE="${2:-}"; shift 2 ;;
      --sing-box-config=*) SING_BOX_CONFIG_SOURCE="${1#*=}"; shift ;;
      -h|--help) ACTION="help"; shift ;;
      *) die "未知参数：$1" ;;
    esac
  done

  if [[ "${ACTION}" == "status" && "${TARGET_SET}" -eq 0 ]]; then
    TARGET="all"
  fi
  if [[ "${ACTION}" == "reset-state" && "${TARGET_SET}" -eq 0 ]]; then
    TARGET="all"
  fi
  if [[ ( "${ACTION}" == "plan" || "${ACTION}" == "install" ) && "${TARGET_SET}" -eq 0 ]]; then
    die "${ACTION} 需要指定一个 Arch 能力；查看可用项请执行 --help"
  fi
}

main() {
  parse_config_file_args "$@"
  load_user_config_file
  parse_args "$@"
  validate_config

  case "${ACTION}" in
    help) show_help ;;
    plan)
      show_plan "${TARGET}" "$(modules_for_target "${TARGET}")"
      ;;
    status)
      show_status
      ;;
    doctor)
      show_doctor
      ;;
    reset-state)
      reset_module_state "${TARGET}"
      ;;
    menu)
      [[ "${EUID}" -eq 0 ]] || require_cmd sudo
      show_menu
      ;;
    install)
      [[ "${EUID}" -eq 0 ]] || require_cmd sudo
      confirm_and_run_target "${TARGET}"
      ;;
    *)
      die "未知动作：${ACTION}"
      ;;
  esac
}

main "$@"

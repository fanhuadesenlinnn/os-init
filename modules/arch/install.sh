#!/usr/bin/env bash
# Arch provider implementation. Planning, confirmation, lifecycle selection,
# logging, and summaries belong to the Go control plane.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

# Capture exported values before loading Arch defaults. They are restored
# after the user config so precedence is defaults < config < environment.
declare -A OS_INIT_ARCH_INHERITED_ENV=()
snapshot_config_environment() {
  local key
  for key in $(config_scalar_keys) $(config_list_keys); do
    if printenv "${key}" >/dev/null 2>&1; then
      OS_INIT_ARCH_INHERITED_ENV["${key}"]="${!key}"
    fi
  done
}

restore_config_environment() {
  local key
  for key in "${!OS_INIT_ARCH_INHERITED_ENV[@]}"; do
    apply_config_assignment "${key}" "${OS_INIT_ARCH_INHERITED_ENV[${key}]}"
  done
}

snapshot_config_environment
# Shared defaults are the single source for settings exposed by the generated
# user config. install_vars only adds Arch-internal defaults on top.
source "${SCRIPT_DIR}/../config/defaults.env"
source "${SCRIPT_DIR}/install_vars"
source "${SCRIPT_DIR}/lib/files.sh"
source "${SCRIPT_DIR}/lib/packages.sh"
source "${SCRIPT_DIR}/lib/systemd.sh"
source "${SCRIPT_DIR}/lib/json.sh"
source "${SCRIPT_DIR}/modules/base.sh"
source "${SCRIPT_DIR}/modules/cli.sh"
source "${SCRIPT_DIR}/modules/aur.sh"
source "${SCRIPT_DIR}/modules/dns.sh"
source "${SCRIPT_DIR}/modules/archlinuxcn.sh"
source "${SCRIPT_DIR}/modules/git.sh"
source "${SCRIPT_DIR}/modules/ops_toolkit.sh"
source "${SCRIPT_DIR}/modules/fonts.sh"
source "${SCRIPT_DIR}/modules/desktop_hyprland.sh"
source "${SCRIPT_DIR}/modules/proxy.sh"
source "${SCRIPT_DIR}/lib/module_registry.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/lib/doctor.sh"

OUTPUT_JSON=0
STATUS_VERBOSE=0

provider_preflight() {
  log_info "执行 Arch 能力运行前检查"
  require_arch
  require_cmd pacman
  if [[ "${EUID}" -ne 0 ]]; then
    require_cmd sudo
  fi
}

provider_main() {
  local component="${1:-}" module
  [[ "${OS_INIT_PROVIDER_MODE:-0}" -eq 1 ]] || \
    die "Arch 能力必须通过 OS Init 控制面或 modules/provider.sh 执行"

  load_user_config_file
  restore_config_environment
  normalize_archlinuxarm_package_defaults
  validate_config

  case "${component}" in
    doctor) show_doctor; return ;;
    status) show_status; return ;;
  esac

  module="$(module_key "${component}")"
  case "${OS_INIT_PROVIDER_OPERATION:-install}" in
    install|update) ;;
    *) die "Arch 能力不支持操作：${OS_INIT_PROVIDER_OPERATION:-}" ;;
  esac

  provider_preflight
  module_install_func "${module}"
  mark_module_installed "${module}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  provider_main "$@"
fi

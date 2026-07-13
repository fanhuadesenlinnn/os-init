#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r script; do
  bash -n "${script}"
done < <(find "${SCRIPT_DIR}" -type f -name '*.sh' -print)

grep -Fq "\${HOME}/.config/os-init/config.env" "${SCRIPT_DIR}/install_vars"
grep -Fq "\${HOME}/.local/state/os-init/arch" "${SCRIPT_DIR}/install_vars"
grep -Fq 'base aur archlinuxcn dns git ops_toolkit fonts proxy desktop_hyprland' \
  "${SCRIPT_DIR}/lib/module_registry.sh"

if grep -RqsE --exclude=test.sh 'Arch[D]evKit|arch[d]evkit|ARCH[D]EVKIT' "${SCRIPT_DIR}"; then
  echo "legacy subsystem name remains in modules/arch" >&2
  exit 1
fi

if grep -Fq 'require_normal_user' "${SCRIPT_DIR}/install.sh"; then
  echo "Arch capability entrypoint must support root" >&2
  exit 1
fi

for removed in modules/runtime.sh modules/nvim.sh modules/docker.sh modules/shell_zsh.sh modules/proxy/sing_box.sh files/sing-box/config.json.tpl; do
  if [[ -e "${SCRIPT_DIR}/${removed}" ]]; then
    echo "duplicate cross-platform installer remains: ${removed}" >&2
    exit 1
  fi
done

if grep -RqsE --include='*.sh' --exclude=test.sh 'RUNTIME_MANAGER|NVIM_REPO|SING_BOX|ADD_USER_TO_DOCKER_GROUP' "${SCRIPT_DIR}"; then
  echo "cross-platform installer configuration leaked into modules/arch" >&2
  exit 1
fi

grep -Fq 'install_package_from_pacman_prefer_archlinuxcn paru' "${SCRIPT_DIR}/lib/packages.sh"
grep -Fq 'install_package_from_pacman_prefer_archlinuxcn yay' "${SCRIPT_DIR}/lib/packages.sh"
grep -Fq 'mihomo_service_ready' "${SCRIPT_DIR}/modules/proxy/common.sh"
grep -Fq 'https://example.com/your-subscription-url' "${SCRIPT_DIR}/files/mihomo/config.yaml.tpl"
grep -Fq 'OS_INIT_PROVIDER_MODE' "${SCRIPT_DIR}/install.sh"
grep -Fq 'restore_config_environment' "${SCRIPT_DIR}/install.sh"

for removed_control in lib/plan.sh lib/runner.sh lib/recovery.sh lib/ui.sh preset.sh; do
  if [[ -e "${SCRIPT_DIR}/${removed_control}" ]]; then
    echo "duplicate Arch control-plane file remains: ${removed_control}" >&2
    exit 1
  fi
done

echo "Arch capability checks passed"

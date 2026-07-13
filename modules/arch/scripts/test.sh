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

for removed in modules/runtime.sh modules/nvim.sh modules/docker.sh modules/shell_zsh.sh modules/proxy/mihomo.sh; do
  if [[ -e "${SCRIPT_DIR}/${removed}" ]]; then
    echo "duplicate cross-platform installer remains: ${removed}" >&2
    exit 1
  fi
done

if grep -RqsE --include='*.sh' --exclude=test.sh 'RUNTIME_MANAGER|NVIM_REPO|MIHOMO_CONFIG|ADD_USER_TO_DOCKER_GROUP' "${SCRIPT_DIR}"; then
  echo "cross-platform installer configuration leaked into modules/arch" >&2
  exit 1
fi

echo "Arch capability checks passed"

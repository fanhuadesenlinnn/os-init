#!/usr/bin/env bash
# Test stubs are dispatched indirectly through module_install_func. ShellCheck
# renamed this diagnostic between supported releases.
# shellcheck disable=SC2317,SC2329
set -euo pipefail

ARCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${ARCH_DIR}/../.." && pwd)"

while IFS= read -r script; do
  bash -n "${script}"
done < <(find "${ARCH_DIR}" -type f -name '*.sh' -print)

grep -Fq "\${HOME}/.config/os-init/config.env" "${ARCH_DIR}/install_vars"
grep -Fq "\${HOME}/.local/state/os-init/arch" "${ARCH_DIR}/install_vars"
grep -Fq 'base aur archlinuxcn dns git ops_toolkit fonts proxy desktop_hyprland' \
  "${ARCH_DIR}/lib/module_registry.sh"

if grep -RqsE --exclude=test.sh 'Arch[D]evKit|arch[d]evkit|ARCH[D]EVKIT' "${ARCH_DIR}"; then
  echo "legacy subsystem name remains in modules/arch" >&2
  exit 1
fi

if grep -Fq 'require_normal_user' "${ARCH_DIR}/install.sh"; then
  echo "Arch capability entrypoint must support root" >&2
  exit 1
fi

if grep -RqsE --include='*.sh' --exclude=test.sh 'preflight_install|modules_for_target' "${ARCH_DIR}"; then
  echo "removed Arch control-plane function reference remains" >&2
  exit 1
fi

for removed in modules/runtime.sh modules/nvim.sh modules/docker.sh modules/shell_zsh.sh modules/proxy/sing_box.sh files/sing-box/config.json.tpl; do
  if [[ -e "${ARCH_DIR}/${removed}" ]]; then
    echo "duplicate cross-platform installer remains: ${removed}" >&2
    exit 1
  fi
done

if grep -RqsE --include='*.sh' --exclude=test.sh 'RUNTIME_MANAGER|NVIM_REPO|SING_BOX|ADD_USER_TO_DOCKER_GROUP' "${ARCH_DIR}"; then
  echo "cross-platform installer configuration leaked into modules/arch" >&2
  exit 1
fi

grep -Fq 'install_package_from_pacman_prefer_archlinuxcn paru' "${ARCH_DIR}/lib/packages.sh"
grep -Fq 'install_package_from_pacman_prefer_archlinuxcn yay' "${ARCH_DIR}/lib/packages.sh"
grep -Fq 'mihomo_service_ready' "${ARCH_DIR}/modules/proxy/common.sh"
grep -Fq 'https://example.com/your-subscription-url' "${ARCH_DIR}/files/mihomo/config.yaml.tpl"
grep -Fq 'OS_INIT_PROVIDER_MODE' "${ARCH_DIR}/install.sh"
grep -Fq 'restore_config_environment' "${ARCH_DIR}/install.sh"

for removed_control in lib/plan.sh lib/runner.sh lib/recovery.sh lib/ui.sh preset.sh; do
  if [[ -e "${ARCH_DIR}/${removed_control}" ]]; then
    echo "duplicate Arch control-plane file remains: ${removed_control}" >&2
    exit 1
  fi
done

if (( BASH_VERSINFO[0] >= 4 )); then
  (
    # Loading the real entrypoint catches missing sourced functions without
    # executing a provider operation.
    # shellcheck source=modules/arch/install.sh
    source "${ARCH_DIR}/install.sh"

    declare -F provider_preflight >/dev/null
    declare -F module_install_func >/dev/null
    declare -F mark_module_installed >/dev/null

    require_arch() { :; }
    require_cmd() { :; }
    provider_preflight >/dev/null

    install_base() { printf 'base'; }
    install_aur_helpers() { printf 'aur'; }
    install_archlinuxcn() { printf 'archlinuxcn'; }
    install_dns_env() { printf 'dns'; }
    install_git_env() { printf 'git'; }
    install_ops_toolkit() { printf 'ops_toolkit'; }
    install_fonts() { printf 'fonts'; }
    install_proxy_env() { printf 'proxy'; }
    install_desktop_hyprland() { printf 'desktop_hyprland'; }

    while IFS= read -r component; do
      [[ -n "${component}" ]] || continue
      expected="$(module_key "${component}")"
      actual="$(module_install_func "${component}")"
      if [[ "${actual}" != "${expected}" ]]; then
        echo "Go/Shell Arch component mismatch: ${component} -> ${actual}, expected ${expected}" >&2
        exit 1
      fi
    done < <(sed -n 's/.*archLinuxModule("[^"]*", "\([^"]*\)".*/\1/p' "${REPO_ROOT}/internal/modules/registry.go")
  )

  OS_INIT_PROVIDER_MODE=1 OS_INIT_ARCH_LOAD_CONFIG_FILE=0 \
    bash "${ARCH_DIR}/install.sh" doctor >/dev/null
  OS_INIT_PROVIDER_MODE=1 OS_INIT_ARCH_LOAD_CONFIG_FILE=0 \
    bash "${ARCH_DIR}/install.sh" status >/dev/null
else
  echo "Skipping executable Arch provider contracts: Bash 4+ required (current ${BASH_VERSION})"
fi

echo "Arch capability checks passed"

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
grep -Fq "https://repo.archlinuxcn.org/\\\$arch" "${ARCH_DIR}/modules/archlinuxcn.sh"
grep -Fq '# >>> OS Init Arch: archlinuxcn >>>' "${ARCH_DIR}/modules/archlinuxcn.sh"
if grep -Eq 'SigLevel[[:space:]]*=[[:space:]]*Optional[[:space:]]+(TrustAll|TrustedOnly)' \
  "${ARCH_DIR}/modules/archlinuxcn.sh"; then
  echo "archlinuxcn must inherit the global pacman signature policy" >&2
  exit 1
fi
grep -Fq 'mihomo_service_ready' "${ARCH_DIR}/modules/proxy/common.sh"
grep -Fq 'https://example.com/your-subscription-url' "${ARCH_DIR}/files/mihomo/config.yaml.tpl"
grep -Fq 'OS_INIT_PROVIDER_MODE' "${ARCH_DIR}/install.sh"
grep -Fq 'restore_config_environment' "${ARCH_DIR}/install.sh"
grep -Fq 'sync_rime_config_tree' "${ARCH_DIR}/modules/desktop/input_method.sh"
grep -Fq 'QT_IM_MODULES=wayland;fcitx;ibus' "${ARCH_DIR}/modules/desktop/input_method.sh"
for key in ENABLE_FCITX5 INPUT_METHOD_ENGINE INSTALL_RIME_CONFIG RIME_CONFIG_REPO RIME_CONFIG_BRANCH RIME_CONFIG_DIR; do
  grep -Fq "${key}" "${ARCH_DIR}/lib/module_registry.sh"
done

for removed_control in lib/plan.sh lib/runner.sh lib/recovery.sh lib/ui.sh preset.sh; do
  if [[ -e "${ARCH_DIR}/${removed_control}" ]]; then
    echo "duplicate Arch control-plane file remains: ${removed_control}" >&2
    exit 1
  fi
done

(
  fixture="$(mktemp)"
  trap 'rm -f "${fixture}"' EXIT
  cat > "${fixture}" <<'EOF'
[options]
SigLevel = Required DatabaseOptional

[archlinuxcn]
SigLevel = Optional TrustAll
Server = https://old.example/archlinuxcn/$arch

[custom]
SigLevel = Optional TrustedOnly
Server = https://custom.example/$arch
EOF
  ARCHLINUXCN_PACMAN_CONF="${fixture}"
  ARCHLINUXCN_SERVER="https://new.example/archlinuxcn/\$arch"
  run_sudo() { "$@"; }
  # shellcheck source=modules/arch/modules/archlinuxcn.sh
  source "${ARCH_DIR}/modules/archlinuxcn.sh"
  remove_archlinuxcn_siglevel
  grep -Fq "Server = https://old.example/archlinuxcn/\$arch" "${fixture}"
  grep -Fq 'SigLevel = Required DatabaseOptional' "${fixture}"
  grep -Fq 'SigLevel = Optional TrustedOnly' "${fixture}"
  rewrite_archlinuxcn_repo "${ARCHLINUXCN_SERVER}"

  if awk '/^\[archlinuxcn\]/{repo=1; next} /^\[/{repo=0} repo && /^[[:space:]]*SigLevel[[:space:]]*=/{found=1} END{exit(found ? 0 : 1)}' "${fixture}"; then
    echo "legacy archlinuxcn SigLevel was not removed" >&2
    exit 1
  fi
  grep -Fq 'SigLevel = Required DatabaseOptional' "${fixture}"
  grep -Fq 'SigLevel = Optional TrustedOnly' "${fixture}"
  grep -Fq "Server = https://new.example/archlinuxcn/\$arch" "${fixture}"
  if grep -Fq 'https://old.example' "${fixture}"; then
    echo "legacy archlinuxcn Server was not replaced" >&2
    exit 1
  fi

  ARCHLINUXCN_SERVER="https://mirrors.ustc.edu.cn/archlinuxcn/\$arch"
  rewrite_archlinuxcn_repo "${ARCHLINUXCN_SERVER}"
  run_sudo() {
    if [[ "$1" == "pacman" ]]; then
      grep -Fq "Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch" "${fixture}"
      return
    fi
    "$@"
  }
  log_info() { :; }
  log_warn() { :; }
  select_working_archlinuxcn_server
  [[ "${ARCHLINUXCN_ACTIVE_SERVER}" == "https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch" ]]
)

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

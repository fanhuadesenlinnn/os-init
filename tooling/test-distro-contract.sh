#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FAMILY="${1:?expected family is required}"
BINARY="${2:-${ROOT_DIR}/os-init-contract}"

fail() {
  printf 'distro contract failed: %s\n' "$*" >&2
  exit 1
}

[[ -x "${BINARY}" ]] || fail "binary is not executable: ${BINARY}"
"${BINARY}" --version | grep -Fq 'os-init '
help_text="$(OS_INIT_LANG=en_US "${BINARY}" --help)"
grep -Fq -- '--system-info' <<<"${help_text}"
grep -Fq 'Configuration precedence:' <<<"${help_text}"
grep -Fq 'OS_INIT_SCRIPT_TIMEOUT' <<<"${help_text}"
grep -Fq 'logs/' <<<"${help_text}"

system_info="$(${BINARY} --system-info)"
grep -Fqx 'goos=linux' <<<"${system_info}"
grep -Fqx "family=${EXPECTED_FAMILY}" <<<"${system_info}" || {
  printf '%s\n' "${system_info}" >&2
  fail "binary detected the wrong Linux family"
}
grep -Eq '^id=.+$' <<<"${system_info}" || fail "binary did not report an OS id"

# shellcheck source=modules/lib.sh
source "${ROOT_DIR}/modules/lib.sh"
[[ "${OS}" == "linux" ]] || fail "shell library detected OS=${OS}"
[[ "${OS_FAMILY}" == "${EXPECTED_FAMILY}" ]] || fail "shell library detected family=${OS_FAMILY}"

calls="$(mktemp "${TMPDIR:-/tmp}/os-init-distro-calls.XXXXXX")"
trap 'rm -f "${calls}"' EXIT
pkg_update() { :; }
sudo_env() { printf '%s\n' "$*" >>"${calls}"; }
arch_install_packages_or_aur() { printf 'arch-install %s\n' "$*" >>"${calls}"; }

pkg_install os-init-contract-package
pkg_remove os-init-contract-package

case "${EXPECTED_FAMILY}" in
  debian)
    grep -Fqx 'apt-get install -y os-init-contract-package' "${calls}"
    grep -Fqx 'apt-get remove -y os-init-contract-package' "${calls}"
    ;;
  redhat)
    grep -Eq '^(dnf|yum) install -y os-init-contract-package$' "${calls}"
    grep -Eq '^(dnf|yum) remove -y os-init-contract-package$' "${calls}"
    ;;
  arch)
    grep -Fqx 'arch-install os-init-contract-package' "${calls}"
    grep -Fqx 'pacman -Rns --noconfirm os-init-contract-package' "${calls}"
    ;;
  *) fail "unsupported expected family: ${EXPECTED_FAMILY}" ;;
esac

if bash "${ROOT_DIR}/modules/provider.sh" execute --script ../outside.sh >/dev/null 2>&1; then
  fail "provider accepted a path traversal"
fi
if bash "${ROOT_DIR}/modules/provider.sh" execute --script terminal/install.sh --operation invalid >/dev/null 2>&1; then
  fail "provider accepted an unsupported operation"
fi

for script in kernel/optimize.sh shell/install.sh terminal/install.sh; do
  if HOME="$(mktemp -d)" OS_INIT_LANG=en_US \
    bash "${ROOT_DIR}/modules/provider.sh" execute --script "${script}" \
      --component __unknown_component__ >/dev/null 2>&1; then
    fail "${script} accepted an unknown component"
  fi
done

printf 'distro contract passed: id=%s family=%s arch=%s\n' \
  "$(sed -n 's/^id=//p' <<<"${system_info}")" "${EXPECTED_FAMILY}" "$(uname -m)"

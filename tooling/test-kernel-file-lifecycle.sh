#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FAMILY="${1:?expected family is required}"

# shellcheck source=modules/lib.sh
source "${ROOT_DIR}/modules/lib.sh"
[[ "$(id -u)" == "0" ]] || { echo "root is required" >&2; exit 1; }
[[ "${OS_FAMILY}" == "${EXPECTED_FAMILY}" ]] || {
  echo "family=${OS_FAMILY}, expected ${EXPECTED_FAMILY}" >&2
  exit 1
}

provider=(bash "${ROOT_DIR}/modules/provider.sh" execute --script kernel/optimize.sh)
components=(limits scheduler ipv4)
args=()
for component in "${components[@]}"; do
  args+=(--component "${component}")
done

"${provider[@]}" "${args[@]}"
"${provider[@]}" "${args[@]}"

[[ -f /etc/security/limits.d/99-os-init.conf ]]
[[ -f /etc/udev/rules.d/60-scheduler.rules ]]
grep -Fq '# os-init -- prefer IPv4 addresses when both A and AAAA exist' /etc/gai.conf

"${provider[@]}" "${args[@]}" --operation uninstall

[[ ! -e /etc/security/limits.d/99-os-init.conf ]]
[[ ! -e /etc/udev/rules.d/60-scheduler.rules ]]
if grep -Fq '# os-init -- prefer IPv4 addresses when both A and AAAA exist' /etc/gai.conf; then
  echo "IPv4 preference marker remained after uninstall" >&2
  exit 1
fi

printf 'kernel file lifecycle passed: family=%s\n' "${OS_FAMILY}"

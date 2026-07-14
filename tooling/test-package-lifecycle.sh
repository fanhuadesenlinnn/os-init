#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FAMILY="${1:?expected family is required}"

# shellcheck source=modules/lib.sh
source "${ROOT_DIR}/modules/lib.sh"
[[ "${OS}" == "linux" ]] || { echo "Linux is required" >&2; exit 1; }
[[ "${OS_FAMILY}" == "${EXPECTED_FAMILY}" ]] || {
  echo "family=${OS_FAMILY}, expected ${EXPECTED_FAMILY}" >&2
  exit 1
}

provider=(bash "${ROOT_DIR}/modules/provider.sh" execute --script terminal/install.sh --component ncdu)

# Establish a clean package and ownership baseline in the disposable runner.
pkg_remove ncdu >/dev/null 2>&1 || true
rm -rf "$(os_init_user_state_dir)"

"${provider[@]}"
command -v ncdu >/dev/null
os_init_package_owned ncdu-package

# Re-install and update must be safe and retain a valid installation.
"${provider[@]}"
"${provider[@]}" --operation update
command -v ncdu >/dev/null

"${provider[@]}" --operation uninstall
if command -v ncdu >/dev/null; then
  echo "ncdu remained installed after an OS Init-owned uninstall" >&2
  exit 1
fi
if os_init_package_owned ncdu-package; then
  echo "ncdu ownership marker remained after uninstall" >&2
  exit 1
fi

printf 'package lifecycle passed: family=%s user=%s\n' "${OS_FAMILY}" "$(id -un)"

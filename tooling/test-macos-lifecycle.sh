#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMULA="${OS_INIT_MACOS_TEST_FORMULA:-nload}"
provider=(bash "${ROOT_DIR}/modules/provider.sh" execute --script macos/cli.sh --component "${FORMULA}")

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS is required" >&2; exit 1; }
command -v brew >/dev/null || { echo "Homebrew is required" >&2; exit 1; }

# GitHub-hosted runners are disposable. Remove a preinstalled copy so this test
# verifies OS Init ownership instead of the preserve-external-install branch.
brew uninstall --formula "${FORMULA}" >/dev/null 2>&1 || true
rm -f "${HOME}/.local/state/os-init/ownership/macos-formula-${FORMULA}"

"${provider[@]}"
brew list --formula "${FORMULA}" >/dev/null
"${provider[@]}"
"${provider[@]}" --operation update
brew list --formula "${FORMULA}" >/dev/null
"${provider[@]}" --operation uninstall
if brew list --formula "${FORMULA}" >/dev/null 2>&1; then
  echo "${FORMULA} remained installed after an OS Init-owned uninstall" >&2
  exit 1
fi

printf 'macOS Homebrew lifecycle passed: formula=%s arch=%s\n' "${FORMULA}" "$(uname -m)"

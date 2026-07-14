#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-${ROOT_DIR}/os-init}"

fail() {
  printf 'headless contract failed: %s\n' "$*" >&2
  exit 1
}

[[ -x "${BINARY}" ]] || fail "binary is not executable: ${BINARY}"

ids="$(${BINARY} module list --format ids)"
grep -Fqx 'terminal-ncdu' <<<"${ids}" || fail "stable terminal-ncdu ID is missing"

catalog="$(${BINARY} module list --format json)"
grep -Fq '"automation_scope"' <<<"${catalog}" || fail "catalog has no automation policy"
grep -Fq '"automation_lifecycle"' <<<"${catalog}" || fail "catalog has no lifecycle policy"

plan="$(${BINARY} module plan --format json terminal-ncdu)"
grep -Fq '"operation": "install"' <<<"${plan}" || fail "plan operation is missing"
grep -Fq '"id": "terminal-ncdu"' <<<"${plan}" || fail "planned module is missing"

if "${BINARY}" module install terminal-ncdu >/dev/null 2>&1; then
  fail "mutating command succeeded without --yes"
fi

help="$(${BINARY} module help)"
grep -Fq -- '--continue-on-error' <<<"${help}" || fail "module help lacks continuation policy"
grep -Fq -- '--junit' <<<"${help}" || fail "module help lacks JUnit reporting"

printf 'headless CLI contracts passed\n'

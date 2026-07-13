#!/usr/bin/env bash
set -euo pipefail

# Stable provider boundary used by the Go control plane. Individual modules
# keep their platform-specific implementation and legacy positional parser
# behind this adapter while the public invocation remains uniform.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'os-init provider: %s\n' "$*" >&2
  exit 2
}

[[ "${1:-}" == "execute" ]] || die "expected execute"
shift

script=""
operation="install"
components=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script)
      [[ $# -ge 2 ]] || die "--script requires a value"
      script="$2"
      shift 2
      ;;
    --operation)
      [[ $# -ge 2 ]] || die "--operation requires a value"
      operation="$2"
      shift 2
      ;;
    --component)
      [[ $# -ge 2 ]] || die "--component requires a value"
      components+=("$2")
      shift 2
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "${script}" ]] || die "--script is required"
case "${script}" in
  /*|*..*) die "script must be relative to modules/" ;;
esac
script_path="${SCRIPT_DIR}/${script}"
[[ -f "${script_path}" ]] || die "script not found: ${script}"

export OS_INIT_PROVIDER_MODE=1
export OS_INIT_PROVIDER_OPERATION="${operation}"

args=()
if [[ ${#components[@]} -gt 0 ]]; then
  args+=("${components[@]}")
fi
case "${operation}" in
  install) ;;
  update) args+=(--update) ;;
  uninstall) args+=(--uninstall) ;;
  *) die "unsupported operation: ${operation}" ;;
esac

if [[ ${#args[@]} -gt 0 ]]; then
  exec bash "${script_path}" "${args[@]}"
fi
exec bash "${script_path}"

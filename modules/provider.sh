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
export OS_INIT_PROVIDER_PROTOCOL=2

requested_protocol="${OS_INIT_PROVIDER_PROTOCOL_REQUEST:-1}"
[[ "${requested_protocol}" == "1" || "${requested_protocol}" == "2" ]] || die "unsupported protocol: ${requested_protocol}"
emit_event() {
  [[ "${requested_protocol}" == "2" ]] || return 0
  printf '@@OS_INIT_EVENT@@%s\n' "$1"
}

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

emit_event "{\"protocol\":2,\"type\":\"started\"}"
set +e
if [[ ${#args[@]} -gt 0 ]]; then
  bash "${script_path}" "${args[@]}"
else
  bash "${script_path}"
fi
exit_code=$?
set -e
status="passed"
[[ ${exit_code} -eq 0 ]] || status="failed"
emit_event "{\"protocol\":2,\"type\":\"result\",\"status\":\"${status}\",\"exit_code\":${exit_code}}"
exit "${exit_code}"

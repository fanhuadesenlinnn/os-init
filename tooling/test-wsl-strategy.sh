#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/os-init-wsl-test.XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT

mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/state"
cat > "${TEST_DIR}/bin/sudo" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|-E|-H|-S) shift ;;
        -p) shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
if [[ "${1:-}" == "install" ]]; then
    shift
    has_D=0
    args=()
    for arg in "$@"; do
        if [[ "${arg}" == "-D" ]]; then
            has_D=1
        else
            args+=("${arg}")
        fi
    done
    if [[ "${has_D}" -eq 1 ]]; then
        target="${args[${#args[@]}-1]}"
        mkdir -p "$(dirname "${target}")"
    fi
    exec /usr/bin/install "${args[@]}"
fi
exec "$@"
EOF
chmod +x "${TEST_DIR}/bin/sudo"
cat > "${TEST_DIR}/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TEST_DIR}/bin/apt-get"

cat > "${TEST_DIR}/wsl.conf" <<'EOF'
[automount]
enabled=true

[boot]
command=/usr/local/bin/example
systemd=false

[user]
default=alice
EOF
cp "${TEST_DIR}/wsl.conf" "${TEST_DIR}/wsl.conf.before"

run_wsl_module() {
    component="$1"
    shift
    PATH="${TEST_DIR}/bin:${PATH}" \
    HOME="${TEST_DIR}/home" \
    OS_INIT_CONFIG_LOADED=1 \
    OS_INIT_CONTEXT_VERSION=1 \
    OS_INIT_TARGET_GOOS=linux \
    OS_INIT_TARGET_FAMILY=debian \
    OS_INIT_TARGET_INIT=unknown \
    OS_INIT_TARGET_ENVIRONMENT=wsl \
    OS_INIT_TARGET_WSL_VERSION=2 \
    OS_INIT_TARGET_WSLG=false \
    OS_INIT_TARGET_USER=alice \
    OS_INIT_TARGET_HOME="${TEST_DIR}/home" \
    OS_INIT_SYSTEM_STATE_DIR="${TEST_DIR}/state" \
    WSL_CONF_PATH="${TEST_DIR}/wsl.conf" \
    bash "${ROOT_DIR}/modules/wsl/install.sh" "${component}" "$@"
}

run_wsl_module systemd >/dev/null
grep -Fq 'enabled=true' "${TEST_DIR}/wsl.conf"
grep -Fq 'command=/usr/local/bin/example' "${TEST_DIR}/wsl.conf"
grep -Fq 'default=alice' "${TEST_DIR}/wsl.conf"
grep -Fq '# >>> OS Init: WSL systemd >>>' "${TEST_DIR}/wsl.conf"
[[ "$(grep -Fc 'systemd=true' "${TEST_DIR}/wsl.conf")" -eq 1 ]]
if grep -Fq 'systemd=false' "${TEST_DIR}/wsl.conf"; then
    echo "WSL systemd migration retained the disabled value" >&2
    exit 1
fi

run_wsl_module systemd --uninstall >/dev/null
cmp -s "${TEST_DIR}/wsl.conf" "${TEST_DIR}/wsl.conf.before"

cat > "${TEST_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "context" && "${2:-}" == "show" ]]; then
    printf 'desktop-linux\n'
    exit 0
fi
exit 1
EOF
chmod +x "${TEST_DIR}/bin/docker"
doctor_output="$(run_wsl_module doctor)"
grep -Fq 'docker=conflict' <<<"${doctor_output}"

grep -Fq 'prepare_wsl_native_docker' "${ROOT_DIR}/modules/docker/install.sh"
grep -Fq 'Docker Desktop WSL Integration' "${ROOT_DIR}/modules/docker/install.sh"
grep -Fq 'wsl_docker_desktop_integration_detected' "${ROOT_DIR}/modules/lib.sh"

printf 'WSL detection, safe systemd merge, restore, filtering, and native Docker checks passed\n'

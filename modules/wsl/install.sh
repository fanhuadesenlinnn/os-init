#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_DIR}/lib.sh"

component="systemd"
for arg in "$@"; do
    case "${arg}" in
        systemd|doctor) component="${arg}" ;;
    esac
done
parse_update_flag "$@"

WSL_CONF_PATH="${WSL_CONF_PATH:-/etc/wsl.conf}"

ensure_wsl_systemd_packages() {
    case "${OS_FAMILY}" in
        debian) pkg_install systemd systemd-sysv ;;
        redhat|arch) pkg_install systemd ;;
        *) die "当前 WSL 发行版家族尚未适配 systemd 软件包：${OS_FAMILY}" ;;
    esac
}

write_wsl_systemd_config() {
    local source_file tmp
    source_file="${WSL_CONF_PATH}"
    tmp="$(mktemp "${TMPDIR:-/tmp}/os-init-wsl-conf.XXXXXX")"
    if [[ -f "${source_file}" ]]; then
        cp -a "${source_file}" "${tmp}"
    else
        : > "${tmp}"
    fi

    awk '
        function managed_block() {
            print "# >>> OS Init: WSL systemd >>>"
            print "systemd=true"
            print "# <<< OS Init: WSL systemd <<<"
        }
        BEGIN { in_boot=0; boot_seen=0; written=0 }
        /^\[boot\][[:space:]]*$/ {
            in_boot=1
            boot_seen=1
            print
            next
        }
        /^\[/ {
            if (in_boot && !written) {
                managed_block()
                written=1
            }
            in_boot=0
            print
            next
        }
        in_boot && /^[[:space:]]*# >>> OS Init: WSL systemd >>>[[:space:]]*$/ {
            next
        }
        in_boot && /^[[:space:]]*# <<< OS Init: WSL systemd <<<[[:space:]]*$/ {
            next
        }
        in_boot && /^[[:space:]]*systemd[[:space:]]*=/ {
            if (!written) {
                managed_block()
                written=1
            }
            next
        }
        { print }
        END {
            if (in_boot && !written) managed_block()
            if (!boot_seen) {
                if (NR > 0) print ""
                print "[boot]"
                managed_block()
            }
        }
    ' "${tmp}" > "${tmp}.new"
    mv "${tmp}.new" "${tmp}"

    install "启用 WSL2 systemd：${WSL_CONF_PATH}"
    os_init_prepare_owned_path "wsl-systemd-config" "${WSL_CONF_PATH}"
    sudo install -m 0644 -D "${tmp}" "${WSL_CONF_PATH}"
    rm -f "${tmp}"
    warn "配置将在 WSL 重启后生效：请从 PowerShell 执行 wsl.exe --shutdown"
}

uninstall_wsl_systemd_config() {
    remove "恢复安装 WSL systemd 前的配置"
    os_init_restore_owned_path "wsl-systemd-config" "${WSL_CONF_PATH}" || true
    warn "恢复将在 WSL 重启后生效：请从 PowerShell 执行 wsl.exe --shutdown"
}

show_wsl_doctor() {
    require_wsl
    printf 'environment=wsl\n'
    printf 'wsl_version=%s\n' "${WSL_VERSION}"
    printf 'init=%s\n' "${INIT_SYSTEM}"
    printf 'wslg=%s\n' "${WSLG}"
    if is_wsl2; then
        printf 'wsl2=ok\n'
    else
        printf 'wsl2=unsupported-for-services\n'
    fi
    if is_systemd; then
        printf 'systemd=active\n'
    else
        printf 'systemd=inactive; install wsl-systemd and restart WSL\n'
    fi
    if wsl_docker_desktop_integration_detected; then
        printf 'docker=conflict; disable Docker Desktop WSL Integration for this distribution\n'
    elif command -v dockerd >/dev/null 2>&1; then
        printf 'docker=native-engine-present\n'
    else
        printf 'docker=not-installed\n'
    fi
    case "${PWD}" in
        /mnt/[a-zA-Z]/*) printf 'workspace=windows-mount; prefer a path under the Linux home directory for development\n' ;;
        *) printf 'workspace=linux-filesystem\n' ;;
    esac
}

case "${component}" in
    doctor)
        show_wsl_doctor
        ;;
    systemd)
        require_wsl2
        if [[ "${UNINSTALL}" == true ]]; then
            uninstall_wsl_systemd_config
        else
            ensure_wsl_systemd_packages
            write_wsl_systemd_config
        fi
        ;;
    *)
        die "未知 WSL 组件：${component}"
        ;;
esac

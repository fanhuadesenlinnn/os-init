#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_FAMILY="${1:?expected family is required}"

if [[ "${EXPECTED_FAMILY}" == "arch" && "${OS_INIT_CONTAINER_TEST:-0}" == "1" ]]; then
  # pacman 7 enables syscall sandboxing that is unavailable in ordinary Docker
  # seccomp profiles. Disable only that inner sandbox in this disposable test
  # container; package signatures and repository checks remain enabled.
  sed -i 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/' /etc/pacman.conf
fi

export HOME=/root
bash "${ROOT_DIR}/tooling/test-package-lifecycle.sh" "${EXPECTED_FAMILY}"
bash "${ROOT_DIR}/tooling/test-kernel-file-lifecycle.sh" "${EXPECTED_FAMILY}"

# Repeat the same lifecycle as a normal user with passwordless sudo. The
# container is disposable and the sudo rule exists only for this test.
case "${EXPECTED_FAMILY}" in
  debian)
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y sudo passwd >/dev/null
    ;;
  redhat)
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y sudo shadow-utils >/dev/null
    else
      yum install -y sudo shadow-utils >/dev/null
    fi
    ;;
  arch)
    pacman -Sy --needed --noconfirm sudo shadow >/dev/null
    ;;
  *) echo "unsupported family: ${EXPECTED_FAMILY}" >&2; exit 1 ;;
esac

useradd -m -s /bin/bash osinitci
install -d -m 0750 /etc/sudoers.d
printf 'osinitci ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/osinitci
chmod 0440 /etc/sudoers.d/osinitci

sudo -u osinitci -H env OS_INIT_LANG=en_US \
  bash "${ROOT_DIR}/tooling/test-package-lifecycle.sh" "${EXPECTED_FAMILY}"

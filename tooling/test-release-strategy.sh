#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/release.yml"
SYSTEM_WORKFLOW="${ROOT_DIR}/.github/workflows/system-integration.yml"
notes="$(mktemp "${TMPDIR:-/tmp}/os-init-release-test.XXXXXX")"
trap 'rm -f "${notes}"' EXIT

bash "${ROOT_DIR}/tooling/release-notes.sh" v0.27.2 "${ROOT_DIR}/CHANGELOG.md" > "${notes}"
grep -Fq '## OS Init v0.27.2' "${notes}"
grep -Fq 'Replace the incompatible mise Go mirror default' "${notes}"
if grep -Fq 'Restore the Arch provider preflight check' "${notes}"; then
    echo 'release notes leaked content from the previous version' >&2
    exit 1
fi
if bash "${ROOT_DIR}/tooling/release-notes.sh" v999.0.0 "${ROOT_DIR}/CHANGELOG.md" >/dev/null 2>&1; then
    echo 'release notes should fail when the tag is absent from CHANGELOG.md' >&2
    exit 1
fi

if grep -Fq 'release/v' "${WORKFLOW}"; then
    echo 'release branches must not publish releases' >&2
    exit 1
fi
grep -Fq "startsWith(github.ref, 'refs/tags/v')" "${WORKFLOW}"
# The workflow expression is intentionally matched literally.
# shellcheck disable=SC2016
grep -Fq 'bash tooling/release-notes.sh "${RELEASE_TAG}"' "${WORKFLOW}"
grep -Fq 'runner: [macos-15, macos-15-intel]' "${WORKFLOW}"
grep -Fq 'manjarolinux/base:latest' "${WORKFLOW}"
grep -Fq 'bash tooling/test-distro-contract.sh' "${WORKFLOW}"
grep -Fq 'bash tooling/run-linux-lifecycle.sh' "${SYSTEM_WORKFLOW}"
grep -Fq 'bash tooling/test-macos-lifecycle.sh' "${SYSTEM_WORKFLOW}"
grep -Fq 'workflow_call:' "${SYSTEM_WORKFLOW}"
grep -Fq 'needs: [test, macos-test, linux-matrix-test, system-integration]' "${WORKFLOW}"
grep -Fq "startsWith(github.ref, 'refs/tags/v')" "${WORKFLOW}"

printf 'release strategy checks passed\n'

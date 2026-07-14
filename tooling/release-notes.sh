#!/usr/bin/env bash
set -euo pipefail

release_tag="${1:-}"
changelog="${2:-CHANGELOG.md}"

[[ "${release_tag}" == v* ]] || {
    printf 'release-notes: expected a v* tag, got %q\n' "${release_tag}" >&2
    exit 1
}
[[ -f "${changelog}" ]] || {
    printf 'release-notes: changelog not found: %s\n' "${changelog}" >&2
    exit 1
}

section="$(mktemp "${TMPDIR:-/tmp}/os-init-release-notes.XXXXXX")"
trap 'rm -f "${section}"' EXIT

awk -v tag="${release_tag}" '
    $0 ~ "^## " tag "([[:space:]]|$)" { found=1; next }
    found && /^## v/ { exit }
    found { print }
    END { if (!found) exit 1 }
' "${changelog}" > "${section}" || {
    printf 'release-notes: %s is missing from %s\n' "${release_tag}" "${changelog}" >&2
    exit 1
}
[[ -s "${section}" ]] || {
    printf 'release-notes: %s has an empty changelog section\n' "${release_tag}" >&2
    exit 1
}

printf '## OS Init %s\n\n' "${release_tag}"
printf '面向中国大陆网络环境的 macOS / Linux 系统初始化发布包。\n\n'
cat "${section}"
printf '\n### 发布包\n\n'
# Markdown backticks are literal release-note content.
# shellcheck disable=SC2016
printf '%s\n' \
    '- `os-init_linux_amd64.tar.gz`' \
    '- `os-init_linux_arm64.tar.gz`' \
    '- `os-init_darwin_amd64.tar.gz`' \
    '- `os-init_darwin_arm64.tar.gz`' \
    '- `checksums.txt`'

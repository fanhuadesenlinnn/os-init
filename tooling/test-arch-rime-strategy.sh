#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/os-init-rime-test.XXXXXX")"
trap 'rm -rf "${TEST_ROOT}"' EXIT

export HOME="${TEST_ROOT}/home"
export DRY_RUN=0
mkdir -p "${HOME}" "${TEST_ROOT}/source/opencc" "${TEST_ROOT}/target/sample.userdb" "${TEST_ROOT}/target/sync"

# shellcheck disable=SC1091
source "${ROOT_DIR}/modules/arch/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/modules/arch/lib/files.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/modules/arch/modules/desktop/input_method.sh"

state_root() { printf '%s' "${TEST_ROOT}/state"; }

cat > "${TEST_ROOT}/source/default.custom.yaml" <<'EOF'
patch:
  schema_list:
    - schema: luna_pinyin_simp
    - schema: double_pinyin_flypy
    - schema: numbers
  menu/page_size: 9
EOF
printf 'public example\n' > "${TEST_ROOT}/source/custom_phrase.txt"
printf 'new opencc\n' > "${TEST_ROOT}/source/opencc/example.txt"
printf 'old config\n' > "${TEST_ROOT}/target/default.custom.yaml"
printf 'private phrase\n' > "${TEST_ROOT}/target/custom_phrase.txt"
printf 'learned words\n' > "${TEST_ROOT}/target/sample.userdb/data"
printf 'sync state\n' > "${TEST_ROOT}/target/sync/state"
printf 'machine state\n' > "${TEST_ROOT}/target/installation.yaml"

select_rime_schema_in_file "${TEST_ROOT}/source/default.custom.yaml" double_pinyin_flypy
sync_rime_config_tree "${TEST_ROOT}/source" "${TEST_ROOT}/target"

first_schema="$(sed -n 's/^[[:space:]]*- schema: //p' "${TEST_ROOT}/target/default.custom.yaml" | head -1)"
[[ "${first_schema}" == "double_pinyin_flypy" ]]
grep -Fqx 'private phrase' "${TEST_ROOT}/target/custom_phrase.txt"
grep -Fqx 'learned words' "${TEST_ROOT}/target/sample.userdb/data"
grep -Fqx 'sync state' "${TEST_ROOT}/target/sync/state"
grep -Fqx 'machine state' "${TEST_ROOT}/target/installation.yaml"
grep -Fqx 'new opencc' "${TEST_ROOT}/target/opencc/example.txt"
find "${TEST_ROOT}/state/backups/rime-config" -type f -name default.custom.yaml -exec grep -Fqx 'old config' {} \;

mkdir -p "${HOME}/.config/fcitx5"
cat > "${HOME}/.config/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Existing
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[GroupOrder]
0=Existing
EOF
RIME_SCHEMA=double_pinyin_flypy configure_fcitx5_rime_profile
grep -Fqx 'DefaultIM=rime' "${HOME}/.config/fcitx5/profile"
grep -Fqx 'Name=mozc' "${HOME}/.config/fcitx5/profile"
[[ "$(grep -Fxc 'Name=rime' "${HOME}/.config/fcitx5/profile")" -eq 1 ]]

backup_file="$(find "${TEST_ROOT}/state/backups/rime-config" -type f -name default.custom.yaml -print -quit)"
[[ -n "${backup_file}" ]]
grep -Fqx 'old config' "${backup_file}"

echo "Arch Rime safe-merge, schema-selection, and Fcitx5 profile checks passed"

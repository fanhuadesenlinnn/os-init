#!/usr/bin/env bash
# 文件写入公共操作：统一临时文件、备份、安装权限、root 写入和模板渲染。

install_file_from_temp() {
  local tmp_file="$1" target="$2" mode="${3:-0644}"
  [[ -n "${tmp_file}" && -f "${tmp_file}" ]] || die "临时文件不存在：${tmp_file}"
  [[ -n "${target}" ]] || die "目标文件路径为空"

  mkdir -p "$(dirname "${target}")"
  backup_path "${target}"
  install -m "${mode}" "${tmp_file}" "${target}"
}

install_root_file_from_temp() {
  local tmp_file="$1" target="$2" mode="${3:-0644}"
  [[ -n "${tmp_file}" && -f "${tmp_file}" ]] || die "临时文件不存在：${tmp_file}"
  [[ -n "${target}" ]] || die "root 目标文件路径为空"

  run_sudo mkdir -p "$(dirname "${target}")"
  backup_file_root "${target}"
  run_sudo install -m "${mode}" "${tmp_file}" "${target}"
}

write_file_from_stdin() {
  local target="$1" mode="${2:-0644}" tmp_file
  [[ -n "${target}" ]] || die "目标文件路径为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write ${target}"
    return 0
  fi

  tmp_file="$(mktemp)"
  if ! cat > "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
  install_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

write_root_file_from_stdin() {
  local target="$1" mode="${2:-0644}" tmp_file
  [[ -n "${target}" ]] || die "root 目标文件路径为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo write ${target}"
    return 0
  fi

  tmp_file="$(mktemp)"
  if ! cat > "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
  install_root_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

render_template_file() {
  local template="$1" target="$2" mode="${3:-0644}" tmp_file
  shift 3 || true

  [[ -f "${template}" ]] || die "模板文件不存在：${template}"
  [[ -n "${target}" ]] || die "模板目标文件路径为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ render ${template} -> ${target}"
    return 0
  fi

  tmp_file="$(mktemp)"
  if [[ "$#" -gt 0 ]]; then
    sed "$@" "${template}" > "${tmp_file}" || {
      rm -f "${tmp_file}"
      return 1
    }
  else
    cp -a "${template}" "${tmp_file}" || {
      rm -f "${tmp_file}"
      return 1
    }
  fi
  install_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

render_template_root_file() {
  local template="$1" target="$2" mode="${3:-0644}" tmp_file
  shift 3 || true

  [[ -f "${template}" ]] || die "模板文件不存在：${template}"
  [[ -n "${target}" ]] || die "root 模板目标文件路径为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ sudo render ${template} -> ${target}"
    return 0
  fi

  tmp_file="$(mktemp)"
  if [[ "$#" -gt 0 ]]; then
    sed "$@" "${template}" > "${tmp_file}" || {
      rm -f "${tmp_file}"
      return 1
    }
  else
    cp -a "${template}" "${tmp_file}" || {
      rm -f "${tmp_file}"
      return 1
    }
  fi
  install_root_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

managed_block_begin() {
  local name="$1"
  [[ -n "${name}" ]] || die "managed block 名称为空"
  printf '# >>> ArchDevKit: %s >>>' "${name}"
}

managed_block_end() {
  local name="$1"
  [[ -n "${name}" ]] || die "managed block 名称为空"
  printf '# <<< ArchDevKit: %s <<<' "${name}"
}

remove_managed_block() {
  local target="$1" name="$2" mode="${3:-0644}" tmp_file begin end
  [[ -n "${target}" ]] || die "managed block 目标文件路径为空"
  [[ -n "${name}" ]] || die "managed block 名称为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ remove managed block ${name} from ${target}"
    return 0
  fi

  [[ -f "${target}" ]] || return 0

  begin="$(managed_block_begin "${name}")"
  end="$(managed_block_end "${name}")"
  tmp_file="$(mktemp)"
  if awk -v begin="${begin}" -v end="${end}" '
    $0 == begin {skip = 1; found = 1; next}
    $0 == end {skip = 0; next}
    skip != 1 {print}
    END {if (skip == 1) exit 2; if (found != 1) exit 3}
  ' "${target}" > "${tmp_file}"; then
    :
  else
    local rc=$?
    rm -f "${tmp_file}"
    [[ "${rc}" -eq 3 ]] && return 0
    die "managed block ${name} 缺少结束标记，已拒绝修改：${target}"
  fi

  install_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

write_managed_block_from_stdin() {
  local target="$1" name="$2" mode="${3:-0644}" tmp_file begin end
  [[ -n "${target}" ]] || die "managed block 目标文件路径为空"
  [[ -n "${name}" ]] || die "managed block 名称为空"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ write managed block ${name} -> ${target}"
    cat >/dev/null
    return 0
  fi

  begin="$(managed_block_begin "${name}")"
  end="$(managed_block_end "${name}")"
  mkdir -p "$(dirname "${target}")"
  [[ -f "${target}" ]] || touch "${target}"

  tmp_file="$(mktemp)"
  if ! awk -v begin="${begin}" -v end="${end}" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    skip != 1 {print}
    END {if (skip == 1) exit 2}
  ' "${target}" > "${tmp_file}"; then
    rm -f "${tmp_file}"
    die "managed block ${name} 缺少结束标记，已拒绝修改：${target}"
  fi

  {
    printf '\n%s\n' "${begin}"
    cat
    printf '%s\n' "${end}"
  } >> "${tmp_file}"

  install_file_from_temp "${tmp_file}" "${target}" "${mode}"
  rm -f "${tmp_file}"
}

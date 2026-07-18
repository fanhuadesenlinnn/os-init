#!/usr/bin/env bash
# Ops Toolkit 模块
# 克隆/更新运维脚本仓库，并写入稳定命令入口。

install_ops_toolkit() {
  if is_done "ops_toolkit"; then
    log_info "Ops Toolkit 已处理，跳过"
    return 0
  fi

  log_info "开始安装 Ops Toolkit"
  install_or_update_ops_toolkit_repo
  install_ops_toolkit_dispatcher
  install_ops_toolkit_script_commands
  install_ops_toolkit_shell_path
  verify_ops_toolkit

  mark_done "ops_toolkit"
  log_info "Ops Toolkit 安装完成"
}

install_or_update_ops_toolkit_repo() {
  local repo_dir="${OPS_TOOLKIT_DIR}" repo_url="${OPS_TOOLKIT_REPO}" branch="${OPS_TOOLKIT_BRANCH:-}" actual_url
  [[ -n "${repo_dir}" ]] || die "OPS_TOOLKIT_DIR 不能为空"
  [[ -n "${repo_url}" ]] || die "OPS_TOOLKIT_REPO 不能为空"

  ensure_git_command
  actual_url="$(github_proxy_url "${repo_url}")"

  if [[ -d "${repo_dir}/.git" ]]; then
    log_info "更新 Ops Toolkit 仓库：${repo_dir}"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      printf '+ git -C %q -c %q pull --ff-only\n' "${repo_dir}" "remote.origin.url=${actual_url}"
      return 0
    fi
    GIT_TERMINAL_PROMPT=0 git -C "${repo_dir}" -c "remote.origin.url=${actual_url}" pull --ff-only
    git -C "${repo_dir}" remote set-url origin "${repo_url}"
    return 0
  fi

  if [[ -e "${repo_dir}" ]]; then
    log_warn "目标目录已存在但不是 Git 仓库，将先备份：${repo_dir}"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      echo "+ backup ${repo_dir}"
    else
      backup_path "${repo_dir}"
    fi
  fi

  log_info "克隆 Ops Toolkit：${repo_url}"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    if [[ -n "${branch}" ]]; then
      printf '+ git clone --depth=1 -b %q %q %q\n' "${branch}" "${actual_url}" "${repo_dir}"
    else
      printf '+ git clone --depth=1 %q %q\n' "${actual_url}" "${repo_dir}"
    fi
    return 0
  fi

  mkdir -p "$(dirname "${repo_dir}")"
  if [[ -n "${branch}" ]]; then
    git clone --depth=1 -b "${branch}" "${actual_url}" "${repo_dir}"
  else
    git clone --depth=1 "${actual_url}" "${repo_dir}"
  fi
  [[ "${actual_url}" == "${repo_url}" ]] || git -C "${repo_dir}" remote set-url origin "${repo_url}"
}

ops_toolkit_script_name() {
  local script_path="$1" base
  base="$(basename "${script_path}")"
  printf '%s' "${base%.sh}"
}

ops_toolkit_scripts() {
  local repo_dir="${OPS_TOOLKIT_DIR}"
  [[ -d "${repo_dir}" ]] || return 0
  find "${repo_dir}" -maxdepth 1 -type f -name '*.sh' | sort
}

ops_toolkit_valid_command_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

shell_literal() {
  printf '%q' "$1"
}

install_ops_toolkit_dispatcher() {
  local dispatcher="${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" repo_dir bin_dir command_name proxy_url repo_url
  repo_dir="$(shell_literal "${OPS_TOOLKIT_DIR}")"
  bin_dir="$(shell_literal "${OPS_TOOLKIT_BIN_DIR}")"
  command_name="$(shell_literal "${OPS_TOOLKIT_COMMAND}")"
  proxy_url="$(shell_literal "$(github_proxy_url "${OPS_TOOLKIT_REPO}")")"
  repo_url="$(shell_literal "${OPS_TOOLKIT_REPO}")"

  log_info "写入 Ops Toolkit 命令入口：${dispatcher}"
  write_file_from_stdin "${dispatcher}" 0755 <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

OPS_TOOLKIT_DIR=${repo_dir}
OPS_TOOLKIT_BIN_DIR=${bin_dir}
OPS_TOOLKIT_COMMAND=${command_name}
OPS_TOOLKIT_PROXY_URL=${proxy_url}
OPS_TOOLKIT_REPO_URL=${repo_url}

list_scripts() {
  [[ -d "\${OPS_TOOLKIT_DIR}" ]] || return 0
  find "\${OPS_TOOLKIT_DIR}" -maxdepth 1 -type f -name '*.sh' | while IFS= read -r script; do
    base="\$(basename "\${script}")"
    printf '%s\n' "\${base%.sh}"
  done | sort
}

show_help() {
  cat <<HELP
Ops Toolkit command dispatcher

Usage:
  \${OPS_TOOLKIT_COMMAND} list
  \${OPS_TOOLKIT_COMMAND} update
  \${OPS_TOOLKIT_COMMAND} path
  \${OPS_TOOLKIT_COMMAND} <script-name> [args...]

Examples:
  \${OPS_TOOLKIT_COMMAND} sshm --list
  \${OPS_TOOLKIT_COMMAND} linux-admin-toolkit --help

Direct script commands are also installed for scripts present at setup time,
for example: sshm, linux-admin-toolkit.
HELP
}

case "\${1:-help}" in
  help|-h|--help)
    show_help
    ;;
  list|--list)
    list_scripts
    ;;
  path)
    printf '%s\n' "\${OPS_TOOLKIT_DIR}"
    ;;
  update)
    GIT_TERMINAL_PROMPT=0 git -C "\${OPS_TOOLKIT_DIR}" -c "remote.origin.url=\${OPS_TOOLKIT_PROXY_URL}" pull --ff-only
    git -C "\${OPS_TOOLKIT_DIR}" remote set-url origin "\${OPS_TOOLKIT_REPO_URL}"
    ;;
  *)
    script_name="\${1%.sh}"
    shift
    if [[ ! "\${script_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      printf '非法 Ops Toolkit 脚本名：%s\n' "\${script_name}" >&2
      exit 2
    fi
    script_path="\${OPS_TOOLKIT_DIR}/\${script_name}.sh"
    if [[ ! -f "\${script_path}" ]]; then
      printf '未知 Ops Toolkit 脚本：%s\n\n' "\${script_name}" >&2
      printf '可用脚本：\n' >&2
      list_scripts >&2
      exit 127
    fi
    exec bash "\${script_path}" "\$@"
    ;;
esac
EOF
}

install_ops_toolkit_script_commands() {
  local script script_name wrapper dispatcher="${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" dispatcher_literal script_name_literal count=0

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "+ mkdir -p ${OPS_TOOLKIT_BIN_DIR}"
  else
    mkdir -p "${OPS_TOOLKIT_BIN_DIR}"
  fi
  dispatcher_literal="$(shell_literal "${dispatcher}")"
  while IFS= read -r script; do
    [[ -n "${script}" ]] || continue
    script_name="$(ops_toolkit_script_name "${script}")"
    [[ "${script_name}" == "${OPS_TOOLKIT_COMMAND}" ]] && continue
    if ! ops_toolkit_valid_command_name "${script_name}"; then
      log_warn "跳过非法脚本命令名：${script_name}"
      continue
    fi
    if ops_toolkit_sensitive_command_name "${script_name}"; then
      log_warn "跳过会遮蔽安全敏感命令的脚本：${script_name}"
      continue
    fi
    script_name_literal="$(shell_literal "${script_name}")"
    wrapper="${OPS_TOOLKIT_BIN_DIR}/${script_name}"
    log_info "写入 Ops Toolkit 脚本命令：${wrapper}"
    write_file_from_stdin "${wrapper}" 0755 <<EOF
#!/usr/bin/env bash
exec ${dispatcher_literal} ${script_name_literal} "\$@"
EOF
    count=$((count + 1))
  done < <(ops_toolkit_scripts)

  if [[ "${count}" -eq 0 ]]; then
    log_warn "未发现 Ops Toolkit .sh 脚本；仓库更新后可使用 ${OPS_TOOLKIT_COMMAND} list 查看"
  fi
}

ops_toolkit_sensitive_command_name() {
  case "$1" in
    sudo|su|doas|ssh|scp|sftp|git|bash|sh|zsh|fish|pacman|paru|yay|systemctl|journalctl) return 0 ;;
    *) return 1 ;;
  esac
}

install_ops_toolkit_shell_path() {
  local rc path_line="export PATH=\"\$HOME/.local/bin:\$PATH\""
  for rc in "${HOME}/.profile" "${HOME}/.zprofile" "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    append_unique_line "${path_line}" "${rc}"
  done
}

verify_ops_toolkit() {
  log_info "验证 Ops Toolkit"
  [[ -d "${OPS_TOOLKIT_DIR}/.git" || "${DRY_RUN:-0}" -eq 1 ]] || die "Ops Toolkit 仓库不存在：${OPS_TOOLKIT_DIR}"
  [[ -x "${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" || "${DRY_RUN:-0}" -eq 1 ]] || die "Ops Toolkit 命令入口不存在：${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}"
  run_cmd "${OPS_TOOLKIT_BIN_DIR}/${OPS_TOOLKIT_COMMAND}" list || true
  log_info "后续更新：${OPS_TOOLKIT_COMMAND} update"
}

ensure_ops_toolkit() {
  if [[ "${ENABLE_OPS_TOOLKIT:-0}" -eq 1 ]]; then
    install_ops_toolkit
  else
    log_info "当前配置未启用 Ops Toolkit，跳过"
  fi
}

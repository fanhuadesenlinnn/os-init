#!/usr/bin/env bash
# 基础环境模块
# 只负责官方仓库中的最小下载、解压和诊断基础。现代 CLI、Git、
# tmux 和编译工具由各自模块管理。

base_packages() {
  echo "curl wget less unzip tar gzip xz jq rsync pciutils ca-certificates"
}

base_tool_commands() {
  cat <<'EOF'
curl:curl
wget:wget
less:less
unzip:unzip
tar:tar
gzip:gzip
xz:xz
jq:jq
rsync:rsync
pciutils:lspci
EOF
}

show_base_tool_status_table() {
  local name command_path command_name missing=0

  echo "[基础工具状态]"
  printf "%-18s %-8s %s\n" "工具" "状态" "命令路径"
  printf "%-18s %-8s %s\n" "----" "----" "----"
  while IFS=: read -r name command_name; do
    [[ -n "${name}" ]] || continue
    if command_path="$(command -v "${command_name}" 2>/dev/null)"; then
      printf "%-18s %-8s %s\n" "${name}" "ok" "${command_path}"
    else
      printf "%-18s %-8s 缺少命令：%s\n" "${name}" "missing" "${command_name}"
      missing=$((missing + 1))
    fi
  done < <(base_tool_commands)

  if [[ "${missing}" -gt 0 ]]; then
    log_warn "缺少 ${missing} 个基础工具命令，请重新运行 OS Init 并更新 Arch 最小基础"
  else
    log_info "基础工具命令检测通过"
  fi
}

install_base() {
  if is_done "base"; then
    log_info "基础环境已处理，跳过"
    return 0
  fi

  local packages
  read -r -a packages <<<"$(base_packages)"

  require_arch
  log_info "开始安装基础环境"
  pacman_update

  install_packages_or_aur "${packages[@]}"

  mark_done "base"
  log_info "基础环境安装完成"
}

ensure_base() {
  if ! is_done "base"; then
    install_base
  fi
}

#!/usr/bin/env bash
# 基础环境模块
# 负责安装最基础的命令行工具、编译工具和排障工具。

base_packages() {
  echo "base-devel git curl wget less unzip tar gzip xz jq rsync rclone net-tools iotop iftop nethogs ripgrep fd fzf bat eza dust bottom procs bandwhich sd hyperfine just tmux pciutils openssh ca-certificates"
}

base_tool_commands() {
  cat <<'EOF'
base-devel:make
git:git
curl:curl
wget:wget
less:less
unzip:unzip
tar:tar
gzip:gzip
xz:xz
jq:jq
rsync:rsync
rclone:rclone
net-tools:ifconfig
iotop:iotop
iftop:iftop
nethogs:nethogs
ripgrep:rg
fd:fd
fzf:fzf
bat:bat
eza:eza
dust:dust
bottom:btm
procs:procs
bandwhich:bandwhich
sd:sd
hyperfine:hyperfine
just:just
tmux:tmux
pciutils:lspci
openssh:ssh
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
    log_warn "缺少 ${missing} 个基础工具命令，请重新运行 OS Init 并更新 Arch 基础环境"
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

  pacman_install "${packages[@]}"
  install_tmux_config

  mark_done "base"
  log_info "基础环境安装完成"
}

ensure_base() {
  if ! is_done "base"; then
    install_base
  fi
}

install_tmux_config() {
  local template="${SCRIPT_DIR}/files/tmux/tmux.conf"

  log_info "配置 tmux：${HOME}/.tmux.conf"
  render_template_file "${template}" "${HOME}/.tmux.conf" 0644
}

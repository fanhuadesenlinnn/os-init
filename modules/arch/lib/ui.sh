#!/usr/bin/env bash
# Minimal direct-entry menu. The main OS Init TUI remains the primary UI and
# owns cross-platform presets and custom multi-module selection.

ask_arch_target() {
  local answer
  while true; do
    cat <<'EOF'

Arch Linux 能力：
  1. base           基础命令行工具和 tmux
  2. aur            paru/yay（优先使用 archlinuxcn 预编译包）
  3. archlinuxcn    软件源、keyring 和 mirrorlist
  4. dns            systemd-resolved DNS
  5. git            Git / GitHub CLI / OpenSSH
  6. ops-toolkit    运维脚本命令入口
  7. fonts          中文、Emoji、Nerd Font 和 Monaco
  8. mihomo         Mihomo、配置预检、systemd 与 MetaCubeXD
  9. desktop        Hyprland 完整桌面

dev/workstation 组合请从 OS Init 主菜单选择。
EOF
    read -r -p "请选择 [1-9]: " answer
    case "${answer}" in
      1|base) echo base; return ;;
      2|aur) echo aur; return ;;
      3|archlinuxcn) echo archlinuxcn; return ;;
      4|dns) echo dns; return ;;
      5|git) echo git; return ;;
      6|ops|ops-toolkit) echo ops-toolkit; return ;;
      7|fonts) echo fonts; return ;;
      8|proxy|mihomo) echo mihomo; return ;;
      9|desktop|hyprland) echo desktop; return ;;
      *) log_warn "请输入 1-9 或能力名称" ;;
    esac
  done
}

show_menu() {
  TARGET="$(ask_arch_target)"
  confirm_and_run_target "${TARGET}"
}

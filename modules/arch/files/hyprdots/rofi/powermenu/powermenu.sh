#!/usr/bin/env bash

set -euo pipefail

dir="$HOME/.config/rofi/powermenu"
theme="style"
uptime_text="$(uptime -p | sed -e 's/up //g' -e 's/hour/hr/g' -e 's/minute/min/g')"

hibernate="Hibernate"
shutdown="Shutdown"
reboot="Reboot"
lock="Lock"
suspend="Suspend"
logout="Logout"
yes="yes"
no="no"

rofi_cmd() {
  rofi -dmenu \
    -p "$USER" \
    -mesg "Uptime: $uptime_text" \
    -theme "$dir/$theme.rasi"
}

confirm_cmd() {
  rofi -markup-rows -dmenu \
    -p "Confirmation" \
    -mesg "Are you sure?" \
    -theme "$dir/confirmation.rasi"
}

confirm_exit() {
  printf "<span foreground='#a6d189'>%s</span>\n<span foreground='#e78284'>%s</span>\n" "$yes" "$no" | confirm_cmd
}

run_rofi() {
  printf "%s\n%s\n%s\n%s\n%s\n%s\n" "$shutdown" "$reboot" "$lock" "$suspend" "$hibernate" "$logout" | rofi_cmd
}

run_confirmed() {
  local action="$1"
  local selected
  selected="$(confirm_exit)"

  [[ "$selected" =~ $yes ]] || exit 0

  case "$action" in
  --shutdown) systemctl poweroff ;;
  --reboot) systemctl reboot ;;
  --hibernate) systemctl hibernate ;;
  --suspend)
    command -v mpc >/dev/null 2>&1 && mpc -q pause || true
    command -v amixer >/dev/null 2>&1 && amixer set Master mute || true
    systemctl suspend
    ;;
  --logout) hyprctl dispatch exit ;;
  esac
}

chosen="$(run_rofi)"
case "$chosen" in
"$shutdown") run_confirmed --shutdown ;;
"$reboot") run_confirmed --reboot ;;
"$hibernate") run_confirmed --hibernate ;;
"$lock") hyprlock ;;
"$suspend") run_confirmed --suspend ;;
"$logout") run_confirmed --logout ;;
esac

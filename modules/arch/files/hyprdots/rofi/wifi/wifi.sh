#!/usr/bin/env bash

set -euo pipefail

LIST_THEME="$HOME/.config/rofi/wifi/list.rasi"
ENABLE_THEME="$HOME/.config/rofi/wifi/enable.rasi"
SSID_THEME="$HOME/.config/rofi/wifi/ssid.rasi"
PASSWORD_THEME="$HOME/.config/rofi/wifi/password.rasi"
TERMINAL="${TERMINAL:-${HOME}/.local/bin/os-init-arch-terminal}"

notify-send -t 3000 -i info "Wi-Fi" "Checking networks..." || true

enable_wifi_menu() {
  printf 'Enable Wi-Fi\n' | rofi -dmenu -theme "$ENABLE_THEME"
}

prompt_ssid() {
  rofi -dmenu -p "SSID" -theme "$SSID_THEME"
}

prompt_password() {
  rofi -password -dmenu -p "Password" -theme "$PASSWORD_THEME"
}

wifi_status="$(nmcli -t -f WIFI general | tail -n1)"

if [[ "$wifi_status" == "disabled" ]]; then
  choice="$(enable_wifi_menu)"
  if [[ "$choice" == "Enable Wi-Fi" ]]; then
    nmcli radio wifi on
  fi
  exit 0
fi

connected_ssid="$(nmcli -t -f active,ssid dev wifi | awk -F: '$1 == "yes" {print $2; exit}')"
wifi_list="$(
  nmcli -t -f ssid,security dev wifi |
    awk -F: '
      $1 != "" {
        icon = ($2 ~ /WPA|WEP|802\.1X/) ? "[lock]" : "[open]";
        printf "%s %s\n", icon, $1;
      }
    ' |
    sort -u
)"

menu_items="Disable Wi-Fi"
if [[ -n "$connected_ssid" ]]; then
  menu_items="${menu_items}"$'\n'"Connected to $connected_ssid"
fi
menu_items="${menu_items}"$'\n'"Manual Setup"
if [[ -n "$wifi_list" ]]; then
  menu_items="${menu_items}"$'\n'"$wifi_list"
fi

choice="$(printf '%s\n' "$menu_items" | rofi -markup-rows -dmenu -theme "$LIST_THEME")"
choice="$(printf '%s' "$choice" | sed -E 's/^\[(lock|open)\][[:space:]]+//')"

case "$choice" in
"Disable Wi-Fi")
  nmcli radio wifi off
  ;;
"Manual Setup")
  ssid="$(prompt_ssid)"
  [[ -z "$ssid" ]] && exit 0
  password="$(prompt_password)"
  nmcli dev wifi connect "$ssid" hidden yes password "$password"
  ;;
"Connected to "*)
  "$TERMINAL" -e sh -c "nmcli dev wifi show-password; read -r -p 'Press Return to close...'"
  ;;
"")
  exit 0
  ;;
*)
  password="$(prompt_password)"
  if [[ -n "$password" ]]; then
    nmcli dev wifi connect "$choice" password "$password"
  else
    nmcli dev wifi connect "$choice"
  fi
  ;;
esac

#!/usr/bin/env bash

set -euo pipefail

if [[ -z "$(wl-paste 2>/dev/null || true)" ]]; then
  dunstify -h string:x-dunst-stack-tag:clip_notif -t 4000 -u critical "Clipboard Manager" "Clipboard is empty"
  exit 0
fi

dir="$HOME/.config/rofi/clipboard"
wipe_label="Wipe Clipboard"

choice="$(
  printf '%s\n%s\n' "$wipe_label" "$(cliphist list)" |
    rofi -markup-rows -dmenu -display-columns 2 -theme "$dir/clipboard.rasi"
)"

case "$choice" in
"$wipe_label")
  confirmation="$(
    printf "<span foreground='#a6d189'>yes</span>\n<span foreground='#e78284'>no</span>\n" |
      rofi -markup-rows -dmenu -p "Confirmation" -mesg "Are you sure?" -theme "$dir/confirmation.rasi"
  )"

  if [[ "$confirmation" =~ yes ]]; then
    cliphist wipe
    wl-copy -c
    dunstify -h string:x-dunst-stack-tag:clip_notif -t 4000 -u critical "Clipboard Manager" "Clipboard has been wiped"
  fi
  ;;
"")
  exit 0
  ;;
*)
  cliphist decode "$choice" | wl-copy
  if command -v wtype >/dev/null 2>&1; then
    wtype -M ctrl -M shift -P v -s 500 -p v -m shift -m ctrl
  fi
  ;;
esac

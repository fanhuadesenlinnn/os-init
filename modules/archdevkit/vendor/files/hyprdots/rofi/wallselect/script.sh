#!/usr/bin/env bash

set -euo pipefail

WALL_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpaper}"
THEME="$HOME/.config/rofi/wallselect/style.rasi"
CONFIG_PATH="$HOME/.config/hypr/hyprpaper.conf"

if [[ ! -d "$WALL_DIR" ]]; then
  notify-send -t 4000 "Wallpaper" "Directory not found: $WALL_DIR" || true
  exit 1
fi

selected="$(
  find "$WALL_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) |
    shuf |
    while read -r img; do
      printf '%s\0icon\x1f%s\n' "$img" "$img"
    done |
    rofi -dmenu -show-icons -theme "$THEME"
)"

[[ -z "$selected" ]] && exit 0

mkdir -p "$(dirname "$CONFIG_PATH")"
{
  echo "splash = false"
  echo "preload = $selected"
  echo "wallpaper = , $selected"
} >"$CONFIG_PATH"

pkill hyprpaper 2>/dev/null || true
hyprctl dispatch exec hyprpaper
notify-send -a "hyprpaper" "Wallpaper changed" -i "$selected" || true

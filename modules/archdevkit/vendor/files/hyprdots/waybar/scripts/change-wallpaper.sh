#!/usr/bin/env bash

set -euo pipefail

TARGET="${WALLPAPER_DIR:-$HOME/Pictures/Wallpaper}"
CONFIG_PATH="$HOME/.config/hypr/hyprpaper.conf"

if [[ ! -d "$TARGET" ]]; then
  notify-send -t 4000 "Wallpaper" "Directory not found: $TARGET" || true
  exit 1
fi

WALLPAPER="$(
  find "$TARGET" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) |
    shuf -n 1
)"

if [[ -z "$WALLPAPER" ]]; then
  notify-send -t 4000 "Wallpaper" "No images found in $TARGET" || true
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_PATH")"
{
  echo "splash = false"
  echo "preload = $WALLPAPER"
  echo "wallpaper = , $WALLPAPER"
} >"$CONFIG_PATH"

pkill hyprpaper 2>/dev/null || true
hyprctl dispatch exec hyprpaper
notify-send -a "hyprpaper" "Wallpaper changed" -i "$WALLPAPER" || true

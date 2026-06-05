#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpaper}"
CONFIG_PATH="$HOME/.config/hypr/hyprpaper.conf"
TEMP_FILE="$(mktemp)"

cleanup() {
  rm -f "$TEMP_FILE"
}
trap cleanup EXIT

yazi --chooser-file "$TEMP_FILE" "$TARGET_DIR"

WALLPAPER="$(cat "$TEMP_FILE")"

if [[ -z "$WALLPAPER" || ! -f "$WALLPAPER" ]]; then
  echo "No wallpaper selected. Exiting."
  exit 0
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
echo "Wallpaper set to: $WALLPAPER"

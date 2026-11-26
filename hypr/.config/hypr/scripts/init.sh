#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/caching.sh"
qs_ensure_cache "wallpaper_picker"

CACHE_IMG="$QS_CACHE_WALLPAPER_PICKER/current_wallpaper.png"
RELOAD="$(dirname "${BASH_SOURCE[0]}")/quickshell/wallpaper/matugen_reload.sh"
ON_APPLY="$(dirname "${BASH_SOURCE[0]}")/wallpaper/on_apply.sh"

if [ -f "$CACHE_IMG" ]; then
    matugen image "$CACHE_IMG" --source-color-index 0
    bash "$RELOAD"
    exit 0
fi

sleep 0.5
if command -v skwd-helm >/dev/null && skwd-helm random >/dev/null 2>&1; then
    exit 0
fi

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
file=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) 2>/dev/null | shuf -n 1)
[ -n "$file" ] && bash "$ON_APPLY" "$file"

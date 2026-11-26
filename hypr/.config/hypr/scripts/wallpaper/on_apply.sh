#!/usr/bin/env bash
# Run whenever a wallpaper is applied (wired into skwd-wall's "External Matugen" command):
#   ~/.config/hypr/scripts/wallpaper/on_apply.sh %path%
#
# Keeps the rest of the setup in sync:
#   current_wallpaper.png  still frame  -> matugen colours, MacLock fallback, SDDM (via sddm-sync.path)
#   current_wallpaper.mp4  symlink to the video -> MacLock + SDDM play it (absent for images)
set -uo pipefail

SRC="${1:?usage: on_apply.sh <wallpaper path>}"
SRC="$(readlink -f "$SRC")"
[ -f "$SRC" ] || { echo "on_apply: no such file: $SRC" >&2; exit 1; }

source "$HOME/.config/hypr/scripts/caching.sh"
qs_ensure_cache "wallpaper_picker"
DIR="$QS_CACHE_WALLPAPER_PICKER"
PNG="$DIR/current_wallpaper.png"
MP4="$DIR/current_wallpaper.mp4"
RELOAD="$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"

mime="$(file -b --mime-type "$SRC")"
tmp="$DIR/.frame.png"
# cap the still at 2560 px wide: enough for matugen/lock/SDDM, keeps the PNG small
grab() { ffmpeg -v error -y "$@" -frames:v 1 -vf "scale='min(2560,iw)':-2" "$tmp"; }

case "$mime" in
    video/*)
        # frame ~1 s in (skips black intro frames); fall back to the first frame for short clips
        grab -ss 1 -i "$SRC" 2>/dev/null && [ -s "$tmp" ] || grab -i "$SRC"
        ln -sfn "$SRC" "$MP4"
        ;;
    image/*)
        grab -i "$SRC"
        rm -f "$MP4"
        ;;
    *)
        echo "on_apply: unsupported type $mime" >&2; exit 1 ;;
esac

[ -s "$tmp" ] || { echo "on_apply: could not extract a frame from $SRC" >&2; exit 1; }
mv -f "$tmp" "$PNG"   # atomic replace; triggers sddm-sync.path

matugen image "$PNG" --source-color-index 0
bash "$RELOAD"

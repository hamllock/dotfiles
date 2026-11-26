#!/usr/bin/env bash
# Copy the current wallpaper (+ video) and avatar into the installed SDDM theme (run by sddm-sync.path).
A=/usr/share/sddm/themes/maclock/assets
[ -w "$A" ] || exit 0
C="$HOME/.cache/quickshell/wallpaper_picker"
W="$C/current_wallpaper.png"
M="$C/current_wallpaper.mp4"
V="$HOME/.cache/quickshell/dash/avatar.png"
[ -s "$W" ] && cp -L "$W" "$A/wallpaper.png"
if [ -e "$M" ]; then
    # videos are big: only copy when it actually changed
    cmp -s "$M" "$A/wallpaper.mp4" || { cp -L "$M" "$A/.wallpaper.mp4" && mv -f "$A/.wallpaper.mp4" "$A/wallpaper.mp4"; }
    chmod 644 "$A/wallpaper.mp4"
else
    rm -f "$A/wallpaper.mp4"
fi
[ -s "$V" ] && cp -L "$V" "$A/avatar.png"
exit 0

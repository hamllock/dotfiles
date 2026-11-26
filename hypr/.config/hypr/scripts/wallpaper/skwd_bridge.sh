#!/usr/bin/env bash
# Follow skwd-wall's daemon events and run on_apply.sh for every applied wallpaper.
# Runs as skwd-wall-bridge.service (~/.config/systemd/user).
HOOK="$HOME/.config/hypr/scripts/wallpaper/on_apply.sh"
skwd-helm watch \
  | jq --unbuffered -r 'select(.event == "skwd.wall.applied") | .data.path // empty' \
  | while IFS= read -r path; do
        [ -n "$path" ] && "$HOOK" "$path" || true
    done
# watch exits if the daemon restarts -> systemd restarts us
exit 1

#!/usr/bin/env bash
# Start the web wallpaper trial (pauses skwd underneath). Stop with stop.sh.
D=$(dirname "$(readlink -f "$0")")
W="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/workshop/content/431960/3775510022"
skwd-helm pause >/dev/null
systemd-run --user --quiet --unit=webwall-trial --collect -E WAYLAND_DISPLAY -E XDG_RUNTIME_DIR \
    /usr/bin/python3 -I "$D/webwall.py" "$W" "$D/settings.json"

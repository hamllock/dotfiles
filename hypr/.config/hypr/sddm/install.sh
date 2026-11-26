#!/usr/bin/env bash
# Install the MacLock SDDM theme. Run with sudo:  sudo ~/.config/hypr/sddm/install.sh
set -euo pipefail
U="${SUDO_USER:?run with sudo}"
SRC="$(dirname "$(readlink -f "$0")")/maclock"
DST=/usr/share/sddm/themes/maclock
rm -rf "$DST"
cp -r "$SRC" "$DST"
chown -R root:root "$DST"
chown -R "$U:$U" "$DST/assets"     # lets sync.sh update wallpaper/avatar without sudo
chmod 755 "$DST/assets"; chmod 644 "$DST"/assets/*
mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=maclock\n' > /etc/sddm.conf.d/10-maclock.conf
echo "Installed. Revert: sudo rm /etc/sddm.conf.d/10-maclock.conf"

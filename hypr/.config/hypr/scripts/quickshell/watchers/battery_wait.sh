#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"

PIPE="$QS_RUN_DIR/qs_battery_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null

trap 'rm -f "$PIPE"; kill $MONITOR_PID 2>/dev/null; exit 0' EXIT INT TERM

# Run udevadm isolated and capture its exact PID
LC_ALL=C setpriv --pdeathsig KILL udevadm monitor --subsystem-match=power_supply 2>/dev/null > "$PIPE" &
MONITOR_PID=$!

# Report back (the top bar then re-reads the battery) when:
#   - the charger is plugged / unplugged: right away
#   - the battery level ticks (every few seconds while charging): at most every 15 s
#   - nothing happens for 60 s
exec 3< "$PIPE"
while read -r -t 60 line <&3; do
    case "$line" in *change*) ;; *) continue ;; esac
    case "$line" in *ADP*|*/AC*|*ACAD*) exit 0 ;; esac
    timeout 15 grep -m 1 -E 'change.*(ADP|/AC|ACAD)' <&3 > /dev/null
    exit 0
done


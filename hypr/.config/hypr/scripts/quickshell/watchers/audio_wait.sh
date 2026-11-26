#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"

PIPE="$QS_RUN_DIR/qs_audio_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null

trap 'rm -f "$PIPE"; kill $MONITOR_PID 2>/dev/null; exit 0' EXIT INT TERM

# Run pactl isolated and capture its exact PID to prevent PipeWire connection exhaustion
LC_ALL=C setpriv --pdeathsig KILL pactl subscribe 2>/dev/null > "$PIPE" &
MONITOR_PID=$!

state() { LC_ALL=C wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; }
initial="$(state)"

while read -r line; do
    case "$line" in
        *"on server #"*) break ;;
        *"on sink #"*|*"on card #"*) [ "$(state)" != "$initial" ] && break ;;
    esac
done < "$PIPE"

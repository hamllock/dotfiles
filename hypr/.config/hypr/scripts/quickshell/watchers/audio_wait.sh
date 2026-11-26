#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../caching.sh"

PIPE="$QS_RUN_DIR/qs_audio_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null

trap 'rm -f "$PIPE"; kill $MONITOR_PID 2>/dev/null; exit 0' EXIT INT TERM

# Run pactl isolated and capture its exact PID to prevent PipeWire connection exhaustion
LC_ALL=C setpriv --pdeathsig KILL pactl subscribe 2>/dev/null > "$PIPE" &
MONITOR_PID=$!

# volume, mute or default device; not "sink-input" (app streams change constantly)
grep -m 1 -E "on (sink|server|card) #" < "$PIPE" > /dev/null

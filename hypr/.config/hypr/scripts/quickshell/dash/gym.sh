#!/usr/bin/env bash
# Log gym sessions to ~/gym.md (the dash's gym heatmap reads it).
#   gym.sh                    log today
#   gym.sh push day           log today with a note
#   gym.sh -d 2026-11-20 legs log another day
#   gym.sh -d yesterday       any `date -d` string works
#   gym.sh undo [-d DATE]     remove that day (default today)
#   gym.sh ls                 last 10 sessions
set -euo pipefail
FILE="$HOME/gym.md"
touch "$FILE"

day=$(date +%F)
if [[ "${1:-}" == "ls" ]]; then head -n 10 "$FILE"; exit 0; fi
undo=0
if [[ "${1:-}" == "undo" ]]; then undo=1; shift; fi
if [[ "${1:-}" == "-d" ]]; then day=$(date -d "$2" +%F); shift 2; fi
note="$*"

# drop any existing line for that day, then add the new one (newest first)
grep -v "^$day\b" "$FILE" > "$FILE.tmp" || true
if (( ! undo )); then
    printf '%s%s\n' "$day" "${note:+ $note}" >> "$FILE.tmp"
fi
sort -r "$FILE.tmp" > "$FILE" && rm -f "$FILE.tmp"

if (( undo )); then echo "removed $day"; else echo "logged $day${note:+ · $note}"; fi

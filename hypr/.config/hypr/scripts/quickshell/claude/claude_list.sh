#!/usr/bin/env bash
# Prints every live Claude Code session as a JSON array (newest first) for the top bar.
# Status files are written by claude_status.sh (Claude Code hooks); files whose claude
# process is gone (crashed / killed without SessionEnd) are removed here.
DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-status"
[[ -d "$DIR" ]] || { echo "[]"; exit 0; }
live=()
for f in "$DIR"/*.json; do
    [[ -e "$f" ]] || continue
    pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
    if [[ -n "$pid" && "$(cat /proc/$pid/comm 2>/dev/null)" == "claude" ]]; then live+=("$f"); else rm -f "$f"; fi
done
(( ${#live[@]} )) && jq -s -c 'sort_by(-.updated)' "${live[@]}" || echo "[]"

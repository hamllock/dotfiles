#!/usr/bin/env bash
# Claude Code hook -> per-session status file for the Quickshell top bar (ClaudePopup.qml).
# Called from ~/.claude/settings.json hooks as: claude_status.sh <EventName>, hook JSON on stdin.
# Writes $XDG_RUNTIME_DIR/claude-status/<session_id>.json:
#   {id, status: idle|working|waiting|done, project, cwd, message, updated, pid, term_pid}
DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-status"
mkdir -p "$DIR"
input=$(cat)
id=$(jq -r '.session_id // empty' <<<"$input")
[[ -z "$id" ]] && exit 0
file="$DIR/$id.json"
event="$1"

if [[ "$event" == "SessionEnd" ]]; then rm -f "$file"; exit 0; fi

cwd=$(jq -r '.cwd // empty' <<<"$input"); [[ -z "$cwd" ]] && cwd="$PWD"
msg=""
case "$event" in
    SessionStart)                       status="idle" ;;
    UserPromptSubmit|PreToolUse|PostToolUse) status="working" ;;
    Stop)                               status="done" ;;
    Notification)
        msg=$(jq -r '.message // ""' <<<"$input")
        # permission prompts need you; the "waiting for your input" reminder just means done
        if grep -qi "permission" <<<"$msg"; then status="waiting"; else status="done"; msg=""; fi ;;
    *) exit 0 ;;
esac

# walk up the process tree: hooks run through a short-lived shell, so find the real
# claude process (for "is it still alive?") and the terminal window it runs in
pid=""
term_pid=""
p=$$
for _ in 1 2 3 4 5 6 7 8 9 10; do
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || break
    [[ -z "$p" || "$p" -le 1 ]] && break
    case "$(cat /proc/$p/comm 2>/dev/null)" in
        claude) [[ -z "$pid" ]] && pid=$p ;;
        kitty|foot|alacritty|ghostty|wezterm*|konsole|gnome-terminal*) term_pid=$p; break ;;
    esac
done
[[ -z "$pid" ]] && pid=$PPID

jq -n --arg id "$id" --arg status "$status" --arg cwd "$cwd" --arg msg "$msg" \
      --argjson pid "$pid" --arg term "$term_pid" --argjson now "$(date +%s)" \
      '{id: $id, status: $status, project: ($cwd | split("/") | last), cwd: $cwd, message: $msg,
        updated: $now, pid: $pid, term_pid: ($term | if . == "" then null else tonumber end)}' > "$file.tmp" \
  && mv "$file.tmp" "$file"

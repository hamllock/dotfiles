#!/usr/bin/env bash
# Open a LeetCode problem: nvim (kitty) + the LeetCode window side by side.
#   lc_open.sh [slug|daily]     default: daily
#   lc_open.sh --browse         just the LeetCode window, on the problem browser
D="$HOME/.config/hypr/scripts/quickshell/leetcode"
QML="$D/LeetCode.qml"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/lc-nvim.sock"

~/.config/hypr/scripts/qs_manager.sh close >/dev/null 2>&1

arg="${1:-daily}"
slug="" file=""
if [[ "$arg" != "--browse" ]]; then
    json=$(python3 -I "$D/lc.py" fetch "$arg")
    err=$(jq -r '.error // empty' <<<"$json")
    if [[ -n "$err" ]]; then notify-send -a LeetCode "LeetCode" "$err"; exit 1; fi
    slug=$(jq -r '.slug' <<<"$json")
    file=$(jq -r '.file' <<<"$json")
fi

# LeetCode window: reuse it if it's open. An instance without a window (closed some
# other way) is stale: stop it and start a new one.
has_window() { hyprctl clients -j | jq -e 'any(.[]; .title == "LeetCode" and .class == "org.quickshell")' >/dev/null; }
if quickshell list -p "$QML" 2>/dev/null | grep -q "Instance" && ! has_window; then
    quickshell kill -p "$QML" >/dev/null 2>&1 || pkill -f "^quickshell -p $QML"
    sleep 0.3
fi
if quickshell list -p "$QML" 2>/dev/null | grep -q "Instance"; then
    if [[ -n "$slug" ]]; then quickshell ipc -p "$QML" call lc open "$slug" >/dev/null
    else quickshell ipc -p "$QML" call lc browse >/dev/null; fi
    hyprctl dispatch 'hl.dsp.focus({ window = "title:^(LeetCode)$" })' >/dev/null 2>&1
else
    LC_SLUG="$slug" LC_BROWSE=$([[ -z "$slug" ]] && echo 1) setsid -f quickshell -p "$QML" >/dev/null 2>&1
fi

# editor: reuse the nvim we started before (it listens on $SOCK), else open a new kitty
[[ -z "$file" ]] && exit 0
if [[ -S "$SOCK" ]] && timeout 2 nvim --server "$SOCK" --remote-expr 1 >/dev/null 2>&1; then
    nvim --server "$SOCK" --remote "$file" >/dev/null 2>&1
else
    rm -f "$SOCK"
    sleep 0.3   # let the LeetCode window map first so nvim tiles next to it
    setsid -f kitty --class lc-editor --title "LeetCode · nvim" nvim --listen "$SOCK" "$file" >/dev/null 2>&1
fi

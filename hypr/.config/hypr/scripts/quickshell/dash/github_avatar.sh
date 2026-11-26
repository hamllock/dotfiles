#!/usr/bin/env bash
# Prints the path to the gh-authenticated user's GitHub avatar, downloading it into
# ~/.cache/quickshell/dash/avatar.png when missing or older than a day.
# Pass --force to re-download. Prints nothing if there is no avatar and no network.
CACHE_DIR="${QS_CACHE_DASH:-$HOME/.cache/quickshell/dash}"
OUT="$CACHE_DIR/avatar.png"
mkdir -p "$CACHE_DIR"

if [[ "$1" == "--force" || ! -s "$OUT" ]] || [[ $(( $(date +%s) - $(stat -c %Y "$OUT") )) -gt 86400 ]]; then
    url=$(gh api user --jq .avatar_url 2>/dev/null)
    if [[ -n "$url" ]]; then
        sep='?'; [[ "$url" == *\?* ]] && sep='&'
        curl -fsSL --max-time 15 "${url}${sep}s=256" -o "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
        rm -f "$OUT.tmp"
    fi
fi
[[ -s "$OUT" ]] && echo "$OUT"

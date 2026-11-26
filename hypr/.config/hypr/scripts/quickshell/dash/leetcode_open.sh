#!/usr/bin/env bash
# Dash LeetCode buttons -> the LeetCode window + nvim (../leetcode/lc_open.sh).
#   leetcode_open.sh daily   -> today's problem
#   leetcode_open.sh         -> browse (LeetCode window only, search there)
L="$HOME/.config/hypr/scripts/quickshell/leetcode/lc_open.sh"
if [[ "$1" == "daily" ]]; then exec bash "$L" daily; else exec bash "$L" --browse; fi

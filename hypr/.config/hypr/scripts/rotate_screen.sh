#!/usr/bin/env bash

# Rotate screen into any cardinal direction in Hyprland
# Arguments:
#   up    | normal | 0   -> Normal landscape (0°)
#   right | 90     | 1   -> Portrait clockwise (90°)
#   down  | 180    | 2   -> Inverted landscape (180°)
#   left  | 270    | 3   -> Portrait counter-clockwise (270°)
#   next  | toggle       -> Cycle to the next rotation

DIR="${1:-up}"

case "$DIR" in
    up|normal|0)
        TRANSFORM=0
        LABEL="Landscape (Normal)"
        ;;
    right|90|1)
        TRANSFORM=1
        LABEL="Portrait (90° Clockwise)"
        ;;
    down|inverted|180|2)
        TRANSFORM=2
        LABEL="Landscape (Inverted 180°)"
        ;;
    left|270|3)
        TRANSFORM=3
        LABEL="Portrait (270° Counter-Clockwise)"
        ;;
    next|toggle)
        CURRENT_TRANSFORM=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .transform // 0')
        [ -z "$CURRENT_TRANSFORM" ] && CURRENT_TRANSFORM=0
        TRANSFORM=$(( (CURRENT_TRANSFORM + 1) % 4 ))
        case "$TRANSFORM" in
            0) LABEL="Landscape (Normal)" ;;
            1) LABEL="Portrait (90° Clockwise)" ;;
            2) LABEL="Landscape (Inverted 180°)" ;;
            3) LABEL="Portrait (270° Counter-Clockwise)" ;;
        esac
        ;;
    *)
        echo "Usage: $0 {up|right|down|left|next|0|1|2|3}"
        exit 1
        ;;
esac

# Find the focused monitor
FOCUSED_MON=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)')
if [ -z "$FOCUSED_MON" ]; then
    FOCUSED_MON=$(hyprctl monitors -j | jq -r '.[0]')
fi

MON_NAME=$(echo "$FOCUSED_MON" | jq -r '.name')
MON_SCALE=$(echo "$FOCUSED_MON" | jq -r '.scale // 1')
[ -z "$MON_SCALE" ] || [ "$MON_SCALE" = "null" ] && MON_SCALE="1"

# Apply transform dynamically via Hyprland
hyprctl eval "hl.monitor({ output = \"${MON_NAME}\", mode = \"preferred\", position = \"auto\", scale = ${MON_SCALE}, transform = ${TRANSFORM} })"

# Notify user (transient / synchronous replacement)
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Display" -i "display" -h "string:x-canonical-private-synchronous:screen-rotate" -t 1500 "Screen Orientation" "$LABEL"
fi

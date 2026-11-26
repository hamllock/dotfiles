#!/usr/bin/env bash

sink()  { pactl get-default-sink; }
state() { LC_ALL=C wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null; }

last_sink=$(sink)
last_state=$(state)

LC_ALL=C pactl subscribe | grep --line-buffered -E "Event 'change' on (sink|server) #" | while read -r line; do
    if [[ "$line" == *"on server #"* ]]; then
        last_sink=$(sink)
        last_state=$(state)
        continue
    fi

    current_state=$(state)
    [[ "$current_state" == "$last_state" ]] && continue
    last_state="$current_state"

    swayosd-client --output-volume 0
done

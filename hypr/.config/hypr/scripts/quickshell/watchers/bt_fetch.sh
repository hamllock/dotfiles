#!/usr/bin/env bash

# Fetch bluetooth controller info once and strip ANSI escape sequences
show_out=$(LC_ALL=C timeout 0.5 bluetoothctl show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

if echo "$show_out" | grep -q "Powered: yes"; then
    status="on"
else
    status="off"
fi

get_bt_connected_device() {
    if [ "$status" = "on" ]; then
        # Fetch connected devices once and strip ANSI escape sequences
        local devices=$(LC_ALL=C timeout 0.5 bluetoothctl devices Connected 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
        local device=$(echo "$devices" | head -n1 | cut -d' ' -f3-)
        if [ -n "$device" ]; then
            echo "$device"
        else
            echo "Disconnected"
        fi
    else
        echo "Off"
    fi
}

get_bt_icon() {
    if [ "$status" = "on" ]; then
        if echo "$1" | grep -q "^Device"; then
            echo "󰂱"
        else
            echo "󰂯"
        fi
    else
        echo "󰂲"
    fi
}

toggle_bt() {
    if [ "$status" = "on" ]; then
        LC_ALL=C timeout 0.5 bluetoothctl power off 2>/dev/null
        notify-send -u low -i bluetooth-disabled "Bluetooth" "Disabled"
    else
        LC_ALL=C timeout 0.5 bluetoothctl power on 2>/dev/null
        notify-send -u low -i bluetooth-active "Bluetooth" "Enabled"
    fi
}

case $1 in
    --toggle)
        toggle_bt
        ;;
    *)
        if [ "$status" = "on" ]; then
            devices_out=$(LC_ALL=C timeout 0.5 bluetoothctl devices Connected 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
            device_name=$(echo "$devices_out" | head -n1 | cut -d' ' -f3-)
            if [ -n "$device_name" ]; then
                connected="$device_name"
            else
                connected="Disconnected"
            fi
            icon=$(get_bt_icon "$devices_out")
        else
            connected="Off"
            icon="󰂲"
        fi
        
        jq -n -c --arg status "$status" --arg icon "$icon" --arg connected "$connected" \
            '{status: $status, icon: $icon, connected: $connected}'
        ;;
esac

#!/usr/bin/env bash
# Bluetooth actions for BluetoothPopup.qml. Status/connect/disconnect/power reuse the
# original bluetooth_panel_logic.sh (from the old network popup); pairing and removing are added here.
#   bt.sh status | power | connect <mac> | disconnect <mac> | pair <mac> | remove <mac>
LOGIC="$HOME/.config/hypr/scripts/quickshell/bluetooth/bluetooth_panel_logic.sh"
mac="$2"
case "$1" in
    status)     bash "$LOGIC" --status ;;
    power)      bash "$LOGIC" --toggle ;;
    connect)    timeout 20 bash "$LOGIC" --connect "$mac" | grep -q "Connection successful" ;;
    disconnect) bash "$LOGIC" --disconnect "$mac" >/dev/null ;;
    pair)       timeout 30 bluetoothctl pair "$mac" | grep -qE "Pairing successful|AlreadyExists" \
                  && bluetoothctl trust "$mac" >/dev/null \
                  && timeout 20 bluetoothctl connect "$mac" | grep -q "Connection successful" ;;
    remove)     bluetoothctl remove "$mac" >/dev/null ;;
esac

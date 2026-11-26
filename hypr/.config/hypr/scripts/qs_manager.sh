#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# GLOBAL VARS
# -----------------------------------------------------------------------------
SCRIPTS_DIR="$HOME/.config/hypr/scripts/quickshell"
SHELL_QML_PATH="$SCRIPTS_DIR/Shell.qml"

# -----------------------------------------------------------------------------
# FAST PATH: WORKSPACE SWITCHING
# Must be first — before any sourcing, caching, or pgrep.
# -----------------------------------------------------------------------------
ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

is_vicinae_open() {
    pgrep -x vicinae-server >/dev/null || return 1
    pgrep -a vicinae-server 2>/dev/null | grep -q '"open":true'
}

if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
    # Send IPC command directly to Main.qml via Quickshell's native IPC handler
    quickshell -p "$SHELL_QML_PATH" ipc call main handleCommand "close" "" "" >/dev/null 2>&1
    is_vicinae_open && vicinae close >/dev/null 2>&1

    CMD="hl.dsp.focus({ workspace = $ACTION })"
    [[ "$TARGET" == "move" ]] && CMD="hl.dsp.window.move({ workspace = $ACTION })"
    hyprctl dispatch "$CMD" >/dev/null 2>&1
    exit 0
fi

# -----------------------------------------------------------------------------
# SLOW PATH: Everything below only runs for non-workspace actions
# -----------------------------------------------------------------------------

source "$(dirname "${BASH_SOURCE[0]}")/caching.sh"

qs_ensure_cache "workspaces"

# -----------------------------------------------------------------------------
# ZOMBIE WATCHDOG
# Only runs on slow path — not on every workspace switch
# -----------------------------------------------------------------------------

if ! pgrep -f "quickshell.*Shell.qml" >/dev/null; then
    quickshell -p "$SHELL_QML_PATH" >/dev/null 2>&1 &
    disown
fi

# -----------------------------------------------------------------------------
# IPC ROUTING
# -----------------------------------------------------------------------------
if [[ "$ACTION" == "close" ]]; then
    quickshell -p "$SHELL_QML_PATH" ipc call main handleCommand "close" "" "" >/dev/null 2>&1
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    if [[ "$TARGET" == "vicinae" ]]; then
        quickshell -p "$SHELL_QML_PATH" ipc call main handleCommand "close" "" "" >/dev/null 2>&1
        vicinae toggle >/dev/null 2>&1
        exit 0
    fi

    # Close vicinae when any other panel opens
    is_vicinae_open && vicinae close >/dev/null 2>&1

    # "network" (old combined popup) now means wifi, or bluetooth with the "bt" subtarget
    if [[ "$TARGET" == "network" ]]; then
        [[ "$SUBTARGET" == "bt" ]] && TARGET="bluetooth" || TARGET="wifi"
        SUBTARGET=""
    fi

    quickshell -p "$SHELL_QML_PATH" ipc call main handleCommand "$ACTION" "$TARGET" "$SUBTARGET" >/dev/null 2>&1
    exit 0
fi

#!/usr/bin/env bash

# File paths
SETTINGS_FILE="$HOME/.config/hypr/settings.json"
WEATHER_SCRIPT="$HOME/.config/hypr/scripts/weather.sh"
ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

# Target configuration files (Lua since Hyprland 0.57; templates live in templates/*.lua.template)
CONF_DIR="$HOME/.config/hypr/config"
TMPL_DIR="$HOME/.config/hypr/templates"
SETTINGS_CONF="$CONF_DIR/settings.lua"
AUTOSTART_CONF="$CONF_DIR/autostart.lua"
ENV_CONF="$CONF_DIR/env.lua"
KEYBINDS_CONF="$CONF_DIR/keybindings.lua"
MONITORS_CONF="$CONF_DIR/monitors.lua"
HYPRIDLE_CONF="$HOME/.config/hypr/hypridle.conf"

# jq helper: turn a JSON value into a quoted Lua string literal
JQ_LUA='def lua: tostring | "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n") | gsub("\r"; "\\r") | gsub("\t"; "\\t")) + "\"";'

# Escape a shell string for use inside a "..." Lua literal AND as a sed replacement
lua_sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\"]/\\\\&/g' -e 's/[|&]/\\&/g'
}

# Ensure the required files and directories exist
mkdir -p "$CONF_DIR" "$TMPL_DIR" "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")"
[ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"

CACHE_DIR="$HOME/.cache/settings_watcher"
mkdir -p "$CACHE_DIR"

compile_settings() {
    echo "Regenerating configurations from templates..."

    # Hash existing configs before any changes, split by monitor vs non-monitor.
    # This means a pure uiScale/weatherApiKey write never triggers a reload.
    OLD_NONMON_HASH=$(md5sum "$SETTINGS_CONF" "$KEYBINDS_CONF" "$AUTOSTART_CONF" "$ENV_CONF" 2>/dev/null | md5sum)
    OLD_MON_HASH=$(md5sum "$MONITORS_CONF" 2>/dev/null | md5sum)

    # Read state from JSON (Using 'has' to safely parse booleans)
    LANG=$(jq -r '.language // "us"' "$SETTINGS_FILE")
    KB_OPT=$(jq -r '.kbOptions // "grp:alt_shift_toggle"' "$SETTINGS_FILE")

    # Windows / input (Settings > General); numbers are clamped so a bad value can't break the config
    num() { jq -r "($1) as \$v | if (\$v|type) == \"number\" then ([[\$v, $2]|max, $3]|min) else $4 end" "$SETTINGS_FILE"; }
    bool() { jq -r "if ($1) == false then \"false\" else \"true\" end" "$SETTINGS_FILE"; }
    GAPS_IN=$(num '.windows.gapsIn' 0 40 4)
    GAPS_OUT=$(num '.windows.gapsOut' 0 60 4)
    BORDER_SIZE=$(num '.windows.border' 0 10 2)
    ROUNDING=$(num '.windows.rounding' 0 30 4)
    BLUR=$(bool '.windows.blur')
    ANIMATIONS=$(bool '.windows.animations')
    NATURAL_SCROLL=$(bool '.input.naturalScroll')
    SENSITIVITY=$(num '.input.sensitivity' -1 1 0)

    PIC_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
    VID_DIR="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"

    # Hardware variables injected by install.sh, as old "env = NAME,value" / "NAME,value" lines
    HW_ENV=$(jq -r "$JQ_LUA"' .hardwareEnvs[]? // empty | sub("^\\s*env\\s*=\\s*"; "") | capture("^(?<k>[^,]+),(?<v>.*)$")? | "hl.env(\(.k | sub("\\s+$"; "") | lua), \(.v | sub("^\\s+"; "") | lua))"' "$SETTINGS_FILE")

    # 1. Regenerate env.lua using the template
    echo "Regenerating env.lua..."
    sed -e "s|{{XDG_PICTURES_DIR}}|$(lua_sed_escape "$PIC_DIR")|g" \
        -e "s|{{XDG_VIDEOS_DIR}}|$(lua_sed_escape "$VID_DIR")|g" \
        -e "s|{{SCRIPT_DIR}}|$(lua_sed_escape "$HOME/.config/hypr/scripts")|g" \
        "$TMPL_DIR/env.lua.template" > "${ENV_CONF}.tmp"

    # Use awk to safely substitute the multi-line HW_ENV array without breaking escapes
    awk -v hw="$HW_ENV" '{
        if (index($0, "{{HARDWARE_ENV}}")) {
            print hw
        } else {
            print $0
        }
    }' "${ENV_CONF}.tmp" > "$ENV_CONF"
    rm -f "${ENV_CONF}.tmp"

    # 2. Regenerate settings.lua using template
    echo "Regenerating settings.lua..."
    sed -e "s|{{KB_LAYOUT}}|$(lua_sed_escape "$LANG")|g" \
        -e "s|{{KB_OPTIONS}}|$(lua_sed_escape "$KB_OPT")|g" \
        -e "s|{{GAPS_IN}}|$GAPS_IN|g" -e "s|{{GAPS_OUT}}|$GAPS_OUT|g" \
        -e "s|{{BORDER_SIZE}}|$BORDER_SIZE|g" -e "s|{{ROUNDING}}|$ROUNDING|g" \
        -e "s|{{BLUR}}|$BLUR|g" -e "s|{{ANIMATIONS}}|$ANIMATIONS|g" \
        -e "s|{{NATURAL_SCROLL}}|$NATURAL_SCROLL|g" -e "s|{{SENSITIVITY}}|$SENSITIVITY|g" \
        "$TMPL_DIR/settings.lua.template" > "$SETTINGS_CONF"

    # 3. Regenerate autostart.lua
    echo "Regenerating autostart.lua..."
    cp "$TMPL_DIR/autostart.lua.template" "$AUTOSTART_CONF"

    # Dump normal startup entries
    jq -r "$JQ_LUA"' .startup[]? | "exec_once(\(.command | lua))"' "$SETTINGS_FILE" >> "$AUTOSTART_CONF"


    # 4. Regenerate keybindings.lua (settings.json keeps the old Hyprlang bind format;
    #    config/legacy.lua translates it)
    echo "Regenerating keybindings.lua..."
    cp "$TMPL_DIR/keybinds.lua.template" "$KEYBINDS_CONF"
    jq -r "$JQ_LUA"' .keybinds[]? | "L.bind(\(.type // "bind" | lua), \(.mods // "" | lua), \(.key // "" | lua), \(.dispatcher // "exec" | lua), \(.command // "" | lua))"' "$SETTINGS_FILE" >> "$KEYBINDS_CONF"

    # 5. Regenerate monitors.lua
    echo "Regenerating monitors.lua..."
    cp "$TMPL_DIR/monitors.lua.template" "$MONITORS_CONF"
    MONITOR_COUNT=$(jq '.monitors | length' "$SETTINGS_FILE" 2>/dev/null)
    if [[ "$MONITOR_COUNT" -gt 0 ]]; then
        jq -r "$JQ_LUA"' .monitors[]? | "L.monitor(\(.name | lua), \("\(.resW)x\(.resH)@\(.rate)" | lua), \("\(.x)x\(.y)" | lua), \(.scale // 1), \(.transform // 0), \(.vrr // 0))"' "$SETTINGS_FILE" >> "$MONITORS_CONF"
    else
        echo 'L.monitor("", "preferred", "auto", 1)' >> "$MONITORS_CONF"
    fi

    # 6. Regenerate hypridle.conf (minutes; 0 = never) and restart hypridle if it changed
    LOCK_MIN=$(num '.idle.lockMin' 0 240 10)
    OFF_MIN=$(num '.idle.screenOffMin' 0 240 11)
    SUSPEND_MIN=$(num '.idle.suspendMin' 0 480 40)
    OLD_IDLE_HASH=$(md5sum "$HYPRIDLE_CONF" 2>/dev/null)
    {
        cat "$TMPL_DIR/hypridle.conf.template"
        if [ "$LOCK_MIN" -gt 0 ]; then
            printf '\nlistener {\n    timeout = %d\n    on-timeout = loginctl lock-session\n}\n' $((LOCK_MIN * 60))
        fi
        if [ "$OFF_MIN" -gt 0 ]; then
            printf '\nlistener {\n    timeout = %d\n    on-timeout = hyprctl dispatch '"'"'hl.dsp.dpms({ action = "off" })'"'"'\n    on-resume = hyprctl dispatch '"'"'hl.dsp.dpms({ action = "on" })'"'"'\n}\n' $((OFF_MIN * 60))
        fi
        if [ "$SUSPEND_MIN" -gt 0 ]; then
            # only on battery: plugged in, the machine stays awake
            printf '\nlistener {\n    timeout = %d\n    on-timeout = [ "$(cat /sys/class/power_supply/ADP1/online)" = 1 ] || systemctl suspend\n}\n' $((SUSPEND_MIN * 60))
        fi
    } > "$HYPRIDLE_CONF.tmp" && mv "$HYPRIDLE_CONF.tmp" "$HYPRIDLE_CONF"
    if [ "$OLD_IDLE_HASH" != "$(md5sum "$HYPRIDLE_CONF")" ] && pgrep -x hypridle >/dev/null; then
        echo "Idle timers changed, restarting hypridle..."
        pkill -x hypridle; setsid -f hypridle >/dev/null 2>&1 < /dev/null
    fi

    # Hash after changes
    NEW_NONMON_HASH=$(md5sum "$SETTINGS_CONF" "$KEYBINDS_CONF" "$AUTOSTART_CONF" "$ENV_CONF" 2>/dev/null | md5sum)
    NEW_MON_HASH=$(md5sum "$MONITORS_CONF" 2>/dev/null | md5sum)

    if [ "$OLD_MON_HASH" != "$NEW_MON_HASH" ]; then
        # Monitor layout actually changed — full reload needed
        echo "Monitor config changed, reloading Hyprland..."
        hyprctl reload
    elif [ "$OLD_NONMON_HASH" != "$NEW_NONMON_HASH" ]; then
        # Non-monitor settings changed (keybinds, autostart, input, env) — reload safe, no display flicker
        echo "Non-monitor config changed, reloading Hyprland..."
        hyprctl reload
    else
        # Nothing that affects Hyprland changed (e.g. uiScale, weatherApiKey) — skip reload entirely
        echo "No Hyprland config changes detected, skipping reload."
    fi
}

# If called with --compile, execute once and exit (used by install.sh)
if [[ "$1" == "--compile" ]]; then
    compile_settings
    exit 0
fi

echo "Started watching settings directories for changes..."

# Watch the real directories (~/.config/hypr is a Stow symlink; inotifywait drops the
# "/" between dir and file name for symlinked paths) and compare resolved paths.
SETTINGS_REAL="$(readlink -f "$SETTINGS_FILE")"
ENV_REAL="$(readlink -f "$(dirname "$ENV_FILE")")/$(basename "$ENV_FILE")"
inotifywait -m -q -e close_write,moved_to --format '%w%f' "$(dirname "$SETTINGS_REAL")/" "$(dirname "$ENV_REAL")/" | while read -r filepath; do

    # ---------------------------------------------------------
    # SETTINGS JSON TRIGGER
    # ---------------------------------------------------------
    if [[ "$filepath" == "$SETTINGS_REAL" ]]; then
        compile_settings
    fi

    # ---------------------------------------------------------
    # .ENV WEATHER TRIGGER
    # ---------------------------------------------------------
    if [[ "$filepath" == "$ENV_REAL" ]]; then
        echo ".env updated! Forcing weather cache refresh..."
        if [ -x "$WEATHER_SCRIPT" ]; then
            "$WEATHER_SCRIPT" --getdata &
        else
            bash "$WEATHER_SCRIPT" --getdata &
        fi
    fi
done

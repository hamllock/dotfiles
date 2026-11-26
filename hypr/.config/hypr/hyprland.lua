-- --------------------------------------------------------------------------------------
--
--   ██╗██╗  ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗
--   ██║██║  ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
--   ██║██║   ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
--   ██║██║    ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
--   ██║███████╗██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
--   ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝
--
--   Created by ilyamiro
--   https://github.com/ilyamiro/nixos-configuration
--
-- --------------------------------------------------------------------------------------
-- Lua config for Hyprland 0.57+ (the old hyprland.conf / config/*.conf files are gone).

local HYPR = os.getenv("HOME") .. "/.config/hypr"

-- Run a config file, passing it (legacy helpers, colors). Uses loadfile instead of
-- require so every `hyprctl reload` re-reads the file.
local function source(rel, ...)
    local chunk, err = loadfile(HYPR .. "/" .. rel)
    if not chunk then error(err, 0) end
    return chunk(...)
end

local L      = source("config/legacy.lua")
local colors = source("colors.lua")   -- written by matugen

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ MODULAR CONFIGURATION
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Passthrough submap used by the Quickshell settings keybind recorder.
-- The dummy bind forces Hyprland to register the submap; since you never press it,
-- every keystroke falls through to Quickshell.
hl.define_submap("passthru", function()
    hl.bind("SUPER + SHIFT + CTRL + ALT + F35", hl.dsp.exec_cmd("true"))
end)

-- Generated from settings.json by scripts/settings_watcher.sh (edit templates/*.lua.template)
source("config/monitors.lua", L, colors)
source("config/env.lua", L, colors)
source("config/autostart.lua", L, colors)
source("config/settings.lua", L, colors)
source("config/keybindings.lua", L, colors)

-- Hand-written
source("config/rules.lua", L, colors)

-- liquid glass (hyprliquid): remove this line to turn it off
source("config/hyprliquid.lua", L, colors)

-- picture-in-picture: pinned, follows the focused monitor, SUPER+P collapses it
source("config/pip.lua", L, colors)

-- minimize: SUPER+Z minimizes / restores, SUPER+SHIFT+Z shows minimized windows
source("config/minimize.lua", L, colors)


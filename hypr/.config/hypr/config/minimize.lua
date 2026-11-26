-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ MINIMIZE (Hyprland has none built in: this uses a hidden "minimized" workspace)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  SUPER+Z         minimize the focused window
--                  (on a minimized window: bring it back to the workspace you're on)
--  SUPER+SHIFT+Z   show / hide the minimized windows as an overlay
--  An app's own minimize button does the same as SUPER+Z.
-- Remove the source("config/minimize.lua") line in hyprland.lua to turn this off.

local SPECIAL = "minimized"

-- darken everything behind the overlay so it's obvious you're in it (default 0.2)
hl.config({ decoration = { dim_special = 0.65 } })

local function sel(w) return "address:" .. w.address end

local function is_minimized(w)
    return w and w.workspace and w.workspace.name == "special:" .. SPECIAL
end

local function minimize(w)
    if not w or is_minimized(w) then return end
    hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. SPECIAL, follow = false, window = sel(w) }))
end

local function restore(w)
    local m = w.monitor or hl.get_active_monitor()
    local ws = m and m.active_workspace
    if not ws then return end
    hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = sel(w) }))
    -- close the overlay and focus the restored window
    if m.active_special_workspace then hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL)) end
    hl.dispatch(hl.dsp.focus({ window = sel(w) }))
end

hl.bind("SUPER + Z", function()
    local w = hl.get_active_window()
    if not w then return end
    if is_minimized(w) then restore(w) else minimize(w) end
end)

hl.bind("SUPER + SHIFT + Z", function()
    hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
end)

-- apps' own minimize buttons (Hyprland otherwise ignores these requests)
hl.on("window.minimize", function(w, state)
    if state == false then return end
    minimize(w)
end)

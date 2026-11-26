-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ LEGACY BIND TRANSLATION
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- settings.json (and the Quickshell settings UI) still describe keybinds the
-- Hyprlang way: type "bindel", mods "$mainMod SHIFT_L", dispatcher "movefocus",
-- argument "l". This module turns those into Lua binds / hl.dsp dispatchers.
--
-- It also defines the global legacy_dispatch(name, arg), so scripts can run an
-- old-style dispatcher through hyprctl:
--   hyprctl dispatch 'legacy_dispatch("movefocus", "l")'

local M = {}

local function trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- HYPR_LUA_STRICT=1 Hyprland --verify-config  -> turn these into hard errors
local function notify_error(msg)
    if os.getenv("HYPR_LUA_STRICT") then error(msg, 0) end
    pcall(hl.notification.create, { text = "hypr config: " .. msg, duration = 8000, icon = "error" })
end

-- "$mainMod SHIFT_L" -> { "SUPER", "SHIFT" }
local MOD_NAMES = {
    ["$MAINMOD"] = "SUPER", SUPER = "SUPER", WIN = "SUPER", LOGO = "SUPER", MOD4 = "SUPER",
    SHIFT = "SHIFT",
    CTRL = "CTRL", CONTROL = "CTRL",
    ALT = "ALT", MOD1 = "ALT",
    CAPS = "CAPS", MOD2 = "MOD2", MOD3 = "MOD3", MOD5 = "MOD5",
}

function M.mods(str)
    local out, seen = {}, {}
    for raw in (str or ""):upper():gmatch("[^%s+]+") do
        local tok = raw:gsub("_[LR]$", "")
        local name = MOD_NAMES[tok]
        if not name then
            notify_error("unknown modifier '" .. tok .. "' in '" .. str .. "'")
        elseif not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

function M.keystring(mods, key)
    local m = M.mods(mods)
    m[#m + 1] = trim(key)
    return table.concat(m, " + ")
end

local DIRS = { l = "left", r = "right", u = "up", d = "down", t = "up", b = "down",
               left = "left", right = "right", up = "up", down = "down" }

local function dir(arg)
    return DIRS[trim(arg):lower()]
end

-- workspace arguments: "3" -> 3, anything else ("e+1", "special:magic") stays a string
local function ws(arg)
    arg = trim(arg)
    return tonumber(arg) or arg
end

local function split2(arg)
    local a, b = trim(arg):match("^(%S+)%s+(%S+)$")
    return tonumber(a), tonumber(b)
end

-- Old dispatcher name + argument string -> hl.dsp dispatcher (or nil if unknown).
local DISPATCHERS = {
    exec            = function(a) return M.exec(a) end,
    execr           = function(a) return hl.dsp.exec_raw(a) end,
    killactive      = function() return hl.dsp.window.close() end,
    forcekillactive = function() return hl.dsp.window.kill() end,
    togglefloating  = function() return hl.dsp.window.float({ action = "toggle" }) end,
    setfloating     = function() return hl.dsp.window.float({ action = "set" }) end,
    settiled        = function() return hl.dsp.window.float({ action = "unset" }) end,
    pin             = function() return hl.dsp.window.pin() end,
    pseudo          = function() return hl.dsp.window.pseudo() end,
    centerwindow    = function() return hl.dsp.window.center() end,
    togglesplit     = function() return hl.dsp.layout("togglesplit") end,
    fullscreen      = function(a)
        local mode = trim(a) == "1" and "maximized" or "fullscreen"
        return hl.dsp.window.fullscreen({ mode = mode, action = "toggle" })
    end,
    movefocus       = function(a) return hl.dsp.focus({ direction = dir(a) }) end,
    movewindow      = function(a)
        if trim(a) == "" then return hl.dsp.window.drag() end
        return hl.dsp.window.move({ direction = dir(a) })
    end,
    swapwindow      = function(a) return hl.dsp.window.swap({ direction = dir(a) }) end,
    resizewindow    = function() return hl.dsp.window.resize() end,
    resizeactive    = function(a)
        local x, y = split2(a)
        return hl.dsp.window.resize({ x = x, y = y, relative = true })
    end,
    workspace       = function(a) return hl.dsp.focus({ workspace = ws(a) }) end,
    movetoworkspace = function(a) return hl.dsp.window.move({ workspace = ws(a) }) end,
    togglespecialworkspace = function(a)
        return hl.dsp.workspace.toggle_special(trim(a) ~= "" and trim(a) or "special")
    end,
    focusmonitor    = function(a) return hl.dsp.focus({ monitor = trim(a) }) end,
    movecursor      = function(a)
        local x, y = split2(a)
        return hl.dsp.cursor.move({ x = x, y = y })
    end,
    -- NB: hl.dsp.dpms("off") ignores its string argument and toggles; only the
    -- table form sets an explicit state.
    dpms            = function(a)
        local act = trim(a):lower()
        if act == "" then return hl.dsp.dpms() end
        return hl.dsp.dpms({ action = act })
    end,
    submap          = function(a) return hl.dsp.submap(trim(a)) end,
    exit            = function() return hl.dsp.exit() end,
}

function M.dispatcher(name, arg)
    name = trim(name):lower()
    local f = DISPATCHERS[name]
    if not f then return nil end
    local ok, d = pcall(f, arg or "")
    if ok then return d end
    notify_error("bad argument for '" .. name .. " " .. tostring(arg) .. "': " .. tostring(d))
    return nil
end

-- exec commands that are just "hyprctl dispatch <old dispatcher> ..." no longer work
-- under Lua, so run those natively instead of spawning hyprctl.
function M.exec(cmd)
    local name, arg = trim(cmd):match("^hyprctl%s+dispatch%s+(%S+)%s*(.-)$")
    if name and DISPATCHERS[name:lower()] and name:lower() ~= "exec" then
        local d = M.dispatcher(name, arg)
        if d then return d end
    end
    return hl.dsp.exec_cmd(cmd)
end

-- bind / binde / bindl / bindel / bindm / bindr / ... -> HL.BindOptions
local FLAGS = { e = "repeating", l = "locked", r = "release", n = "non_consuming",
                t = "transparent", i = "ignore_mods", o = "long_press", d = "description" }

function M.bind(btype, mods, key, dispatcher, arg)
    btype = trim(btype ~= "" and btype or "bind")
    local opts = {}
    for c in btype:gsub("^bind", ""):gmatch(".") do
        if c == "m" then
            opts.mouse = true
        elseif FLAGS[c] and c ~= "d" then
            opts[FLAGS[c]] = true
        end
    end

    local d = M.dispatcher(dispatcher ~= "" and dispatcher or "exec", arg)
    if not d then
        notify_error("unknown dispatcher '" .. tostring(dispatcher) .. "' for " .. mods .. " " .. key)
        return nil
    end

    local ok, res = pcall(hl.bind, M.keystring(mods, key), d, next(opts) and opts or nil)
    if not ok then notify_error(tostring(res)) end
    return ok and res or nil
end

-- old monitor line fields -> hl.monitor
function M.monitor(name, mode, position, scale, transform, vrr)
    local spec = { output = name or "", mode = mode, position = position, scale = scale }
    if transform and transform ~= 0 then spec.transform = transform end
    if vrr and vrr ~= 0 then spec.vrr = vrr end
    hl.monitor(spec)
end

function legacy_dispatch(name, arg)
    local d = M.dispatcher(name, arg)
    if not d then error("legacy_dispatch: unknown dispatcher '" .. tostring(name) .. "'") end
    return d
end

return M

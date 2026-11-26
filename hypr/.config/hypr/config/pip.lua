-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ PICTURE-IN-PICTURE (Zen / Firefox / Chromium video pop-outs)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  • floats and is pinned (shows on every workspace), opens bottom-right, sized to the
--    video's own shape inside a 480x360 box (16:9 -> 480x270, 9:16 -> 203x360, ...)
--    and keeps that shape when you resize it
--  • follows you: when another monitor gets focus, it moves to that monitor's corner
--  • SUPER+P tucks it into the nearest screen edge (a thin strip stays visible), so you
--    can drag it anywhere first; SUPER+P again, or clicking the strip, puts it back
--    exactly where it was
-- Remove the source("config/pip.lua") line in hyprland.lua to turn this off.

local MAX_W, MAX_H = 480, 360   -- the video is scaled to fit inside this box
local MARGIN = 24          -- gap to the screen edge
local STRIP = 28           -- how much stays visible while tucked

local restore = nil        -- where the window was before it got tucked {x, y}

pcall(hl.window_rule, {
    name = "pip_aspect",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    keep_aspect_ratio = true,
})

local function is_pip(w)
    return w ~= nil and (w.title == "Picture-in-Picture" or w.title == "Picture in picture")
end

local function find_pip()
    for _, w in ipairs(hl.get_windows()) do
        if is_pip(w) then return w end
    end
end

local function sel(w) return "address:" .. w.address end

-- usable area of a monitor in layout coordinates (minus the top bar etc.)
local function area(m)
    local s, r = m.scale or 1, m.reserved or {}
    local top, bottom = r.top or 0, r.bottom or 0
    return { x = m.x, y = m.y + top, w = m.width / s, h = m.height / s - top - bottom }
end

local function move_to(w, x, y)
    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = sel(w) }))
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- bottom-right corner of monitor m (where a new PiP opens, and where it lands on
-- another monitor)
local function place(w, m, ww, wh)
    m = m or w.monitor or hl.get_active_monitor()
    if not m then return end
    ww = ww or w.size.x
    wh = wh or w.size.y
    local a = area(m)
    restore = nil
    move_to(w, a.x + a.w - ww - MARGIN, a.y + a.h - wh - MARGIN)
end

-- which edge the window is tucked into, or nil. "Tucked" means only about the strip
-- is still on screen; a window just overhanging an edge after a drag doesn't count.
local function tucked_side(w, a)
    local x1, x2 = w.at.x, w.at.x + w.size.x
    local y1, y2 = w.at.y, w.at.y + w.size.y
    local vis_w = math.min(x2, a.x + a.w) - math.max(x1, a.x)
    local vis_h = math.min(y2, a.y + a.h) - math.max(y1, a.y)
    local limit = STRIP + 8
    if vis_w <= limit then return (x1 < a.x) and "left" or "right" end
    if vis_h <= limit then return (y1 < a.y) and "top" or "bottom" end
end

-- tuck into the nearest edge (or `side`), keeping the position along that edge.
-- (px, py) is the untucked position; defaults to where the window is now.
local function tuck(w, a, side, px, py)
    local ww, wh = w.size.x, w.size.y
    px, py = px or w.at.x, py or w.at.y
    if not side then
        local cx, cy = px + ww / 2, py + wh / 2
        local d = { left = cx - a.x, right = a.x + a.w - cx, top = cy - a.y, bottom = a.y + a.h - cy }
        side = "right"
        for k, v in pairs(d) do if v < d[side] then side = k end end
    end
    restore = { x = px, y = py }
    local x = clamp(px, a.x, a.x + a.w - ww)
    local y = clamp(py, a.y, a.y + a.h - wh)
    if side == "left" then x = a.x - ww + STRIP
    elseif side == "right" then x = a.x + a.w - STRIP
    elseif side == "top" then y = a.y - wh + STRIP
    else y = a.y + a.h - STRIP end
    move_to(w, x, y)
end

-- back to where it was before tucking; if that's unknown (e.g. after a config
-- reload), just pull it fully back on screen where it is
local function untuck(w, m, a)
    local ww, wh = w.size.x, w.size.y
    local p = restore or { x = w.at.x, y = w.at.y }
    move_to(w, clamp(p.x, a.x, a.x + a.w - ww), clamp(p.y, a.y, a.y + a.h - wh))
    restore = nil
end

local seen = {}   -- PiP windows already set up (by address)

local function setup(w)
    if not is_pip(w) or seen[w.address] then return end
    seen[w.address] = true
    -- browsers open the PiP window at the video's aspect ratio; keep it. (A window that
    -- isn't floating yet has a tile size, not the video's, so assume 16:9 then.)
    local ar = 16 / 9
    if w.floating and w.size and w.size.x > 0 and w.size.y > 0 then ar = w.size.x / w.size.y end
    local ww, wh = MAX_W, MAX_W / ar
    if wh > MAX_H then wh, ww = MAX_H, MAX_H * ar end
    ww, wh = math.floor(ww + 0.5), math.floor(wh + 0.5)
    if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set", window = sel(w) })) end
    hl.dispatch(hl.dsp.window.resize({ x = ww, y = wh, window = sel(w) }))
    if not w.pinned then hl.dispatch(hl.dsp.window.pin({ window = sel(w) })) end
    place(w, hl.get_active_monitor(), ww, wh)
end

local function by_address(addr)
    for _, w in ipairs(hl.get_windows()) do
        if w.address == addr then return w end
    end
end

-- browsers sometimes set the PiP title only after the window opens: check on open,
-- again a moment later, and on title changes
hl.on("window.open", function(w)
    if not w then return end
    setup(w)
    local addr = w.address
    hl.timer(function() local x = by_address(addr); if x then setup(x) end end, { timeout = 250, type = "oneshot" })
end)
hl.on("window.title", function()
    -- don't rely on the event argument: set up any PiP window not handled yet
    for _, w in ipairs(hl.get_windows()) do
        if is_pip(w) and not seen[w.address] then setup(w) end
    end
end)
hl.on("window.close", function(w) if w then seen[w.address] = nil end end)

-- follow the focused monitor
hl.on("monitor.focused", function(m)
    local w = find_pip()
    if not w or not m or (w.monitor and w.monitor.id == m.id) then return end
    local ws = m.active_workspace
    if not ws then return end
    -- same relative spot on the new monitor, still tucked into the same edge if it was
    local ww, wh = w.size.x, w.size.y
    local a0, a1 = area(w.monitor or m), area(m)
    local side = tucked_side(w, a0)
    local base = (side and restore) or { x = w.at.x, y = w.at.y }
    local fx = a0.w > ww and clamp((base.x - a0.x) / (a0.w - ww), 0, 1) or 1
    local fy = a0.h > wh and clamp((base.y - a0.y) / (a0.h - wh), 0, 1) or 1
    local nx, ny = a1.x + fx * (a1.w - ww), a1.y + fy * (a1.h - wh)
    -- a pinned window can't change workspace, so unpin -> move (without following) -> pin
    if w.pinned then hl.dispatch(hl.dsp.window.pin({ window = sel(w) })) end
    hl.dispatch(hl.dsp.window.move({ workspace = ws.id, follow = false, window = sel(w) }))
    hl.dispatch(hl.dsp.window.pin({ window = sel(w) }))
    if side then tuck(w, a1, side, nx, ny) else restore = nil; move_to(w, nx, ny) end
end)

-- clicking the tucked strip brings it back. This listens for real clicks (not focus:
-- switching to an empty workspace focuses the pinned PiP and must not expand it).
-- The click still reaches whatever is under the cursor.
local function on_click()
    local w = find_pip()
    if not w then return end
    local m = w.monitor or hl.get_active_monitor()
    if not m then return end
    local a = area(m)
    if not tucked_side(w, a) then return end
    local c = hl.get_cursor_pos()
    local cx, cy = c.x or c[1], c.y or c[2]
    -- only the part of the window that's on screen
    local x1, y1 = math.max(w.at.x, a.x), math.max(w.at.y, a.y)
    local x2, y2 = math.min(w.at.x + w.size.x, a.x + a.w), math.min(w.at.y + w.size.y, a.y + a.h)
    if cx >= x1 and cx <= x2 and cy >= y1 and cy <= y2 then untuck(w, m, a) end
end
local ok_click = pcall(hl.bind, "mouse:272", on_click, { non_consuming = true })
if not ok_click then
    pcall(hl.notification.create, { text = "pip.lua: couldn't bind click-to-expand (SUPER+P still works)", duration = 6000, icon = "warning" })
end

-- SUPER+P: tuck / untuck. Whether it's tucked is read from where the window is,
-- so it never gets out of sync.
function PipToggle()
    local w = find_pip()
    if not w then return end
    local m = w.monitor or hl.get_active_monitor()
    if not m then return end
    local a = area(m)
    if tucked_side(w, a) then untuck(w, m, a) else tuck(w, a) end
end

hl.bind("SUPER + P", function() PipToggle() end)

-- PiP windows already open when the config (re)loads: keep them where and how big
-- they are (a reload must not move or resize them), just make sure they're floating
-- and pinned
for _, w in ipairs(hl.get_windows()) do
    if is_pip(w) then
        seen[w.address] = true
        if not w.floating then hl.dispatch(hl.dsp.window.float({ action = "set", window = sel(w) })) end
        if not w.pinned then hl.dispatch(hl.dsp.window.pin({ window = sel(w) })) end
    end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ HYPRLIQUID (liquid glass, as revo-shell used it)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Remove the source("config/hyprliquid.lua") line in hyprland.lua to turn this off.
--
-- The look (effect, tint, thickness, ...) lives in config/hyprliquid.json. "global" applies to every
-- surface; a key inside "surfaces.<name>" overrides it for that surface only.
-- config/hyprliquid.defaults.json is the fallback.
-- What stays here is the plumbing per surface: which layer/window it matches and
-- how the glass gets its shape (vdf_map_mode).

-- hyprliquid 0.3.0 hangs Hyprland at login if it is loaded while the config is
-- first parsed (hl.plugin.load here), but loads fine once Hyprland is running.
-- So: on startup, load it from outside via hyprctl, then reload so the rules
-- below get applied. On later reloads the plugin is already there.
if not hl.plugin.hyprliquid then
    hl.on("hyprland.start", function()
        hl.exec_cmd("sleep 1; hyprctl plugin load /usr/lib/libhyprliquid.so && hyprctl reload")
    end)
    return -- rules need the plugin; they get applied by that reload
end

-- (restart Hyprland after changing these)
hl.config({
    plugin = {
        hyprliquid = {
            watch_system_color_scheme = false,
            background_sharing = false,
        },
    },
})

local HYPR = os.getenv("HOME") .. "/.config/hypr"
local json = loadfile(HYPR .. "/config/json.lua")()

local function notify(msg)
    pcall(hl.notification.create, { text = "hyprliquid: " .. msg, duration = 8000, icon = "warning" })
end

local settings, err = json.read(HYPR .. "/config/hyprliquid.json")
if type(settings) ~= "table" then
    if err and not tostring(err):find("No such file") then
        notify("config/hyprliquid.json unreadable (" .. tostring(err) .. "), using defaults")
    end
    settings = json.read(HYPR .. "/config/hyprliquid.defaults.json") or {}
end
local global   = settings.global or {}
local surfaces = settings.surfaces or {}

-- [r, g, b, a] (0-255, 0-1) -> Hyprland color string
local function rgba(t)
    if type(t) ~= "table" then return nil end
    return ("rgba(0x%02x, 0x%02x, 0x%02x, %.3f)"):format(
        math.floor(t[1] or 0), math.floor(t[2] or 0), math.floor(t[3] or 0), t[4] or 1)
end

-- Tunable keys, in JSON name -> how they are written into the rule.
local TUNABLES = {
    effect           = function(v) return "effect", v end,
    tint             = function(v) return "tint_color", rgba(v) end,
    glass_thickness  = function(v) return "glass_thickness", v end,
    highlight_style  = function(v) return "highlight_style", math.floor(v) end,
    glass_dispersion = function(v) return "glass_dispersion", v == true end,
    brightness       = function(v) return "brightness", v end,
    glass_ior        = function(v) return "glass_ior", v end,
    color_scheme     = function(v) return "color_scheme", v end,
    corner_radius    = function(v) return "corner_radius", math.floor(v) end,
}

-- Surfaces whose glass is shaped from the client's alpha (vdf_map_mode 1). Only
-- liquid_glass uses that shape: acrylic/mica/aero fill the whole surface, and
-- qs-master is a full-screen layer, so any other effect blacks out the screen.
-- These stay liquid_glass whatever effect is picked (none still turns them off).
local ALPHA_SHAPED = { ["qs-master"] = true, ["qs-popups"] = true, ["swayosd"] = true }

-- Build the "hyprliquid:*" keys for one surface: global values, overridden per surface.
local function glass_props(name)
    local s = surfaces[name] or {}
    if s.enabled == false then return nil end
    local props = {}
    for key, conv in pairs(TUNABLES) do
        local v = s[key]
        if v == nil then v = global[key] end
        if v ~= nil then
            local k, out = conv(v)
            if out ~= nil then props["hyprliquid:" .. k] = out end
        end
    end
    if (props["hyprliquid:effect"] or "none") == "none" then return nil end
    if ALPHA_SHAPED[name] then props["hyprliquid:effect"] = "liquid_glass" end
    return props
end

local function merge(base, extra)
    for k, v in pairs(extra) do base[k] = v end
    return base
end

-- Hyprland blur behind the glass ("blur" in hyprliquid.json, global or per surface).
-- ignore_alpha: only pixels more opaque than this get blurred, so the transparent
-- parts of full-screen layers like qs-master stay untouched. Keep it below the
-- popups' outer fill alpha (0.06 in the QML) or their background won't blur.
-- Blur strength itself is decoration.blur in settings (size/passes), shared by all.
local function blur_props(name)
    local s = surfaces[name] or {}
    local on = s.blur
    if on == nil then on = global.blur end
    if on ~= true then return {} end
    return { blur = true, ignore_alpha = s.blur_ignore_alpha or global.blur_ignore_alpha or 0.03 }
end

local function glass_layer(name, rule)
    local props = glass_props(name)
    if not props then return end
    props = merge(props, blur_props(name))
    local ok, e = pcall(hl.layer_rule, merge(merge({ name = name .. "_glass" }, rule), props))
    if not ok then notify(name .. ": " .. tostring(e)) end
end

local function glass_window(name, rule)
    local props = glass_props(name)
    if not props then return end
    -- Hyprland's Lua API caps the normal rounding rule at 20; match the glass instead
    props["hyprliquid:rounding_lua"] = props["hyprliquid:corner_radius"]
    local ok, e = pcall(hl.window_rule, merge(merge({ name = name .. "_glass" }, rule), props))
    if not ok then notify(name .. ": " .. tostring(e)) end
end

-- All quickshell popups share the full-screen qs-master layer; the glass takes its
-- shape from the popup's alpha (vdf_map_mode 1; mode 0 would cover the whole screen),
-- so it only shows through popups whose background is translucent (every popup except
-- the wallpaper picker). The edge depth (z_radius) follows corner_radius, so a large
-- radius = a wide refracting band. Keep corner_radius equal to the popup's QML radius.
glass_layer("qs-master", {
    match = { namespace = "^(qs-master)$" },
    ["hyprliquid:vdf_map_mode"] = 1,
    ["hyprliquid:vdf_map_update_policy"] = "onchange",
})

-- Top bar: its own strip-sized layer, so vdf_map_mode 0 (whole surface = one rounded
-- rect) works without any visible background. Corner 16 = half the bar height, so the
-- refracting edge band spans the whole bar. Dispersion is off by default here: at the
-- screen edge the R/G/B split samples above the bar and draws a 1px coloured line that
-- flickers on workspace switches. Thickness 120 (default 500) keeps the edge from
-- pulling in the wallpaper strip above the bar and window borders below it.
glass_layer("qs-topbar", {
    match = { namespace = "^(qs-topbar)$" },
    ["hyprliquid:vdf_map_mode"] = 0,
})

-- Vicinae launcher (SUPER+D): its surface is exactly the window (shadow off in
-- ~/.config/vicinae/settings.json), so mode 0 fits; its client-side rounding must match
-- corner_radius. Above ~60 the corners cut into its search field and footer. Darker
-- tint by default: keeps the wide warp band from fighting the text.
glass_layer("vicinae", {
    match = { namespace = "^(vicinae)$" },
    ["hyprliquid:vdf_map_mode"] = 0,
})

-- SwayOSD (volume/brightness/caps-lock sliders): its surface has a 16px transparent
-- margin, so the glass is shaped from alpha (mode 1). corner_radius = border-radius in
-- ~/.config/swayosd/style.css (edit matugen/templates/swayosd.css.template, not style.css).
glass_layer("swayosd", {
    match = { namespace = "^(swayosd)$" },
    ["hyprliquid:vdf_map_mode"] = 1,
    ["hyprliquid:vdf_map_update_policy"] = "onchange",
})

-- Notification toasts (top right): one column layer holding every toast, so the glass
-- is shaped from alpha (mode 1). corner_radius = the card radius in WindowRegistry.js
-- getPopupLayout (s(24)).
glass_layer("qs-popups", {
    match = { namespace = "^(qs-popups)$" },
    ["hyprliquid:vdf_map_mode"] = 1,
    ["hyprliquid:vdf_map_update_policy"] = "onchange",
})


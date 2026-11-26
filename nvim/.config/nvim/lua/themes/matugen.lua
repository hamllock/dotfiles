-- this line for types, by hovering and autocompletion (lsp required)
-- will help you understanding properties, fields, and what highlightings the color used for
---@type Base46Table
local M = {}

M.type = "dark"

local c = require "matugen_colors"

-- UI
M.base_30 = {
  white = c.text,
  black = c.base, -- usually your theme bg
  darker_black = c.crust, -- 6% darker than black
  black2 = c.mantle, -- 6% lighter than black
  one_bg = c.surface0, -- 10% lighter than black
  one_bg2 = c.surface1, -- 6% lighter than one_bg
  one_bg3 = c.surface2, -- 6% lighter than one_bg2
  grey = c.overlay0, -- 40% lighter than black
  grey_fg = c.overlay1, -- 10% lighter than grey
  grey_fg2 = c.overlay2, -- 5% lighter than grey
  light_grey = c.subtext0,
  red = c.red,
  baby_pink = c.rosewater,
  pink = c.pink,
  line = c.surface0, -- 15% lighter than black
  green = c.green,
  vibrant_green = c.teal,
  nord_blue = c.sapphire,
  blue = c.blue,
  seablue = c.sky,
  yellow = c.yellow,
  sun = c.peach,
  purple = c.mauve,
  dark_purple = c.lavender,
  teal = c.teal,
  orange = c.flamingo,
  cyan = c.sky,
  statusline_bg = c.mantle,
  lightbg = c.surface1,
  pmenu_bg = c.blue,
  folder_bg = c.blue,
}

-- base00 - Default Background
-- base01 - Lighter Background (Used for status bars, line number and folding marks)
-- base02 - Selection Background
-- base03 - Comments, Invisibles, Line Highlighting
-- base04 - Dark Foreground (Used for status bars)
-- base05 - Default Foreground, Caret, Delimiters, Operators
-- base06 - Light Foreground (Not often used)
-- base07 - Light Background (Not often used)
-- base08 - Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
-- base09 - Integers, Boolean, Constants, XML Attributes, Markup Link Url
-- base0A - Classes, Markup Bold, Search Text Background
-- base0B - Strings, Inherited Class, Markup Code, Diff Inserted
-- base0C - Support, Regular Expressions, Escape Characters, Markup Quotes
-- base0D - Functions, Methods, Attribute IDs, Headings
-- base0E - Keywords, Storage, Selector, Markup Italic, Diff Changed
-- base0F - Deprecated, Opening/Closing Embedded Language Tags, e.g. <?php ?>
M.base_16 = {
  base00 = c.base, -- Default Background
  base01 = c.mantle, -- Lighter Background (status bars, line numbers)
  base02 = c.surface0, -- Selection Background
  base03 = c.overlay0, -- Comments, Invisibles, Line Highlighting
  base04 = c.subtext0, -- Dark Foreground (status bars)
  base05 = c.text, -- Default Foreground
  base06 = c.subtext1, -- Light Foreground
  base07 = c.overlay2, -- Light Background
  base08 = c.red, -- Variables, XML Tags, Diff Deleted
  base09 = c.peach, -- Integers, Boolean, Constants
  base0A = c.yellow, -- Classes, Markup Bold, Search Text Background
  base0B = c.green, -- Strings, Diff Inserted
  base0C = c.teal, -- Support, Regular Expressions, Escape Characters
  base0D = c.blue, -- Functions, Methods, Headings
  base0E = c.mauve, -- Keywords, Storage, Selector
  base0F = c.flamingo, -- Deprecated, Embedded Language Tags
}

return M

local options = {
    chunk = {
        enable = true,
        priority = 15,
        -- colours come from the active base46 theme (chadwal = matugen palette), so they
        -- follow the wallpaper; hlchunk re-evaluates this on every ColorScheme change.
        -- 1 = normal block, 2 = block containing a syntax error
        style = function()
            local ok, c = pcall(function() return require("base46").get_theme_tb "base_30" end)
            if not ok or not c then
                return { { fg = "#bcc2ff" }, { fg = "#ffb4ab" } }
            end
            return { { fg = c.blue }, { fg = c.red } }
        end,
        use_treesitter = true,
        chars = {
            horizontal_line = "─",
            vertical_line = "│",
            left_top = "╭",
            left_bottom = "╰",
            right_arrow = "─",
        },
        textobject = "",
        max_file_size = 1024 * 1024,
        error_sign = true,
        -- animation related
        duration = 100,
        delay = 100,
    },
}

return options

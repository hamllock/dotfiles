local options = {

  -- General options
  logo = "auto", -- "auto" or url
  logo_tooltip = "caca", -- nil or string
  main_image = "language", -- "language" or "logo"
  client_id = "1157438221865717891", -- Use your own Discord application client id (not recommended)
  log_level = nil, -- Log messages at or above this level (one of the following: "debug", "info", "warn", "error")
  debounce_timeout = 10, -- Number of seconds to debounce events (or calls to `:lua package.loaded.presence:update(<filename>, true)`)
  blacklist = {}, -- A list of strings or Lua patterns that disable Rich Presence if the current file name, path, or workspace matches
  file_assets = {}, -- Custom file asset definitions keyed by file names and extensions (see default config at `lua/presence/file_assets.lua` for reference)
  show_time = true, -- Show the timer
  global_timer = false, -- if set true, timer won't update when any event are triggered
}

return options

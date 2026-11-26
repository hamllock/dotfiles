require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

vim.filetype.add {
  pattern = {
    [".*%.blade%.php"] = "blade",
  },
}

-- Wrapped lines keep the indentation of the line they belong to (readable nested code)
vim.o.breakindent = true
vim.o.breakindentopt = "shift:2"   -- indent continuations 2 more columns so they stand out
vim.o.linebreak = true             -- wrap at word boundaries, not mid-word
vim.o.showbreak = "↪ "             -- mark where a wrapped line continues

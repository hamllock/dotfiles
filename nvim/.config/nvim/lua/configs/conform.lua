local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettierd" },
    html = { "prettierd" },
    javascript = { "prettierd", "prettier", stop_after_first = true },
    typescript = { "prettierd", "prettier", stop_after_first = true },
    javascriptreact = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
    c = { "clang-format" },
    cpp = { "clang-format" },
    glsl = { "clang-format" },
    php = { "pint" },
    blade = { "blade-formatter" },
  },

  format_after_save = {
    -- These options will be passed to conform.format()
    lsp_fallback = true,
    async = true,
  },

  formatters = {
    pint = {
      -- prefer project-local pint, fall back to globally installed one
      command = function()
        local local_pint = vim.fn.getcwd() .. "/vendor/bin/pint"
        if vim.fn.executable(local_pint) == 1 then
          return local_pint
        end
        return vim.fn.expand("~/.config/composer/vendor/bin/pint")
      end,
    },
    prettier = {
      options = {
        -- Use a specific prettier parser for a filetype
        -- Otherwise, prettier will try to infer the parser from the file name
        ft_parsers = {
          javascript = "babel",
          javascriptreact = "babel",
          typescript = "typescript",
          typescriptreact = "typescript",
          vue = "vue",
          css = "css",
          scss = "scss",
          less = "less",
          html = "html",
          json = "json",
          jsonc = "json",
          yaml = "yaml",
          markdown = "markdown",
          ["markdown.mdx"] = "mdx",
          graphql = "graphql",
          handlebars = "glimmer",
        },
        -- Use a specific prettier parser for a file extension
        ext_parsers = {
          -- qmd = "markdown",
        },
      },
    },
  },
}

return options

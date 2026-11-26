return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre", -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufWritePre", "BufNewFile" },
    config = function()
      local lint = require "lint"

      lint.linters_by_ft = {
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        svelte = { "eslint_d" },
        kotlin = { "ktlint" },
        terraform = { "tflint" },
        cpp = { "clangtidy" },
        php = { "phpcs" },
      }

      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          lint.try_lint()
        end,
      })

      vim.keymap.set("n", "<leader>ll", function()
        lint.try_lint()
      end, { desc = "Trigger linting for current file" })
    end,
  },

  {
    "Iogamaster/neocord",
    lazy = false,
    opts = require "configs.neocord",
  },

  {
    "nvchad/showkeys",
    cmd = "ShowkeysToggle",
    opts = {
      timeout = 1,
      maxkeys = 3,
      position = "top-right",
    },
  },

  {
    "folke/snacks.nvim",
    lazy = false,
    opts = require "configs.snacks",
    keys = {
      {
        "<leader>z",
        function()
          Snacks.zen()
        end,
        desc = "Toggle Zen Mode",
        mode = "n",
      },
      {
        "<leader>rc",
        function()
          Snacks.rename.rename_file()
        end,
        desc = "Rename File",
      },
    },
  },

  {
    "akinsho/flutter-tools.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim",
    },
    config = function()
      require("configs.flutter-tools")
    end,
  },

  {
    "stevearc/dressing.nvim",
    lazy = false,
  },

  {
    "williamboman/mason.nvim",
    lazy = true,
    config = function()
      require("mason").setup {
        registries = {
          "github:Crashdummyy/mason-registry",
          "github:mason-org/mason-registry",
        },
      }
    end,
  },
  -- lazy.nvim
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = require "configs.noice",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
  },

  {
    url = "https://codeberg.org/andyg/leap.nvim",
    lazy = false,
    dependencies = { "tpope/vim-repeat" },
    opts = {},
  },

  -- nvim-treesitter's `main` branch (the rewrite) no longer installs parsers from
  -- ensure_installed or starts highlighting by itself. Install parsers here and start
  -- Treesitter per buffer. Building parsers needs the `tree-sitter` CLI
  -- (pacman -S tree-sitter-cli) and a C compiler. hlchunk's block lines need these too.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local langs = {
        "c", "cpp", "lua", "luadoc", "vim", "vimdoc", "query", "markdown", "markdown_inline",
        "python", "bash", "json", "toml", "yaml", "html", "css", "javascript", "typescript", "tsx",
        "rust", "go", "dart", "php", "glsl", "qmljs", "cmake", "java", "regex", "printf",
      }
      if vim.fn.executable "tree-sitter" == 1 then
        pcall(function() require("nvim-treesitter").install(langs) end)
      end
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          if pcall(vim.treesitter.start, ev.buf) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  {
    "shellRaining/hlchunk.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = require "configs.hlchunk",
    config = function(_, opts)
      -- hlchunk draws one bar per buffer line, so wrapped rows show a gap. Neovim can
      -- repeat a mark on wrapped rows (virt_text_repeat_linebreak); hlchunk doesn't ask
      -- for it, so add it to the vertical bar pieces it draws (not the corners/arrows).
      local ns = vim.api.nvim_create_namespace "chunk" -- hlchunk's chunk namespace
      local bar = opts.chunk.chars.vertical_line
      local set_extmark = vim.api.nvim_buf_set_extmark
      vim.api.nvim_buf_set_extmark = function(buf, id, row, col, o)
        if id == ns and o and o.virt_text and o.virt_text[1] and o.virt_text[1][1] == bar then
          o = vim.tbl_extend("force", {}, o) -- hlchunk reuses one opts table for every mark
          o.virt_text_repeat_linebreak = true
        end
        return set_extmark(buf, id, row, col, o)
      end
      require("hlchunk").setup(opts)
    end,
  },

  {
    "kawre/leetcode.nvim",
    build = ":TSUpdate html",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    opts = require "configs.leetcode",
    cmd = "Leet",
    -- load at startup when launched as `nvim leetcode.nvim` (the dash's LeetCode button)
    lazy = "leetcode.nvim" ~= vim.fn.argv(0, -1),
  },

  {
    "pmizio/typescript-tools.nvim",
    ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
    dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
    opts = require "configs.typescript-tools",
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("nvchad.configs.lspconfig").defaults()
      require "configs.lspconfig"
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      win = {
        padding = { 0, 5 },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show { global = false }
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" }, -- if you prefer nvim-web-devicons,

    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {},
  },
  {
    "f-person/git-blame.nvim",
    --load the plugin at startup
    event = "VeryLazy",
    -- Because of the keys part, you will be lazy loading this plugin- The plugin will only load once one of the keys is used.
    -- If you want to load the plugin at startup, add something like event = "VeryLazy",
    -- or lazy = false. One of both options will work.
    opts = {
      -- your configuration comes here
      -- for example
      enabled = true, -- if you want to enable the plugin
      message_template = " <author> • <date> • <summary> • <<sha>>", -- template for the blame message, check the Message template section for more options
      date_format = "%m-%d-%Y %H:%M:%S", -- template for the date, check Date format section for more options
      virtual_text_column = 1, -- virtual text start column, check Start virtual text at column section for more options
    },
  },

  {
    "kdheepak/lazygit.nvim",
    lazy = false,
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    -- optional for floating window border decoration
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    -- setting the keybinding for LazyGit with 'keys' is recommended in
    -- order to load the plugin when the command is run for the first time
    keys = {
      { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
    },
  },

  {
    "mrcjkb/rustaceanvim",
    version = "^6", --  estable version
    ft = { "rust" }, -- Load only with Rust files
    config = function()
      vim.g.rustaceanvim = {
        tools = {
          hover_actions = {
            auto_focus = true,
          },
        },
        dap = {
          autoload_config = true, -- rustaceanvim configure codelldb
        },
      }
    end,
  },

  {
    "rust-lang/rust.vim",
    ft = "rust",
    init = function()
      vim.g.rustfmt_autosave = 1
    end,
  },

  {
    "mfussenegger/nvim-dap",
    config = function()
      require "configs.dap"
    end,
  },

  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      require("dapui").setup()
    end,
  },

  {
    "Civitasv/cmake-tools.nvim",
    event = "VeryLazy",
    opts = {},
  },

  {
    "tikhomirov/vim-glsl",
    ft = { "glsl", "vert", "frag", "vs", "fs", "gs", "comp" },
  },

  {
    "timtro/glslView-nvim",
    ft = "glsl",
    opts = {
      viewer_path = "glslView", -- ensure this is in your PATH
      args = { "-w" }, -- watch for changes
    },
  },

  {
    "saecki/crates.nvim",
    ft = { "toml" },
    config = function()
      require("crates").setup {
        completion = {
          cmp = {
            enabled = true,
          },
        },
      }
      require("cmp").setup.buffer {
        sources = { { name = "crates" } },
      }
    end,
  },

  {
    "Axenide/WallSync",
    lazy = false,
    main = "wallsync",
    opts = {},
  },
  -- {
  --   "olimorris/codecompanion.nvim",
  --   opts = require("configs.codecompanion"),
  --   event = "InsertEnter",
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     "nvim-treesitter/nvim-treesitter",
  --     "ravitemer/mcphub.nvim",
  --   },
  -- },
  -- {
  --   "MeanderingProgrammer/render-markdown.nvim",
  --   ft = { "markdown", "codecompanion" },
  -- },
  -- {
  --   "OXY2DEV/markview.nvim",
  --   lazy = false,
  --   opts = {
  --     preview = {
  --       filetypes = { "markdown", "codecompanion" },
  --       ignore_buftypes = {},
  --     },
  --   },
  -- },
  -- {
  --   "zbirenbaum/copilot.lua",
  --   opts = require("configs.copilot"),
  --   event = "InsertEnter",
  --   config = function()
  --     require("copilot").setup({})
  --   end,
  -- },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "vim",
        "lua",
        "vimdoc",
        "html",
        "css",
        "cpp",
        "c",
        "glsl",
        "cmake",
        "typescript",
        "tsx",
        "php",
        "dart",
      },
    },
    config = function(_, opts)
      local configs_status, configs = pcall(require, "nvim-treesitter.configs")
      if configs_status then
        configs.setup(opts)
      end

      local parser_status, parsers = pcall(require, "nvim-treesitter.parsers")
      if parser_status then
        parsers.blade = {
          install_info = {
            url = "https://github.com/EmranMR/tree-sitter-blade",
            files = { "src/parser.c" },
            branch = "main",
          },
          filetype = "blade",
        }
      end
    end,
  },
}

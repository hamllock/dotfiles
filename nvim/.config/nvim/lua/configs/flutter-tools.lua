require("flutter-tools").setup({
  ui = {
    border = "rounded",
    notification_style = "native",
  },
  decorations = {
    statusline = {
      device = true,
      app_version = true,
    }
  },
  debugger = {
    enabled = true,
    run_via_dap = true,
    register_configurations = function(_)
      require("dap").configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch Flutter App",
          program = "lib/main.dart",
          cwd = "${workspaceFolder}",
        }
      }
    end,
  },
  lsp = {
    color_factor = 2.1,
    settings = {
      showTodos = true,
      completeFunctionCalls = true,
      renameFilesWithClasses = "always",
      enableSdkFormatter = true,
    },
  },
})

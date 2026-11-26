-- load defaults (diagnostics config, LspAttach keymaps, capabilities, lua_ls)
require("nvchad.configs.lspconfig").defaults()

-- Servers that need no extra config beyond the global defaults
-- (capabilities + on_init are already set globally by nvchad.configs.lspconfig.defaults())
local servers = {
    "html",
    "cssls",
    "eslint",
    "emmet_language_server",
    "tailwindcss",
    "clangd",
    "glsl_analyzer",
    "intelephense",
}

for _, lsp in ipairs(servers) do
    vim.lsp.enable(lsp)
end

vim.lsp.config("pyright", {
    on_init = function(client)
        local root = client.workspace_folders and client.workspace_folders[1] and client.workspace_folders[1].name
        if root then
            client.config.settings.python = client.config.settings.python or {}
            client.config.settings.python.venvPath = root
            client.config.settings.python.venv = "venv"
            client.notify("workspace/didChangeConfiguration", { settings = client.config.settings })
        end
    end,
})
vim.lsp.enable("pyright")


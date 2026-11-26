require("nvchad.mappings")

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map({ "n", "x", "o" }, "s", "<Plug>(leap-forward)")
map({ "n", "x", "o" }, "S", "<Plug>(leap-backward)")
map({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)")
map("n", "<leader>a", "<cmd>CopilotChatToggle<cr>", { noremap = true, silent = true })
map("v", "<leader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Lsp Code Action" })
map("n", "<leader>ra", require("nvchad.lsp.renamer"), { desc = "NvRenamer" })
map("n", "<leader>gv", "<cmd>GlslView<cr>", { desc = "GLSL Live Preview" })

map("v", "y", [["+y]], { desc = "Yank to system clipboard." })
map({ "v", "n" }, "p", [["+p]], { desc = "Paste from system clipboard." })

-- Nvim DAP
map("n", "<Leader>dl", "<cmd>lua require'dap'.step_into()<CR>", { desc = "Debugger step into" })
map("n", "<Leader>dj", "<cmd>lua require'dap'.step_over()<CR>", { desc = "Debugger step over" })
map("n", "<Leader>dk", "<cmd>lua require'dap'.step_out()<CR>", { desc = "Debugger step out" })
map("n", "<Leader>dc", "<cmd>lua require'dap'.continue()<CR>", { desc = "Debugger continue" })
map("n", "<Leader>db", "<cmd>lua require'dap'.toggle_breakpoint()<CR>", { desc = "Debugger toggle breakpoint" })
map(
  "n",
  "<Leader>dd",
  "<cmd>lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>",
  { desc = "Debugger set conditional breakpoint" }
)
map("n", "<Leader>de", "<cmd>lua require'dap'.terminate()<CR>", { desc = "Debugger reset" })
map("n", "<Leader>dr", "<cmd>lua require'dap'.run_last()<CR>", { desc = "Debugger run last" })

-- rustaceanvim
map("n", "<Leader>dt", "<cmd>lua vim.cmd('RustLsp testables')<CR>", { desc = "Debugger testables" })
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- LeetCode (files under ~/leetcode): run / submit through the LeetCode window
-- (~/.config/hypr/scripts/quickshell/leetcode). The window saves this buffer first.
vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
  pattern = vim.fn.expand "~" .. "/leetcode/*",
  callback = function(ev)
    local qml = vim.fn.expand "~/.config/hypr/scripts/quickshell/leetcode/LeetCode.qml"
    local function lc(action)
      return function()
        vim.cmd "silent! write"
        vim.system { "quickshell", "ipc", "-p", qml, "call", "lc", action }
      end
    end
    map("n", "<leader>lr", lc "run", { buffer = ev.buf, desc = "LeetCode run" })
    map("n", "<leader>ls", lc "submit", { buffer = ev.buf, desc = "LeetCode submit" })
  end,
})

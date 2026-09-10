-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Merged from nvim-personal (Jalovec backup).

local map = LazyVim.safe_keymap_set

vim.api.nvim_set_keymap(
  "n",
  "<A-h>",
  "<cmd>BufferLineMovePrev<CR>",
  { noremap = true, silent = true, desc = "Move tab left" }
)
vim.api.nvim_set_keymap(
  "n",
  "<A-l>",
  "<cmd>BufferLineMoveNext<CR>",
  { noremap = true, silent = true, desc = "Move tab right" }
)

-- exit insert mode
map("i", "jk", "<ESC>", { noremap = true })

map("n", "gh", function()
  return vim.lsp.buf.hover()
end, { desc = "Hover" })

-- delete buffer
map("n", "<C-q>", function()
  Snacks.bufdelete()
end, { desc = "Delete Buffer" })

map("t", "<C-n>", "<C-\\><C-N>", { noremap = true, silent = true, desc = "Terminal to normal mode" })
map("n", "<leader>cX", "<cmd>LspRestart<cr>", { noremap = true, desc = "Lsp restart" })

-- Same as bash Ctrl+f → tmux-sessionizer (nvim-personal)
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

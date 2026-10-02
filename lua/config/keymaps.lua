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

-- Terminal: LazyVim maps <C-/> and <C-_>. On Ubuntu, Ctrl+7 often already sends
-- the same byte as <C-_>; Alacritty does not, so bind <C-7> explicitly too.
local function focus_term()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root() })
end
map({ "n", "t" }, "<C-7>", focus_term, { desc = "Terminal (Root Dir)" })

-- Bash herdr-sessionizer (same as shell Ctrl+f). noice <c-f> disabled in
-- plugins/herdr-sessionizer.lua. Needs a real TTY for fzf — do not use silent
-- (silent :! has no TTY → herdr-sessionizer exits instantly). Snacks.terminal
-- gives a pty; auto_close when the CLI exits.
vim.schedule(function()
  vim.keymap.set("n", "<C-f>", function()
    Snacks.terminal({ "herdr-sessionizer" }, { auto_close = true, interactive = true })
  end, { desc = "herdr-sessionizer" })
end)

--- Per-project herdr workspace labels (git root folder name, not a shared "herd.nvim").
local M = {}

---@return string
function M.label()
  local cwd = vim.fn.getcwd()
  local root = vim.fs.root(cwd, { ".git" }) or cwd
  return vim.fn.fnamemodify(root, ":t")
end

function M.apply()
  local Config = require("herd.config")
  local orig_get = Config.get

  function Config.get()
    local cfg = orig_get()
    cfg.workspace = M.label()
    return cfg
  end
end

return M

--- Per-project herdr *agent host* workspace (float mode).
--- Label must NOT equal the editor project workspace: herd float spawn parks
--- agents in cfg.workspace then prunes every agentless tab there — if that is
--- the same workspace as nvim, prune closes the nvim tab (looks like nvim "exits"
--- and the agent takes its place).
local M = {}

---@return string project folder name (git root basename)
function M.project()
  local cwd = vim.fn.getcwd()
  local root = vim.fs.root(cwd, { ".git" }) or cwd
  return vim.fn.fnamemodify(root, ":t")
end

---@return string dedicated agent-host workspace label for this project
function M.label()
  return "herd:" .. M.project()
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

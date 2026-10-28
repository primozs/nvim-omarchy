--- Pure helper: what a herd terminal-mode Ctrl+hjkl sends at the window edge.
local M = {}

--- At the edge (no neighbor in `dir`), return the expr string to feed the PTY.
--- Ctrl+L is no-op so Cursor Agent does not clear on a double pane-hop.
---@param dir "h"|"j"|"k"|"l"
---@return string
function M.edge_passthrough(dir)
  if dir == "l" then
    return ""
  end
  return ("<C-%s>"):format(dir)
end

return M

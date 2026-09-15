--- Pure helpers for keeping the herd right-split at a fixed width.
local M = {}

--- Only full UI resizes; WinResized re-fires when we set_width and fights drags.
M.RESTORE_EVENTS = { "VimResized" }

---@param entries table<any, { win?: integer }>
---@param target_width integer
---@param get_width fun(win: integer): integer
---@param is_valid fun(win: integer): boolean
---@return integer[]
function M.wins_needing_restore(entries, target_width, get_width, is_valid)
  local wins = {}
  for _, e in pairs(entries) do
    local win = e.win
    if win and is_valid(win) and get_width(win) ~= target_width then
      wins[#wins + 1] = win
    end
  end
  return wins
end

return M

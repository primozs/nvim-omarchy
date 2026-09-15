-- Prove-it: herd split width restore policy (review findings).
-- Run: nvim -l tests/run.lua

local width = require("herd.split_width")

describe("herd.split_width.RESTORE_EVENTS", function()
  it("listens only to VimResized (not WinResized)", function()
    assert.are.same({ "VimResized" }, width.RESTORE_EVENTS)
    for _, event in ipairs(width.RESTORE_EVENTS) do
      assert.are_not.equal("WinResized", event)
    end
  end)
end)

describe("herd.split_width.wins_needing_restore", function()
  local function is_valid(win)
    return win ~= nil and win > 0
  end

  it("returns wins whose width differs from the target", function()
    local widths = { [10] = 60, [11] = 80 }
    local entries = {
      a = { win = 10 },
      b = { win = 11 },
    }
    local got = width.wins_needing_restore(entries, 80, function(w)
      return widths[w]
    end, is_valid)
    table.sort(got)
    assert.are.same({ 10 }, got)
  end)

  it("skips wins already at the target width", function()
    local entries = { a = { win = 7 } }
    local got = width.wins_needing_restore(entries, 80, function()
      return 80
    end, is_valid)
    assert.are.same({}, got)
  end)

  it("skips missing or invalid wins", function()
    local entries = {
      a = { win = nil },
      b = {},
      c = { win = -1 },
    }
    local got = width.wins_needing_restore(entries, 80, function()
      return 40
    end, is_valid)
    assert.are.same({}, got)
  end)
end)

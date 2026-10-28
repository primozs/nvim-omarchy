-- Prove-it: herd terminal edge passthrough (Ctrl+L must not reach Cursor Agent).
-- Run: nvim -l tests/run.lua tests/herd/nav_edge_spec.lua

local nav_edge = require("herd.nav_edge")

describe("herd.nav_edge.edge_passthrough", function()
  it("no-ops Ctrl+L at the right edge", function()
    assert.are.equal("", nav_edge.edge_passthrough("l"))
  end)

  it("still passes through h/j/k at the edge", function()
    assert.are.equal("<C-h>", nav_edge.edge_passthrough("h"))
    assert.are.equal("<C-j>", nav_edge.edge_passthrough("j"))
    assert.are.equal("<C-k>", nav_edge.edge_passthrough("k"))
  end)
end)

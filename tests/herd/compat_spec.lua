-- Prove-it: herd.compat attach --takeover + nameless detected agents.
-- Run: nvim -l tests/run.lua

-- Load plugin herdr/picker from lazy path when not already on rtp.
do
  local lazy = vim.fn.stdpath("data") .. "/lazy/herd.nvim"
  if vim.uv.fs_stat(lazy) then
    vim.opt.rtp:prepend(lazy)
  end
end

local Compat = require("herd.compat")
Compat.apply()

local Herdr = require("herd.herdr")
local Picker = require("herd.picker")

describe("herd.compat.attach_argv", function()
  it("adds --takeover for herdr ≥ 0.9 single-controller attach", function()
    assert.are.same(
      { "herdr", "agent", "attach", "w1:p2", "--takeover" },
      Herdr.attach_argv("w1:p2")
    )
  end)

  it("is idempotent when applied twice", function()
    Compat.apply()
    assert.are.same(
      { "herdr", "agent", "attach", "cursor", "--takeover" },
      Herdr.attach_argv("cursor")
    )
  end)
end)

describe("herd.compat.agents", function()
  it("includes nameless detected agents keyed by pane_id", function()
    local saved = Herdr.api
    Herdr.api = function()
      return {
        agents = {
          {
            name = "cursor",
            pane_id = "w1:p1",
            tab_id = "w1:t1",
            workspace_id = "w1",
            agent_status = "idle",
            cwd = "/tmp/a",
            agent = "cursor",
          },
          {
            pane_id = "w1:p2",
            tab_id = "w1:t2",
            workspace_id = "w1",
            agent_status = "working",
            cwd = "/tmp/a",
            agent = "cursor",
          },
          {
            name = "",
            pane_id = "w1:p3",
            tab_id = "w1:t3",
            workspace_id = "w1",
            agent_status = "idle",
            cwd = "/tmp/a",
            agent = "codex",
          },
          {
            pane_id = "w2:p1",
            tab_id = "w2:t1",
            workspace_id = "w2",
            agent_status = "idle",
            cwd = "/tmp/b",
            agent = "codex",
          },
        },
      }
    end

    local all = Herdr.agents()
    assert.are.equal(4, #all)

    local scoped = Herdr.agents(vim.fs.normalize("/tmp/a"))
    assert.are.equal(3, #scoped)

    local detected = vim.tbl_filter(function(a)
      return a.detected
    end, scoped)
    assert.are.equal(2, #detected)
    assert.are.equal("w1:p2", detected[1].name)
    assert.are.equal("w1:p2", detected[1].pane_id)
    assert.are.equal("cursor", detected[1].kind)
    assert.is_true(detected[1].detected)
    assert.are.equal("w1:p3", detected[2].name)
    assert.is_true(detected[2].detected)

    local named = vim.tbl_filter(function(a)
      return not a.detected
    end, scoped)
    assert.are.equal(1, #named)
    assert.are.equal("cursor", named[1].name)
    assert.is_false(named[1].detected)

    Herdr.api = saved
  end)
end)

describe("herd.compat.picker labels", function()
  it("marks detected agents in the project picker", function()
    local items = Picker.items({
      {
        name = "w1:p2",
        pane_id = "w1:p2",
        status = "idle",
        cwd = "/tmp/a",
        detected = true,
        kind = "cursor",
      },
    }, {})
    assert.are.equal(1, #items)
    assert.are.equal("cursor  [idle]  · detected", items[1].label)
  end)

  it("keeps · detected in the global picker label", function()
    local items = Picker.items_global({
      {
        name = "w1:p2",
        pane_id = "w1:p2",
        tab_id = "w1:t2",
        workspace_id = "w1",
        status = "working",
        cwd = "/tmp/a",
        detected = true,
        kind = "cursor",
      },
    }, { w1 = "nvim" }, { ["w1:t2"] = "nvim:cursor" })
    assert.are.equal(1, #items)
    assert.are.equal("nvim:cursor  [working]  · nvim · detected", items[1].label)
  end)
end)

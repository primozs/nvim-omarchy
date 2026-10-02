--- Compatibility shims for herd.nvim against herdr ≥ 0.9.
--- Applied after require("herd").setup so we patch the live modules.
local M = {}

local applied = false

--- herdr ≥ 0.9: one controller owns a terminal; a second attach must take over
--- (TUI focus, a prior nvim attach, or another direct-attach client).
local function patch_attach_argv(Herdr)
  local orig = Herdr.attach_argv
  function Herdr.attach_argv(target)
    local argv = orig(target)
    if not vim.tbl_contains(argv, "--takeover") then
      argv[#argv + 1] = "--takeover"
    end
    return argv
  end
end

--- Manually launched agents are detected but nameless; herd.nvim skipped them,
--- so the picker only offered "+ tool" spawn rows — looking like "always spawn".
--- Include them keyed by pane_id (a valid attach target) and mark detected.
local function patch_agents(Herdr)
  function Herdr.agents(cwd)
    local res = Herdr.api({ "agent", "list" }, { quiet = true })
    local ret = {} ---@type herd.Agent[]
    for _, a in ipairs(res and res.agents or {}) do
      -- empty string is truthy in Lua; treat blank like missing (upstream skipped both)
      local has_name = a.name ~= nil and a.name ~= ""
      local name = has_name and a.name or a.pane_id
      if name and a.pane_id and (not cwd or vim.fs.normalize(a.cwd or "") == cwd) then
        ret[#ret + 1] = {
          name = name,
          pane_id = a.pane_id,
          tab_id = a.tab_id,
          workspace_id = a.workspace_id,
          status = a.agent_status,
          cwd = a.cwd,
          detected = not has_name,
          kind = a.agent,
        }
      end
    end
    return ret
  end
end

--- Nicer picker labels for detected (nameless) agents.
local function patch_picker(Picker)
  local function relabel(items)
    for _, it in ipairs(items) do
      local a = it.agent
      if a and a.detected then
        local kind = a.kind or "agent"
        local status = a.status or "?"
        if it.ws or it.tab_label then
          it.label = ("%s  [%s]  · %s · detected"):format(
            it.tab_label or kind,
            status,
            it.ws or "?"
          )
        else
          it.label = ("%s  [%s]  · detected"):format(kind, status)
        end
      end
    end
    return items
  end

  local orig_items = Picker.items
  function Picker.items(agents, tools)
    return relabel(orig_items(agents, tools))
  end

  local orig_global = Picker.items_global
  function Picker.items_global(agents, ws_labels, tab_labels)
    return relabel(orig_global(agents, ws_labels, tab_labels))
  end
end

function M.apply()
  if applied then
    return
  end
  applied = true
  local Herdr = require("herd.herdr")
  local Picker = require("herd.picker")
  patch_attach_argv(Herdr)
  patch_agents(Herdr)
  patch_picker(Picker)
end

return M

-- herd.nvim (MomePP) — herdr owns agent PTYs; we host them in a right split (Sidekick-style).
-- Keys under <leader>h* so LazyVim <leader>s and Sidekick <leader>ae* stay free.

local function global_picker()
  local Herdr = require("herd.herdr")
  if not Herdr.server_running() then
    vim.notify("herd: no herdr server running — launch `herdr` first", vim.log.levels.WARN)
    return
  end
  require("herd.picker").open_global(function(item)
    if not item.agent then
      return
    end
    local a = item.agent
    require("herd").target = a.name
    require("herd.terminal").open(a.name, { cwd = a.cwd, pane = a.pane_id })
  end)
end

local function sidekick_split_width()
  local ok, sk = pcall(require, "sidekick.config")
  if ok then
    local w = sk.cli.win.split.width
    if w and w > 0 then
      return w
    end
  end
  return 80
end

return {
  {
    "MomePP/herd.nvim",
    event = "VeryLazy",
    dependencies = { "folke/sidekick.nvim" },
    opts = {
      mode = "float", -- PTY host mode; display is patched to right split below
      -- workspace is set dynamically per git root (see herd.project_workspace)
      tools = {
        pi = { cmd = { "pi" } },
        -- claude = { cmd = { "claude" } },
        cursor = { cmd = { "cursor-agent" }, kind = "cursor" },
        codex = { cmd = { "codex" }, kind = "codex" },
      },
      keys = {
        -- Sidekick-shaped: hh toggle panel / send selection; hs pick or spawn agent
        toggle = "<leader>hh",
        send = "<leader>hh",
        hide = "<C-q>",
        select = "<leader>hs",
        dashboard = false,
        newline = "<S-CR>",
      },
    },
    config = function(_, opts)
      require("herd").setup(opts)
      require("herd.project_workspace").apply()
      require("herd.split_terminal").apply({ width = sidekick_split_width() })
      vim.keymap.set("n", "<leader>hS", global_picker, { desc = "herd: all projects" })
    end,
  },
  {
    -- Runs in every nvim; alerts when a herdr agent (any repo) is done or blocked.
    name = "herd-status-notify",
    dir = vim.fn.stdpath("config"),
    lazy = false,
    config = function()
      require("herd.status_notify").start({ interval_ms = 2000 })
    end,
  },
}

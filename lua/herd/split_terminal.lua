--- Right-split agent panel for herd.nvim (Sidekick-style layout).
--- herd.nvim only ships fullscreen floats; this replaces Terminal.open after setup.
local Herdr = require("herd.herdr")
local Watch = require("herd.watch")

local M = {}

local WINHIGHLIGHT =
  "Normal:SidekickChat,NormalNC:SidekickChat,EndOfBuffer:SidekickChat,SignColumn:SidekickChat"

--- name -> { gen: integer, handle?: vim.SystemObj }
local watchers = {}

local function ensure_sidekick_hl()
  pcall(require("sidekick.config").set_hl)
end

--- Match sidekick.cli.terminal split window chrome (background via SidekickChat → NormalFloat).
local function style_panel(win, buf)
  ensure_sidekick_hl()
  vim.wo[win].winhighlight = WINHIGHLIGHT
  vim.wo[win].colorcolumn = ""
  vim.wo[win].cursorcolumn = false
  vim.wo[win].cursorline = false
  vim.wo[win].fillchars = "eob: "
  vim.wo[win].list = false
  vim.wo[win].spell = false
  vim.wo[win].winbar = ""
  vim.bo[buf].swapfile = false
end

local function stop_watch(name)
  local state = watchers[name]
  if not state then
    return
  end
  state.gen = state.gen + 1
  if state.handle then
    pcall(state.handle.kill, state.handle, 15)
  end
  watchers[name] = nil
end

--- Close split + terminal buffer when the herdr agent exits (attach alone stays open at shell).
local function close_agent(Terminal, name)
  stop_watch(name)
  local cur = Terminal.reg[name]
  if not cur then
    return
  end

  local win = cur.win
  if win and vim.api.nvim_win_is_valid(win) then
    if vim.api.nvim_get_current_win() == win then
      local wins = vim.api.nvim_list_wins()
      if #wins == 1 then
        local listed = vim.tbl_filter(function(b)
          return vim.bo[b].buflisted and b ~= cur.buf
        end, vim.api.nvim_list_bufs())
        if listed[1] then
          vim.cmd.sbuffer(listed[1])
        else
          vim.cmd.enew()
        end
      else
        vim.cmd.wincmd("p")
      end
    end
    pcall(vim.api.nvim_win_close, win, true)
  end

  if cur.buf and vim.api.nvim_buf_is_valid(cur.buf) then
    local job = vim.b[cur.buf].terminal_job_id
    if job then
      pcall(vim.fn.jobstop, job)
    end
    pcall(vim.api.nvim_buf_delete, cur.buf, { force = true })
  end

  Terminal.reg[name] = nil
  local herd = require("herd")
  if herd.target == name then
    herd.target = nil
  end
end

local function start_watch(Terminal, name, pane_id)
  stop_watch(name)
  local state = { gen = 0 }
  watchers[name] = state

  local function arm()
    if watchers[name] ~= state then
      return
    end
    local gen = state.gen
    state.handle = Watch.spawn(
      { "herdr", "agent", "wait", pane_id, "--until", "unknown", "--timeout", "600000" },
      function(stdout, stderr, code)
        vim.schedule(function()
          if watchers[name] ~= state or gen ~= state.gen then
            return
          end
          local out = (stdout or "") .. (stderr or "")
          if out:find("agent_not_running", 1, true) or out:find("agent_not_found", 1, true) then
            close_agent(Terminal, name)
          elseif code == 0 or out:find("timeout", 1, true) then
            arm()
          else
            state.handle = nil
          end
        end)
      end
    )
  end
  arm()
end

--- Sidekick-style window nav from terminal insert mode (no Ctrl-\\ Ctrl-n first).
local function setup_nav(buf)
  ---@param dir "h"|"j"|"k"|"l"
  local function nav(dir)
    return function()
      if vim.fn.winnr() == vim.fn.winnr(dir) then
        return ("<C-%s>"):format(dir)
      end
      vim.schedule(function()
        vim.cmd.wincmd(dir)
      end)
    end
  end

  for _, dir in ipairs({ "h", "j", "k", "l" }) do
    vim.keymap.set("t", "<C-" .. dir .. ">", nav(dir), {
      buffer = buf,
      expr = true,
      desc = "herd: navigate " .. dir,
    })
    vim.keymap.set("n", "<C-" .. dir .. ">", function()
      if vim.fn.winnr() ~= vim.fn.winnr(dir) then
        vim.cmd.wincmd(dir)
      end
    end, { buffer = buf, desc = "herd: navigate " .. dir })
  end
end

---@param opts? { width?: number }
function M.apply(opts)
  opts = opts or {}
  local split_width = opts.width or 80

  local Terminal = require("herd.terminal")

  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("herd_split_nav", { clear = true }),
    callback = function(ev)
      for _, e in pairs(Terminal.reg) do
        if e.buf == ev.buf then
          setup_nav(ev.buf)
          break
        end
      end
    end,
  })

  local function open_split(buf)
    local win = vim.api.nvim_open_win(buf, true, {
      split = "right",
      win = -1,
      width = split_width,
      style = "minimal",
    })
    vim.wo[win].winfixwidth = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].statuscolumn = ""
    vim.wo[win].wrap = false
    style_panel(win, buf)
    return win
  end

  function Terminal.open(name, open_opts)
    open_opts = open_opts or {}
    local pane = open_opts.pane or name
    local entry = Terminal.reg[name]
    if entry and vim.api.nvim_buf_is_valid(entry.buf) then
      entry.pane = open_opts.pane or entry.pane or pane
      start_watch(Terminal, name, entry.pane)
      if entry.win and vim.api.nvim_win_is_valid(entry.win) then
        style_panel(entry.win, entry.buf)
        vim.api.nvim_set_current_win(entry.win)
      else
        entry.win = open_split(entry.buf)
      end
      vim.cmd.startinsert()
      return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    Terminal.reg[name] = { buf = buf, pane = pane }
    local win = open_split(buf)
    Terminal.reg[name].win = win

    start_watch(Terminal, name, pane)
    Terminal.spawn_term(Herdr.attach_argv(pane), function()
      close_agent(Terminal, name)
    end)
    vim.cmd.startinsert()
  end
end

return M

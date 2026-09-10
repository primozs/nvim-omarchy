--- Poll herdr for agent status changes; toast in every nvim instance.
--- Cross-repo: all agents are watched. Skip toast in the nvim that has that agent open.
--- Ping only if THIS nvim last got FocusGained (OS/tmux focus). Hosting nvim never pings.
--- Only "done" / "blocked" (not "idle") so chat turns do not spam.
local M = {}

local last ---@type table<string, string>
local timer ---@type uv.uv_timer_t?
local running = false
local focus_group ---@type integer?

local function focus_file()
  return vim.fn.stdpath("cache") .. "/herd-notify-focused"
end

local function claim_focus()
  vim.fn.writefile({ tostring(vim.fn.getpid()) }, focus_file())
end

local function release_focus()
  local path = focus_file()
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok and lines[1] and tonumber(lines[1]) == vim.fn.getpid() then
    vim.fn.writefile({ "" }, path)
  end
end

local function focused_pid()
  local ok, lines = pcall(vim.fn.readfile, focus_file())
  local pid = ok and lines[1] and tonumber(lines[1])
  if pid and vim.uv.fs_stat("/proc/" .. pid) then
    return pid
  end
  return nil
end

--- True when the OS-active window looks like a terminal (nvim likely lives there).
local function active_window_is_terminal()
  if vim.fn.executable("xdotool") ~= 1 then
    return false
  end
  local active = vim.trim(vim.fn.system({ "xdotool", "getactivewindow" }))
  if active == "" or vim.v.shell_error ~= 0 then
    return false
  end
  local name = vim.trim(vim.fn.system({ "xdotool", "getwindowname", active })):lower()
  local class = ""
  if vim.fn.executable("xprop") == 1 then
    local props = vim.fn.system({ "xprop", "-id", active, "WM_CLASS" })
    class = (props or ""):lower()
  end
  local blob = class .. " " .. name
  for _, needle in ipairs({
    "terminal",
    "tilix",
    "alacritty",
    "kitty",
    "wezterm",
    "xterm",
    "urxvt",
    "foot",
    "ghostty",
    "tmux",
  }) do
    if blob:find(needle, 1, true) then
      return true
    end
  end
  return false
end

--- True when this nvim has the agent's herd panel attached (you already see it).
local function agent_hosted_here(agent)
  local ok, Terminal = pcall(require, "herd.terminal")
  if not ok then
    return false
  end
  local entry = Terminal.reg[agent.name]
  if entry and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
    return true
  end
  for _, e in pairs(Terminal.reg) do
    if e.pane == agent.pane_id and e.buf and vim.api.nvim_buf_is_valid(e.buf) then
      return true
    end
  end
  return false
end

local function presence_dir()
  return vim.fn.stdpath("cache") .. "/herd-notify-presence"
end

local function publish_hosted()
  vim.fn.mkdir(presence_dir(), "p")
  local rows = {}
  local ok, Terminal = pcall(require, "herd.terminal")
  if ok then
    for name, e in pairs(Terminal.reg) do
      if e.buf and vim.api.nvim_buf_is_valid(e.buf) then
        rows[#rows + 1] = { name = name, pane = e.pane }
      end
    end
  end
  vim.fn.writefile(
    { vim.json.encode({ pid = vim.fn.getpid(), hosted = rows }) },
    presence_dir() .. "/" .. vim.fn.getpid() .. ".json"
  )
end

local function clear_presence()
  pcall(vim.fn.delete, presence_dir() .. "/" .. vim.fn.getpid() .. ".json")
end

--- Focused nvim hosts this agent → nobody should ping (you're already looking at it).
local function focused_nvim_hosts(agent)
  local fpid = focused_pid()
  if not fpid then
    return false
  end
  if fpid == vim.fn.getpid() then
    return agent_hosted_here(agent)
  end
  local path = presence_dir() .. "/" .. fpid .. ".json"
  if not vim.uv.fs_stat(path) then
    return false
  end
  local dec_ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if not dec_ok or type(data) ~= "table" then
    return false
  end
  for _, e in ipairs(data.hosted or {}) do
    if e.name == agent.name or (e.pane and e.pane == agent.pane_id) then
      return true
    end
  end
  return false
end

--- Ping when: a focused non-host should ring, OR you're outside all terminals
--- (e.g. Cursor). If focus is unknown but a terminal is active, stay quiet —
--- that is usually case 2 with a missed FocusGained on the host.
local function should_ping(agent)
  if focused_nvim_hosts(agent) then
    return false
  end
  local fpid = focused_pid()
  if fpid then
    return fpid == vim.fn.getpid()
  end
  -- No nvim claimed focus: only ring when OS focus is outside terminals.
  return not active_window_is_terminal()
end

local function ping(urgent)
  if vim.fn.executable("canberra-gtk-play") ~= 1 then
    vim.api.nvim_out_write("\a")
    return
  end
  local icon = urgent and "dialog-warning" or "complete"
  local lock = vim.fn.stdpath("cache") .. "/herd-notify-ping.lock"
  if vim.fn.executable("flock") == 1 then
    vim.system({
      "flock",
      "-n",
      lock,
      "-c",
      string.format("canberra-gtk-play -i %s && sleep 5", icon),
    }, { detach = true })
  else
    vim.system({ "canberra-gtk-play", "-i", icon }, { detach = true })
  end
end

local function notify_agent(agent, message, level, with_ping, urgent)
  local title = string.format("herd · %s", agent.name)
  local body = string.format("%s — %s", vim.fn.fnamemodify(agent.cwd or "", ":t"), message)
  local ok_snacks, Snacks = pcall(require, "snacks")
  if ok_snacks and Snacks.notifier then
    Snacks.notifier.notify(body, level, { title = title })
  else
    vim.notify(body, level, { title = title })
  end

  if not with_ping then
    return
  end

  if should_ping(agent) then
    ping(urgent)
  end
end

local function handle_agents(agents)
  last = last or {}
  publish_hosted()

  local seen = {}
  for _, agent in ipairs(agents) do
    if agent.pane_id and agent.status then
      seen[agent.pane_id] = true
      local prev = last[agent.pane_id]
      local cur = agent.status
      if prev and prev ~= cur and not agent_hosted_here(agent) then
        if cur == "blocked" then
          notify_agent(agent, "blocked — needs your input", vim.log.levels.WARN, true, true)
        elseif prev == "working" and cur == "done" then
          notify_agent(agent, "finished", vim.log.levels.INFO, true, false)
        end
      end
      last[agent.pane_id] = cur
    end
  end

  for pane_id in pairs(last) do
    if not seen[pane_id] then
      last[pane_id] = nil
    end
  end
end

local function poll()
  if not running then
    return
  end

  if vim.fn.executable("herdr") ~= 1 then
    return M.schedule()
  end

  vim.system({ "herdr", "status", "server" }, { text = true }, function(status_res)
    if status_res.code ~= 0 or not (status_res.stdout or ""):find("status: running", 1, true) then
      vim.schedule(M.schedule)
      return
    end

    vim.system({ "herdr", "agent", "list" }, { text = true }, function(list_res)
      vim.schedule(function()
        if list_res.code ~= 0 then
          return M.schedule()
        end
        local ok, decoded = pcall(vim.json.decode, list_res.stdout or "")
        local raw = ok and decoded and decoded.result and decoded.result.agents or {}
        local agents = {}
        for _, a in ipairs(raw) do
          if a.name and a.pane_id then
            agents[#agents + 1] = {
              name = a.name,
              pane_id = a.pane_id,
              status = a.agent_status,
              cwd = a.cwd,
            }
          end
        end
        handle_agents(agents)
        M.schedule()
      end)
    end)
  end)
end

function M.schedule()
  if not running or not timer then
    return
  end
  timer:start(M.interval_ms, 0, function()
    poll()
  end)
end

local function setup_focus()
  if focus_group then
    return
  end
  focus_group = vim.api.nvim_create_augroup("herd_status_notify_focus", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = focus_group,
    callback = claim_focus,
  })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = focus_group,
    callback = release_focus,
  })
end

---@param opts? { interval_ms?: number }
function M.start(opts)
  opts = opts or {}
  if running then
    return
  end
  running = true
  M.interval_ms = opts.interval_ms or 2000
  last = {}
  setup_focus()
  publish_hosted()
  timer = vim.uv.new_timer()
  M.schedule()
end

function M.stop()
  running = false
  release_focus()
  clear_presence()
  if focus_group then
    pcall(vim.api.nvim_del_augroup_by_id, focus_group)
    focus_group = nil
  end
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  timer = nil
  last = nil
end

---@param opts? { urgent?: boolean }
function M.test(opts)
  opts = opts or {}
  local urgent = opts.urgent
  notify_agent({
    name = "test",
    cwd = vim.fn.getcwd(),
  }, urgent and "blocked — needs your input" or "finished", urgent and vim.log.levels.WARN or vim.log.levels.INFO, true, urgent)
end

---@param opts { name: string, pane_id: string, cwd?: string, from?: string, to?: string }
function M.simulate(opts)
  last = last or {}
  last[opts.pane_id] = opts.from or "working"
  handle_agents({
    {
      name = opts.name,
      pane_id = opts.pane_id,
      status = opts.to or "done",
      cwd = opts.cwd or "",
    },
  })
end

return M

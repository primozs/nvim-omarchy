--- Poll herdr for agent status changes.
--- Cross-repo: all agents are watched.
--- System toast only (Omarchy), auto-expires in a few seconds.
--- Also catches missed working pulses via state_change_seq gaps.
--- Sound from non-viewer nvim; stamp-file dedupes desktop across nvims.
local M = {}

local last ---@type table<string, { status: string, seq: integer }>
local timer ---@type uv.uv_timer_t?
local running = false
local focus_group ---@type integer?

local function focus_file()
  return vim.fn.stdpath("cache") .. "/herd-notify-focused"
end

local function debug_log(msg)
  local path = vim.fn.stdpath("cache") .. "/herd-notify-debug.log"
  vim.fn.writefile({ string.format("%s %s", os.date("%H:%M:%S"), msg) }, path, "a")
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

--- Resolve the herd terminal entry for an agent in this nvim (if any).
local function agent_entry(agent)
  local ok, Terminal = pcall(require, "herd.terminal")
  if not ok then
    return nil
  end
  local entry = Terminal.reg[agent.name]
  if entry and entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
    return entry
  end
  for _, e in pairs(Terminal.reg) do
    if e.pane == agent.pane_id and e.buf and vim.api.nvim_buf_is_valid(e.buf) then
      return e
    end
  end
  return nil
end

--- True when this nvim's current window is the agent's terminal buffer.
local function agent_viewing_here(agent)
  local entry = agent_entry(agent)
  if not entry then
    return false
  end
  return entry.buf == vim.api.nvim_get_current_buf()
end

local function presence_dir()
  return vim.fn.stdpath("cache") .. "/herd-notify-presence"
end

local function publish_hosted()
  vim.fn.mkdir(presence_dir(), "p")
  -- Drop presence files from dead nvim PIDs so focus/host checks stay accurate.
  for _, path in ipairs(vim.fn.glob(presence_dir() .. "/*.json", false, true)) do
    local pid = tonumber(vim.fn.fnamemodify(path, ":t:r"))
    if pid and not vim.uv.fs_stat("/proc/" .. pid) then
      pcall(vim.fn.delete, path)
    end
  end
  local rows = {}
  local viewing = nil
  local ok, Terminal = pcall(require, "herd.terminal")
  if ok then
    local cur = vim.api.nvim_get_current_buf()
    for name, e in pairs(Terminal.reg) do
      if e.buf and vim.api.nvim_buf_is_valid(e.buf) then
        rows[#rows + 1] = { name = name, pane = e.pane }
        if e.buf == cur then
          viewing = { name = name, pane = e.pane }
        end
      end
    end
  end
  vim.fn.writefile(
    { vim.json.encode({ pid = vim.fn.getpid(), hosted = rows, viewing = viewing }) },
    presence_dir() .. "/" .. vim.fn.getpid() .. ".json"
  )
end

local function clear_presence()
  pcall(vim.fn.delete, presence_dir() .. "/" .. vim.fn.getpid() .. ".json")
end

--- Focused nvim is looking at this agent's terminal → nobody should ping.
local function focused_nvim_viewing(agent)
  local fpid = focused_pid()
  if not fpid then
    return false
  end
  if fpid == vim.fn.getpid() then
    return agent_viewing_here(agent)
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
  local v = data.viewing
  if type(v) ~= "table" then
    return false
  end
  return v.name == agent.name or (v.pane and v.pane == agent.pane_id)
end

--- Ping / desktop when a focused non-viewer should ring. If no nvim has claimed
--- OS focus (common on Wayland), any instance may ring — flock dedupes.
local function should_ping(agent)
  if focused_nvim_viewing(agent) then
    return false
  end
  local fpid = focused_pid()
  if fpid then
    return fpid == vim.fn.getpid()
  end
  return true
end

local function ping(urgent)
  if vim.fn.executable("canberra-gtk-play") ~= 1 then
    vim.api.nvim_out_write("\a")
    return
  end
  local icon = urgent and "dialog-warning" or "complete"
  local lock = vim.fn.stdpath("cache") .. "/herd-notify-ping.lock"
  if vim.fn.executable("flock") == 1 then
    -- Hold lock briefly so multi-nvim polls don't stack sounds.
    vim.system({
      "flock",
      "-n",
      lock,
      "sh",
      "-c",
      string.format("canberra-gtk-play -i %s; sleep 2", icon),
    }, { detach = true })
  else
    vim.system({ "canberra-gtk-play", "-i", icon }, { detach = true })
  end
end

local function desktop_notify(title, body, urgent)
  -- Cross-nvim debounce via stamp file (flock alone was hard to verify).
  local stamp = vim.fn.stdpath("cache") .. "/herd-notify-desktop.stamp"
  local stat = vim.uv.fs_stat(stamp)
  local now = os.time()
  if stat and stat.mtime and (now - stat.mtime.sec) < 2 then
    debug_log("desktop debounce skip")
    return
  end
  vim.fn.writefile({ tostring(now) }, stamp)

  -- normal/low + short timeout so Omarchy/Quickshell auto-dismisses
  local urgency = urgent and "critical" or "normal"
  local timeout_ms = urgent and "7000" or "5000"
  ---@type string[]
  local argv
  if vim.fn.executable("omarchy-notification-send") == 1 then
    argv = {
      "omarchy-notification-send",
      "-u",
      urgency,
      "-t",
      timeout_ms,
      "--app-name",
      "herd",
      title,
      body,
    }
  elseif vim.fn.executable("notify-send") == 1 then
    argv = { "notify-send", "-a", "herd", "-u", urgency, "-t", timeout_ms, title, body }
  else
    debug_log("desktop: no notifier binary")
    return
  end

  debug_log("desktop spawn: " .. table.concat(argv, " "))
  vim.system(argv, { timeout = 5000 }, function(res)
    vim.schedule(function()
      debug_log(
        string.format(
          "desktop done code=%s signal=%s err=%s",
          tostring(res.code),
          tostring(res.signal),
          vim.trim(res.stderr or "")
        )
      )
    end)
  end)
end

local function notify_agent(agent, message, level, with_ping, urgent)
  local title = string.format("herd · %s", agent.name)
  local body = string.format("%s — %s", vim.fn.fnamemodify(agent.cwd or "", ":t"), message)
  local do_ping = with_ping and should_ping(agent)
  debug_log(
    string.format(
      "notify name=%s msg=%s with_ping=%s do_ping=%s",
      agent.name,
      message,
      tostring(with_ping),
      tostring(do_ping)
    )
  )

  -- System toast only (no Snacks / vim.notify); expires in a few seconds.
  desktop_notify(title, body, urgent)

  if do_ping then
    ping(urgent)
  end
end

---@param agents { name: string, pane_id: string, status: string, cwd?: string, seq?: integer }[]
local function handle_agents(agents)
  last = last or {}
  publish_hosted()

  local seen = {}
  for _, agent in ipairs(agents) do
    if agent.pane_id and agent.status then
      seen[agent.pane_id] = true
      local cur = agent.status
      local seq = agent.seq or 0
      local prev = last[agent.pane_id]

      if not prev then
        last[agent.pane_id] = { status = cur, seq = seq }
      elseif seq ~= prev.seq or cur ~= prev.status then
        local prev_status = prev.status
        local prev_seq = prev.seq
        last[agent.pane_id] = { status = cur, seq = seq }
        debug_log(
          string.format(
            "transition %s %s(seq=%s) -> %s(seq=%s)",
            agent.name,
            prev_status,
            tostring(prev_seq),
            cur,
            tostring(seq)
          )
        )

        if cur == "blocked" and prev_status ~= "blocked" then
          notify_agent(agent, "blocked — needs your input", vim.log.levels.WARN, true, true)
        elseif cur == "done" or cur == "idle" then
          if prev_status == "working" or prev_status == "unknown" then
            notify_agent(agent, "finished", vim.log.levels.INFO, true, false)
          elseif prev_status == cur and seq >= prev_seq + 2 then
            -- Missed intermediate status (usually working) between polls.
            notify_agent(agent, "finished", vim.log.levels.INFO, true, false)
          end
        end
      end
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
              seq = a.state_change_seq,
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
  M.interval_ms = opts.interval_ms or 500
  last = {}
  setup_focus()
  publish_hosted()
  timer = vim.uv.new_timer()
  M.schedule()
  debug_log("started interval_ms=" .. tostring(M.interval_ms))
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

---@param opts { name: string, pane_id: string, cwd?: string, from?: string, to?: string, from_seq?: integer, to_seq?: integer }
function M.simulate(opts)
  last = last or {}
  last[opts.pane_id] = {
    status = opts.from or "working",
    seq = opts.from_seq or 1,
  }
  handle_agents({
    {
      name = opts.name,
      pane_id = opts.pane_id,
      status = opts.to or "done",
      cwd = opts.cwd or "",
      seq = opts.to_seq or 2,
    },
  })
end

return M

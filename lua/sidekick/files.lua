--- Sidekick search → quickfix (99 line-format parser + auto-watch).
--- Future: range → extmark highlights; optional buffer wipe / bulk open.
local M = {}

M.SEARCH_OUTPUT_RULES = [[
<Output>
/path/to/project/src/foo.js:24:8,3,Some notes here about some stuff, it can contain commas
/path/to/project/src/foo.js:71:12,7,more notes, everything is great!
</Output>
<Rule>Text locations are in the format of: path/to/file.ext:lnum:cnum,X,NOTES
lnum = starting line number 1-based
cnum = starting column number 1-based
X = how many lines should be highlighted
NOTES = A text description of why this location is relevant
</Rule>
<Rule>NOTES cannot have new lines</Rule>
<Rule>You must adhere to the output format</Rule>
<Rule>Each location is on its own line</Rule>
<Rule>Paths may be absolute or relative to the project root</Rule>
<Rule>Provide location lines without commentary before or after them</Rule>
<TaskDescription>
Search the project and return matching code locations in the format above.
</TaskDescription>]]

local POLL_MS = 500
local IDLE_MS = 1500
local TIMEOUT_MS = 5 * 60 * 1000
local WATCH_ARM_SLACK_MS = 500

---@type fun(opts: table)?
local send_fn = nil
---@type fun(opts: table): number?
local submit_delay_fn = nil

---@class sidekick.files.Watcher
---@field timer uv.uv_timer_t?
---@field buf integer?
---@field marker_line integer
---@field last_count integer
---@field last_change integer
---@field started integer
---@field title string
---@field cwd string
---@field jump_win integer?

local watcher = {
  marker_line = 0,
  last_count = 0,
  last_change = 0,
  started = 0,
  title = "Sidekick Search",
  cwd = ".",
} ---@type sidekick.files.Watcher

---@param win integer?
---@return boolean
local function is_jump_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local bt = vim.bo[buf].buftype
  if bt == "terminal" or bt == "prompt" or bt == "nofile" then
    return false
  end
  local ft = vim.bo[buf].filetype
  if ft == "qf" or ft == "help" or ft == "sidekick_terminal" then
    return false
  end
  return true
end

---@param preferred integer?
---@return integer?
local function pick_jump_win(preferred)
  if is_jump_win(preferred) then
    return preferred
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_jump_win(win) then
      return win
    end
  end
  return nil
end

---@param opts { send: fun(opts: table), submit_delay?: fun(opts: table): number }
function M.setup(opts)
  send_fn = opts.send
  submit_delay_fn = opts.submit_delay
end

---@param line string
---@return string
local function clean_line(line)
  line = vim.trim(line)
  line = line:gsub("%s+$", "")
  line = line:gsub("^[%s%-%*%d%.%)]+", "")
  line = line:gsub("^[`']+", ""):gsub("[`']+$", "")
  return line
end

---@param line string
---@return boolean
local function skip_line(line)
  return line == ""
    or line:find("/path/to/project", 1, true) ~= nil
    or line:find("^<", 1, false) ~= nil
    or line:find("^</", 1, false) ~= nil
end

---@param filepath string
---@param lnum integer
---@param col integer
---@param text string
---@return table
local function make_entry(filepath, lnum, col, text)
  return {
    filename = filepath,
    lnum = lnum,
    col = col,
    text = text or "",
  }
end

---@param line string
---@return table|nil
function M.parse_line(line)
  line = clean_line(line)
  if skip_line(line) then
    return nil
  end

  -- Full 99: path:lnum:col,range,notes
  local filepath, lnum_raw, rest = line:match("^(.-):([^:]+):(.+)$")
  if filepath and lnum_raw and rest then
    local col_raw, _, notes = rest:match("^([^,]+),([^,]+),?(.*)$")
    if col_raw then
      return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(col_raw) or 1, notes)
    end
    -- path:lnum:col (no range/notes)
    local col_only = rest:match("^(%d+)$")
    if col_only then
      return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(col_only) or 1, "")
    end
  end

  -- path:lnum with optional notes after comma
  filepath, lnum_raw, rest = line:match("^(.-):(%d+),?(.*)$")
  if filepath and lnum_raw and filepath:find("/", 1, true) then
    return make_entry(filepath, tonumber(lnum_raw) or 1, 1, rest or "")
  end

  -- Sidekick @path :L42:C7 or @path:42:7
  filepath, lnum_raw, rest = line:match("^@(.-)%s*:L(%d+):C(%d+)$")
  if filepath and lnum_raw and rest then
    return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(rest) or 1, "")
  end
  filepath, lnum_raw, rest = line:match("^@(.-):(%d+):(%d+)$")
  if filepath and lnum_raw and rest then
    return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(rest) or 1, "")
  end

  -- Bare path (must look like a file path)
  if line:match("^[%w%._%-/]+%.[%w]+$") or line:match("^/[%w%._%-/]+$") then
    return make_entry(line, 1, 1, "")
  end

  return nil
end

---@param text string
---@return table[]
function M.create_qfix_entries(text)
  local qf_list = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local res = M.parse_line(line)
    if res then
      qf_list[#qf_list + 1] = res
    end
  end
  return qf_list
end

---@param text string
---@return string
function M.strip_ansi(text)
  return (text:gsub("\27%[[0-9;]*[A-Za-z]", ""):gsub("\27%].*?\07", ""))
end

---@param items table[]
---@param cwd string
---@return table[]
function M.normalize_paths(items, cwd)
  local ret = {}
  for _, item in ipairs(items) do
    local path = vim.trim(item.filename)
    path = path:gsub("^[`']+", ""):gsub("[`']+$", "")
    if path:sub(1, 2) == "./" then
      path = path:sub(3)
    end
    if path:sub(1, 1) ~= "/" then
      path = vim.fs.joinpath(cwd, path)
    end
    ret[#ret + 1] = vim.tbl_extend("force", item, {
      filename = path,
      valid = true,
    })
  end
  return ret
end

-- Backwards-compatible alias
M.resolve_paths = M.normalize_paths

---@param items table[]
---@param title string
function M.apply_quickfix(items, title)
  if #items == 0 then
    return false
  end
  local win = pick_jump_win(watcher.jump_win)
  if win then
    vim.api.nvim_set_current_win(win)
  end
  vim.fn.setqflist({}, "r", { title = title, items = items })
  vim.cmd("botright copen")
  vim.notify(string.format("Sidekick search: %d location(s)", #items), vim.log.levels.INFO)
  return true
end

function M.stop_watch()
  local timer = watcher.timer
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  watcher.timer = nil
  watcher.buf = nil
end

---@param buf integer
---@param from_line integer
---@return string
local function terminal_text_from(buf, from_line)
  if not vim.api.nvim_buf_is_valid(buf) then
    return ""
  end
  local raw = vim.api.nvim_buf_get_lines(buf, from_line, -1, false)
  local lines = vim.tbl_map(function(l)
    return vim.trim(l):gsub("%s+$", "")
  end, raw)
  return M.strip_ansi(table.concat(lines, "\n"))
end

function M._poll()
  local buf = watcher.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    M.stop_watch()
    return
  end

  local now = vim.uv.now()
  if now - watcher.started > TIMEOUT_MS then
    M.stop_watch()
    vim.notify("Sidekick search: timed out waiting for results", vim.log.levels.WARN)
    return
  end

  local line_count = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if line_count ~= watcher.last_count then
    watcher.last_count = line_count
    watcher.last_change = now
    return
  end

  if now - watcher.last_change < IDLE_MS then
    return
  end

  local text = terminal_text_from(buf, watcher.marker_line)
  local entries = M.normalize_paths(M.create_qfix_entries(text), watcher.cwd)

  if #entries == 0 then
    return
  end

  M.stop_watch()
  M.apply_quickfix(entries, watcher.title)
end

---@param title string
function M.start_watch(title)
  M.stop_watch()

  watcher.title = title
  watcher.started = vim.uv.now()
  watcher.last_change = watcher.started
  watcher.marker_line = 0
  watcher.last_count = 0
  watcher.cwd = vim.fn.getcwd()

  local attached = require("sidekick.cli.state").get({ attached = true })
  local state = attached[1]
  local term = state and state.terminal
  if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
    watcher.buf = term.buf
    watcher.marker_line = #vim.api.nvim_buf_get_lines(term.buf, 0, -1, false)
    watcher.last_count = watcher.marker_line
    local session_cwd = state.session and state.session.cwd
    if session_cwd and session_cwd ~= "" then
      watcher.cwd = session_cwd
    end
  end

  if not watcher.buf then
    vim.notify("Sidekick search: no active terminal to watch", vim.log.levels.ERROR)
    return
  end

  local timer = assert(vim.uv.new_timer())
  watcher.timer = timer
  timer:start(POLL_MS, POLL_MS, function()
    vim.schedule(M._poll)
  end)
end

---@param opts table
---@return number
local function watch_arm_delay(opts)
  local delay = submit_delay_fn and submit_delay_fn(opts) or 400
  return delay + WATCH_ARM_SLACK_MS
end

---@param question string
---@return string
function M.format_search_msg(question)
  return M.SEARCH_OUTPUT_RULES .. "\n\n<Prompt>\n" .. question .. "\n</Prompt>"
end

---@param opts table
---@param title string
---@param jump_win integer?
local function send_search(opts, title, jump_win)
  if not send_fn then
    vim.notify("Sidekick search: not configured (missing send_fn)", vim.log.levels.ERROR)
    return
  end
  watcher.jump_win = jump_win or vim.api.nvim_get_current_win()
  send_fn(opts)
  vim.defer_fn(function()
    M.start_watch(title)
  end, watch_arm_delay(opts))
end

function M.search_general()
  local jump_win = vim.api.nvim_get_current_win()
  vim.ui.input({ prompt = "Search: " }, function(input)
    if not input or input == "" then
      return
    end
    send_search({ msg = M.format_search_msg(input) }, "Sidekick Search", jump_win)
  end)
end

function M.search_here()
  send_search({ prompt = "search_here" }, "Sidekick Search Here")
end

--- Manual fallback: parse current terminal scrollback.
function M.collect_results()
  local text = ""
  local cwd = vim.fn.getcwd()
  local title = "Sidekick Search"

  local attached = require("sidekick.cli.state").get({ attached = true })
  local state = attached[1]
  if state then
    local term = state.terminal
    if term then
      local session_cwd = state.session and state.session.cwd
      if session_cwd and session_cwd ~= "" then
        cwd = session_cwd
      end
      local buf = term.buf
      local scrollback = term.scrollback
      if scrollback and scrollback.is_open and scrollback:is_open() and scrollback.buf then
        buf = scrollback.buf
        title = title .. " (scrollback)"
      end
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local lines = vim.tbl_map(function(l)
          return vim.trim(l):gsub("%s+$", "")
        end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        text = M.strip_ansi(table.concat(lines, "\n"))
      end
    end
  end

  if text == "" then
    vim.notify("Sidekick search: no terminal output to parse", vim.log.levels.WARN)
    return
  end

  local entries = M.normalize_paths(M.create_qfix_entries(text), cwd)
  if #entries == 0 then
    vim.notify("Sidekick search: no locations found", vim.log.levels.INFO)
    return
  end
  M.apply_quickfix(entries, title)
end

return M

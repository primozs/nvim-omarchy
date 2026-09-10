--- Pi semantic project search → quickfix (standalone, uses pi.run + temp file).
local M = {}

M.SEARCH_PROMPT = [[
You are running inside the pi.nvim Neovim plugin. The user is asking for semantic project search results, not a conversational answer. Search the project from the current working directory and write results to the provided temp file.

INSTRUCTIONS:
1. Inspect files as needed to find locations relevant to the user's query.
2. Do not modify project files.
3. Write only quickfix result lines to the temp file.
4. Every non-empty line in the temp file must match exactly:
   path/to/file.ext:lnum:cnum,line_count,notes
5. lnum and cnum are 1-based. line_count is how many lines the result spans.
6. notes must be one line and should explain why the location matters.
7. Do not write markdown fences, bullets, headings, JSON, or conversational text.
8. If there are no matches, write an empty temp file.
9. After writing the temp file once, you are done.]]

local BUFFER_NOTE =
  "NOTE: Current file context may include unsaved buffer changes newer than the on-disk file."

---@type integer?
local jump_win = nil

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
  if ft == "qf" or ft == "help" then
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
    or line:find("/path/to/", 1, true) ~= nil
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
    valid = true,
  }
end

---@param line string
---@return table|nil
function M.parse_line(line)
  line = clean_line(line)
  if skip_line(line) then
    return nil
  end

  local filepath, lnum_raw, rest = line:match("^(.*):(%d+):(.+)$")
  if not filepath or not lnum_raw or not rest then
    return nil
  end

  local col_raw, _, notes = rest:match("^(%d+),(%d+),?(.*)$")
  if col_raw then
    return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(col_raw) or 1, notes)
  end

  local col_only = rest:match("^(%d+)$")
  if col_only then
    return make_entry(filepath, tonumber(lnum_raw) or 1, tonumber(col_only) or 1, "")
  end

  return nil
end

---@param text string
---@return table[]
function M.create_qfix_entries(text)
  local items = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local item = M.parse_line(line)
    if item then
      items[#items + 1] = item
    end
  end
  return items
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
    ret[#ret + 1] = vim.tbl_extend("force", item, { filename = path, valid = true })
  end
  return ret
end

---@param items table[]
---@param title string
---@return boolean
function M.apply_quickfix(items, title)
  if #items == 0 then
    vim.notify("Pi search: no results found", vim.log.levels.INFO)
    return false
  end
  local win = pick_jump_win(jump_win)
  if win then
    vim.api.nvim_set_current_win(win)
  end
  vim.fn.setqflist({}, "r", { title = title, items = items })
  vim.cmd("botright copen")
  vim.notify(string.format("Pi search: %d location(s)", #items), vim.log.levels.INFO)
  return true
end

---@param temp_file string
---@return string
function M.build_search_context(temp_file)
  local cfg = require("pi.config").get()
  local parts = {
    M.SEARCH_PROMPT,
    string.format("Cwd: %s", vim.fn.getcwd()),
    string.format("Temp file: %s", temp_file),
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local ctx = require("pi.context")
  if ctx.buffer_is_file_backed(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local surrounding = cfg.context.ask.surrounding_lines
    local start_line = math.max(1, cursor_line - surrounding)
    local end_line = math.min(#lines, cursor_line + surrounding)
    local nearby = vim.list_slice(lines, start_line, end_line)
    local content = table.concat(nearby, "\n")
    if #content > cfg.context.max_bytes then
      content = content:sub(1, cfg.context.max_bytes)
      parts[#parts + 1] = string.format("NOTE: Context trimmed (max_bytes=%d).", cfg.context.max_bytes)
    end

    parts[#parts + 1] = string.format("Current file: %s", vim.api.nvim_buf_get_name(bufnr))
    parts[#parts + 1] = BUFFER_NOTE
    parts[#parts + 1] = string.format(
      "Current file nearby context (%d-%d):\n```\n%s\n```",
      start_line,
      end_line,
      content
    )
  end

  return table.concat(parts, "\n\n")
end

---@param path string
---@return string|nil
local function read_temp_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

---@param path string|nil
local function cleanup_temp_file(path)
  if path and path ~= "" then
    pcall(vim.fn.delete, path)
  end
end

---@param opts? { query?: string, temp_file?: string, on_results?: fun(items: table[]), jump_win?: integer }
function M.search(opts)
  opts = opts or {}

  local function run(query)
    if not query or query == "" then
      return
    end

    jump_win = opts.jump_win or vim.api.nvim_get_current_win()

    local temp_file = opts.temp_file or vim.fn.tempname()
    local temp_dir = vim.fn.fnamemodify(temp_file, ":h")
    if temp_dir ~= "" then
      vim.fn.mkdir(temp_dir, "p")
    end
    vim.fn.writefile({}, temp_file)

    require("pi").run({
      message = query,
      skip_reload = true,
      build_context = function()
        return M.build_search_context(temp_file)
      end,
      on_done = function()
        local cwd = vim.fn.getcwd()
        local text = read_temp_file(temp_file) or ""
        cleanup_temp_file(temp_file)
        local items = M.normalize_paths(M.create_qfix_entries(text), cwd)
        M.apply_quickfix(items, "Pi Search")
        if opts.on_results then
          opts.on_results(items)
        end
      end,
    })
  end

  if opts.query then
    run(opts.query)
  else
    vim.ui.input({ prompt = "search pi: " }, function(input)
      run(input)
    end)
  end
end

return M

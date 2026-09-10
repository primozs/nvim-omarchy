local ASK_SURROUNDING = 80
local SELECTION_SURROUNDING = 40
local MAX_BYTES = 24000

local SOURCE_OF_TRUTH_NOTE =
  "NOTE: Context from the Neovim buffer; may include unsaved changes newer than the on-disk file."

local function truncate_to_bytes(text, max_bytes)
  if #text <= max_bytes then
    return text, false
  end
  return text:sub(1, max_bytes) .. "\n... (truncated)", true
end

--- Return a slice of `lines` centered on `center_line`, plus its 1-indexed bounds.
--- `surrounding` is the number of lines to include on each side of the center.
local function slice_lines_around(lines, center_line, surrounding)
  local start_line = math.max(1, center_line - surrounding)
  local end_line = math.min(#lines, center_line + surrounding)
  return vim.list_slice(lines, start_line, end_line), start_line, end_line
end

local function filetype_for(buf)
  return vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
end

local function build_buffer_context(ctx, surrounding)
  local buf = ctx.buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nearby, start_line, end_line = slice_lines_around(lines, ctx.row, surrounding)
  local filename = vim.api.nvim_buf_get_name(buf)

  local parts = {
    string.format("File: %s", filename ~= "" and filename or "[No Name]"),
    string.format("Cwd: %s", ctx.cwd),
    string.format("Filetype: %s", filetype_for(buf)),
    string.format("Current line: %d", ctx.row),
    SOURCE_OF_TRUTH_NOTE,
    string.format("Nearby context (%d-%d):", start_line, end_line),
    table.concat(nearby, "\n"),
  }

  local text, trimmed = truncate_to_bytes(table.concat(parts, "\n\n"), MAX_BYTES)
  if trimmed then
    text = text .. string.format("\n\nNOTE: Context trimmed (max_bytes=%d).", MAX_BYTES)
  end
  return vim.split(text, "\n", { plain = true })
end

local function build_buffer_selection_context(ctx)
  local buf = ctx.buf
  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  if from[1] == 0 or to[1] == 0 then
    return false
  end

  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end

  local start_line, end_line = from[1], to[1]
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = math.max(1, start_line - SELECTION_SURROUNDING)
  local after = math.min(#all_lines, end_line + SELECTION_SURROUNDING)

  local selected = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
  local nearby = vim.api.nvim_buf_get_lines(buf, before - 1, after, false)
  local filename = vim.api.nvim_buf_get_name(buf)

  local parts = {
    string.format("File: %s", filename ~= "" and filename or "[No Name]"),
    string.format("Cwd: %s", ctx.cwd),
    string.format("Filetype: %s", filetype_for(buf)),
    string.format("Selected lines: %d-%d", start_line, end_line),
    SOURCE_OF_TRUTH_NOTE,
    "Selected content:",
    table.concat(selected, "\n"),
    string.format("Nearby context (%d-%d):", before, after),
    table.concat(nearby, "\n"),
  }

  local text, trimmed = truncate_to_bytes(table.concat(parts, "\n\n"), MAX_BYTES)
  if trimmed then
    text = text .. string.format("\n\nNOTE: Context trimmed (max_bytes=%d).", MAX_BYTES)
  end
  return vim.split(text, "\n", { plain = true })
end

local SUBMIT_DELAY_BASE = 250
local SUBMIT_DELAY_LARGE = 400
local SUBMIT_RETRY_MS = 200
local SUBMIT_MAX_ATTEMPTS = 5

local SEARCH_OUTPUT_RULES = require("sidekick.files").SEARCH_OUTPUT_RULES

local function submit_delay(opts)
  local msg = opts.msg or ""
  if
    msg:find("{buffer")
    or opts.prompt == "explain"
    or opts.prompt == "fix"
    or opts.prompt == "diagnostics"
    or opts.prompt == "search_here"
    or msg:find("<TaskDescription>", 1, true)
  then
    return SUBMIT_DELAY_LARGE
  end
  return SUBMIT_DELAY_BASE
end

--- Try to submit the pending prompt; retry until Sidekick is attached.
---@param attempt integer
local function try_submit(attempt)
  local submitted = false
  require("sidekick.cli.state").with(function(state)
    local term = state.terminal
    if term and term.job and term:is_running() then
      vim.api.nvim_chan_send(term.job, "\r")
      submitted = true
    elseif state.session and state.session.submit then
      state.session:submit()
      submitted = true
    end
  end, { attach = false })

  if not submitted and attempt < SUBMIT_MAX_ATTEMPTS then
    vim.defer_fn(function()
      try_submit(attempt + 1)
    end, SUBMIT_RETRY_MS)
  end
end

--- Send a message to Sidekick, then auto-submit after a short delay.
--- Submission is deferred so buffer context has time to attach before Enter is sent.
local function send_and_submit(opts)
  require("sidekick.cli").send(vim.tbl_extend("force", opts, { submit = false }))

  vim.defer_fn(function()
    try_submit(1)
  end, submit_delay(opts))
end

local function prompt_label(buf, selection)
  local parts = {}
  local filename = vim.api.nvim_buf_get_name(buf)
  if filename ~= "" then
    parts[#parts + 1] = vim.fn.fnamemodify(filename, ":t")
  end
  if selection then
    parts[#parts + 1] = string.format("%d:%d", selection.start, selection["end"])
  end
  if #parts == 0 then
    return "Ask: "
  end
  return string.format("Ask (%s): ", table.concat(parts, ":"))
end

local function ask_buffer()
  local buf = vim.api.nvim_get_current_buf()
  vim.ui.input({ prompt = prompt_label(buf) }, function(input)
    if not input or input == "" then
      return
    end
    send_and_submit({
      msg = input .. "\n\n{buffer}",
    })
  end)
end

local function ask_selection()
  local buf = vim.api.nvim_get_current_buf()
  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  local selection = from[1] > 0
      and to[1] > 0
      and {
        start = math.min(from[1], to[1]),
        ["end"] = math.max(from[1], to[1]),
      }
    or nil

  vim.ui.input({ prompt = prompt_label(buf, selection) }, function(input)
    if not input or input == "" then
      return
    end
    send_and_submit({
      msg = input .. "\n\n{buffer_selection|buffer}",
    })
  end)
end

local function send_prompt(name)
  send_and_submit({ prompt = name })
end

local function send_paste(opts)
  require("sidekick.cli").send(opts)
end

return {
  {
    "folke/sidekick.nvim",
    init = function()
      vim.g.sidekick_nes = false
    end,
    opts = function(_, opts)
      opts.nes = vim.tbl_extend("force", opts.nes or {}, {
        enabled = false,
      })

      opts.cli = opts.cli or {}
      opts.cli.context = vim.tbl_extend("force", opts.cli.context or {}, {
        buffer = function(ctx)
          return build_buffer_context(ctx, ASK_SURROUNDING)
        end,
        buffer_selection = function(ctx)
          return build_buffer_selection_context(ctx)
        end,
      })

      opts.cli.prompts = vim.tbl_extend("force", opts.cli.prompts or {}, {
        explain = "Explain the following:\n{buffer}",
        fix = "Fix the following:\n{buffer_selection|buffer}",
        search_here = SEARCH_OUTPUT_RULES
          .. "\n\n<Task>\nFind files in this project related to this location or selection:\n{this}\n</Task>",
      })

      opts.cli.tools = vim.tbl_extend("force", opts.cli.tools or {}, {
        ["pi-hub"] = {},
        pi = {
          is_proc = function(_, proc)
            local re = vim.regex("\\<pi\\>")
            return re:match_str(proc.cmd) ~= nil and proc.cmd:find("agent-hub", 1, true) == nil
          end,
        },
      })
    end,
    -- stylua: ignore
    keys = {
      { "<leader>aei", ask_buffer,     mode = "n", desc = "Ask AI (buffer)" },
      { "<leader>aei", ask_selection,  mode = "v", desc = "Ask AI (selection)" },
      { "<leader>aee", function() send_prompt("explain") end,     mode = { "n", "v" }, desc = "Explain code" },
      { "<leader>aeF", function() send_prompt("fix") end,         mode = { "n", "v" }, desc = "Fix code" },
      { "<leader>aer", function() send_prompt("review") end,     mode = "n",          desc = "Review file" },
      { "<leader>aeD", function() send_prompt("diagnostics") end, mode = "n",          desc = "Fix diagnostics" },
      { "<leader>aet", function() send_paste({ msg = "{this}" }) end,       mode = { "n", "x" }, desc = "Send This" },
      { "<leader>aef", function() send_paste({ msg = "{file}" }) end,       mode = "n",          desc = "Send File" },
      { "<leader>aev", function() send_paste({ msg = "{selection}" }) end, mode = "x",          desc = "Send Visual Selection" },
      { "<leader>aeS", function() require("sidekick.files").search_general() end, mode = "n",    desc = "AI Search" },
      { "<leader>aeH", function() require("sidekick.files").search_here() end,  mode = { "n", "v" }, desc = "AI Search Here" },
      { "<leader>aeo", function() require("sidekick.files").collect_results() end, mode = "n", desc = "AI Open Search Results" },
    },
    config = function(_, opts)
      require("sidekick.files").setup({
        send = send_and_submit,
        submit_delay = submit_delay,
      })
      require("sidekick").setup(opts)
      require("sidekick.nes").disable()
      -- LazyVim's sidekick extra registers this toggle in its opts function.
      -- Pressing it calls nes.enable(true) and overwrites enabled = false.
      pcall(vim.keymap.del, "n", "<leader>uN")
    end,
  },
}

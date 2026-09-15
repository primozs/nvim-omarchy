-- Minimal plenary busted runner for this config.
-- Usage: nvim -l tests/run.lua [spec_glob]

local config = vim.fn.stdpath("config")
local plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"

package.path = table.concat({
  config .. "/lua/?.lua",
  config .. "/lua/?/init.lua",
  package.path,
}, ";")

vim.opt.runtimepath:prepend(config)
vim.opt.runtimepath:append(plenary)

if vim.fn.isdirectory(plenary) == 0 then
  io.stderr:write("plenary.nvim not found at " .. plenary .. "\n")
  os.exit(1)
end

local busted = require("plenary.busted")
local pattern = (arg and arg[1]) or (config .. "/tests/**/*_spec.lua")
local files = vim.fn.glob(pattern, false, true)
if #files == 0 then
  io.stderr:write("no specs matched: " .. pattern .. "\n")
  os.exit(1)
end

-- plenary.busted.run() exits via :cq; run one combined load so results aggregate.
for _, file in ipairs(files) do
  busted.run(file)
end

-- Swift lint via mise/system swiftlint (docker wrapper removed).
local lint = require("lint")

lint.linters_by_ft = vim.tbl_extend("force", lint.linters_by_ft or {}, {
  swift = { "swiftlint" },
})

lint.linters.swiftlint = {
  name = "swiftlint",
  cmd = "swiftlint",
  stdin = false,
  args = {
    "lint",
    "--config",
    ".swiftlint.yml",
    "--quiet",
  },
  stream = "stdout",
  ignore_exitcode = true,
  parser = require("lint.parser").from_pattern(
    "([^:]+):(%d+):(%d+): ([^:]+): (.*)",
    { "filename", "lnum", "col", "severity", "message" },
    {
      severity = {
        warning = vim.diagnostic.severity.WARN,
        error = vim.diagnostic.severity.ERROR,
      },
    }
  ),
}

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  pattern = { "*.swift" },
  callback = function()
    vim.defer_fn(function()
      lint.try_lint("swiftlint")
    end, 100)
  end,
})

vim.api.nvim_create_user_command("SwiftLint", function()
  lint.try_lint("swiftlint")
end, {})

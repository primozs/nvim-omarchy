local lint = require("lint")

lint.linters_by_ft = {
  swift = { "swiftlint" },
}

-- Configure swiftlint without --use-stdin
lint.linters.swiftlint = {
  name = "swiftlint",
  cmd = vim.fn.expand("~/bin/swiftlint-docker"),
  stdin = false, -- Changed from true to false
  args = {
    "lint",
    "--config",
    ".swiftlint.yml",
    "--quiet",
    -- "--force-exclude", -- Forces respect of excluded: paths
    -- "--path",
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

-- Auto-lint on save
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

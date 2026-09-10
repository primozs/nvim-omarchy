return {
  {
    "pablopunk/pi.nvim",
    cmd = { "PiAsk", "PiAskSelection", "PiCancel", "PiLog", "PiSearch" },
    -- stylua: ignore
    keys = {
      { "<leader>ai", ":PiAsk<CR>",          mode = "n", desc = "Pi: Ask (buffer)" },
      { "<leader>ai", ":PiAskSelection<CR>", mode = "v", desc = "Pi: Ask (selection)" },
      { "<leader>aeC", ":PiCancel<CR>",       mode = "n", desc = "Pi: Cancel" },
      { "<leader>aeL", ":PiLog<CR>",          mode = "n", desc = "Pi: Log" },
      { "<leader>aS", ":PiSearch<CR>",       mode = "n", desc = "Pi: Search → quickfix" },
    },
    opts = {
      provider = "opencode-go",
      model = "qwen3.7-plus",
      thinking = "off",
      context = {
        max_bytes = 24000,
        ask = { surrounding_lines = 80 },
        selection = { surrounding_lines = 40 },
      },
    },
    config = function(_, opts)
      require("pi").setup(opts)
      vim.api.nvim_create_user_command("PiSearch", function()
        require("pi.search").search()
      end, { desc = "Pi: semantic project search → quickfix" })
    end,
  },
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        -- ... other languages
        "swift",
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    },
  },
}

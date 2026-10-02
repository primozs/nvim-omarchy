-- Drop LazyVim/noice <c-f> Scroll Forward in every mode it binds.
return {
  {
    "folke/noice.nvim",
    keys = {
      { "<c-f>", false, mode = { "i", "n", "s" } },
    },
  },
}

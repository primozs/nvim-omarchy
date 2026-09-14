return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      mappings = {
        -- Override neo-tree's "Order by" prefix so o opens in Files (like LazyVim's O).
        ["o"] = {
          function(state)
            require("lazy.util").open(state.tree:get_node().path, { system = true })
          end,
          desc = "Open with System Application",
        },
      },
    },
  },
}

return {
  { "keith/swift.vim", ft = "swift" },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Arch/Omarchy: pacman swift-bin provides /usr/bin/sourcekit-lsp.
        -- Not available via mason; do not let mason try to install it.
        sourcekit = {
          mason = false,
          cmd = { "sourcekit-lsp" },
          filetypes = { "swift", "objc", "objcpp" },
          root_markers = { "Package.swift", ".git" },
        },
      },
    },
  },
}

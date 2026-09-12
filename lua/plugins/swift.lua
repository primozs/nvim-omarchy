return {
  { "keith/swift.vim", ft = "swift" },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Arch/Omarchy: pacman `swift-bin` ships /usr/bin/sourcekit-lsp (GUI PATH).
        -- Swiftly also provides it once libncurses.so.6 is shimmed for Arch.
        -- Not installable via mason.
        sourcekit = {
          mason = false,
          -- Keep C/C++ for clangd; sourcekit default also claims c/cpp.
          filetypes = { "swift", "objc", "objcpp" },
        },
      },
    },
  },
}

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        mojo = {
          -- You can add any mojo-lsp-server specific settings here
          -- For example, to include the current directory in the search path:
          -- cmd = { "mojo-lsp-server", "-I", "." }
        },
      },
    },
  },
}

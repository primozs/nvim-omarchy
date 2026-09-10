local lspconfig = require("lspconfig")
local util = require("lspconfig.util")

-- Get LazyVim's default on_attach and capabilities
local lazyvim_lsp = require("lazyvim.plugins.lsp")
local on_attach = lazyvim_lsp.on_attach
local capabilities = lazyvim_lsp.capabilities

-- If capabilities not found, fallback to cmp if available
if not capabilities then
  capabilities = vim.lsp.protocol.make_client_capabilities()
  local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  if has_cmp then
    capabilities = cmp_nvim_lsp.default_capabilities()
  end
end

-- Setup sourcekit-lsp
lspconfig.sourcekit.setup({
  cmd = { "sourcekit-lsp" },
  filetypes = { "swift", "objc", "objcpp" },
  root_dir = util.root_pattern("Package.swift", ".git"),
  on_attach = on_attach,
  capabilities = capabilities,
})

print("sourcekit-lsp configured")

-- mason setup
require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = { "ts_ls", "pyright",  "lua_ls" },
  automatic_installation = true,
})

-- native 0.11 configs (same as before, but cmd not needed for mason servers)
local caps = vim.lsp.protocol.make_client_capabilities()
pcall(function()
  local blink = require("blink.cmp")
  caps = blink.get_lsp_capabilities(caps)
end)

vim.lsp.config.ts_ls = {
  filetypes = { "javascript","javascriptreact","typescript","typescriptreact" },
  root_markers = { "package.json","tsconfig.json","jsconfig.json",".git" },
  capabilities = caps,
}
vim.lsp.config.pyright = {
  root_markers = { "pyproject.toml","requirements.txt",".git" },
  capabilities = caps,
}
vim.lsp.config.clangd = {
  root_markers = { "compile_commands.json","compile_flags.txt",".git" },
  capabilities = caps,
}
vim.lsp.config.csharp_ls = {
  root_markers = { "*.sln","*.csproj",".git" },
  capabilities = caps,
}
vim.lsp.config.lua_ls = {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
    },
  },
  capabilities = caps,
}

vim.lsp.enable({ "ts_ls","pyright","lua_ls" })


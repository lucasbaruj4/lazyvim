-- Mason
require("mason").setup()
require("mason-lspconfig").setup {

  ensure_installed = { "pyright", "ts_ls", "lua_ls" },
}

-- Capabilities (with blink.cmp)
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)

-- PYRIGHT
vim.lsp.config("pyright", {
  capabilities = capabilities,
})

-- TS / JS
vim.lsp.config("ts_ls", {
  capabilities = capabilities,
})


-- LUA
vim.lsp.config("lua_ls", {
  capabilities = capabilities,
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
    },
  },
})


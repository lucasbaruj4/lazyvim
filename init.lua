-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "help", "lspinfo", "vimdoc" },
  callback = function()
    vim.opt_local.wrap = true
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    local cfg = vim.api.nvim_win_get_config(0)
    if cfg.relative ~= "" then -- floating window
      vim.opt_local.wrap = true
    end
  end,
})

-- ~/.config/nvim/lua/config/options.lua
vim.lsp.inlay_hint.enable(true)

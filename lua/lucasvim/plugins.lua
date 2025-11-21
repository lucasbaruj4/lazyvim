-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)


require("lazy").setup({

  "williamboman/mason.nvim",
  "williamboman/mason-lspconfig.nvim",
  -- completion
  {
  "saghen/blink.cmp",

  version = "1.*",
  dependencies = { "rafamadriz/friendly-snippets" }, -- optional
  opts = {
    keymap = {
      preset = "default",

      -- move in the completion menu
      ["<Tab>"]   = { "select_next", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },

      -- accept completion
      ["<CR>"]    = { "accept", "fallback" },
    },


    sources = { default = { "lsp", "path", "buffer", "snippets" } },
    completion = { documentation = { auto_show = true } },
  },
  },
  {
	  "scottmckendry/cyberdream.nvim",
	  lazy = false,
	  priority = 1000,
  },
  {
	  "nvim-treesitter/nvim-treesitter",
	  build = ":TSUpdate",
  }, 
  {
	  "neovim/nvim-lspconfig",
  },
})

require("nvim-treesitter.configs").setup({
	ensure_installed = {
	"lua",
	"python",
	"typescript",
	"tsx",
	"javascript",},
	highlight = {enable = true},
})

-- setting up colorscheme
vim.cmd("colorscheme cyberdream")

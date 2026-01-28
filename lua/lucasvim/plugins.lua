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
  -- {
  --  "stevearc/oil.nvim",
  --  ---@module 'oil'
  --  opts = {
  --  view_options = { show_hidden = true },
  --  },
  --  skip_confirm_for_simple_edits = true,
  --  prompt_save_on_select_new_entry = false,
  --  dependencies = { { "nvim-mini/mini.icons", opts = {} } },
  --  lazy = false,
  -- },
  {
	  "akinsho/toggleterm.nvim",
	  version = "*",
	  opts = {
		  direction = 'float',
		  close_on_exit = 'true',
		  auto_scroll = true,
		  open_mapping = [[<leader>ft]],
		  insert_mappings = false,
		  autochdir = true,
		  start_in_insert = true,
		  shell = "powershell.exe",
	  },
  },
  {
	  "mikavilpas/yazi.nvim",
	  version = "*",
	  dependencies = {
		  {"nvim-lua/plenary.nvim", lazy = true },
	  },
	  opts = {
		  floating_window_scaling_factor = 0.8,
		  yazi_floating_window_border = 'rounded',
		  open_for_directories = true,
		  yazi_floating_window_winblend = 0,
	  },
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

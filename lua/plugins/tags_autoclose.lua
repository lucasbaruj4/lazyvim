return { {
  "windwp/nvim-ts-autotag",
  ft = {
    "javascriptreact",
    "typescriptreact",
    "html",
    "javascript",
    "typescript",
  },
  config = function()
    require("nvim-treesitter.configs").setup({
      autotag = {
        enable = true,
      }
    })
  end,
} }

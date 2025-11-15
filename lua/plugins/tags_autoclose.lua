return { {
  "windwp/nvim-ts-autotag",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "NvimTreesitterConfigDone",
      callback = function()
        require("nvim-tresitter.configs").setup({
          autotag = {
            enable = true,
          }
        })
      end
    })
  end,
}
}

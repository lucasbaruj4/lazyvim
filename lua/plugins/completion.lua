-- Configure blink.cmp to use Tab for accepting completions
return {
  {
    "saghen/blink.cmp",
    opts = {
      -- Configure keymap for blink.cmp
      keymap = {
        -- Tab to accept auto copmletion
        ["<Tab>"] = { "accept", "fallback" },
        -- Use shift tab for next suggestion
        ["<S-Tab>"] = { "select_next", "fallback" }
      },
    },
  },
}

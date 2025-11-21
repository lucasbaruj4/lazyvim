-- leader is space
vim.g.mapleader = " "

-- setting up the numbers
vim.o.number = true
vim.o.relativenumber = true
-- deleting the chars on the left
vim.opt.fillchars = { eob = " " }

-- yanks go to clipboard
vim.opt.clipboard = "unnamedplus"

-- deletes (d and D) do NOT go to clipboard
vim.keymap.set({ "n", "v" }, "d", '"_d')
vim.keymap.set({ "n", "v" }, "D", '"_D')
vim.keymap.set({ "n", "v" }, "c", '"_d')

-- disable the command-line window (q:)
vim.keymap.set("n", "q:", "<Nop>", { silent = true })
vim.keymap.set("n", "q/", "<Nop>", { silent = true })
vim.keymap.set("n", "q?", "<Nop>", { silent = true })
vim.keymap.set("c", "<C-f>", "<Nop>", { silent = true })

-- Show all diagnostics for the current line in a floating window
vim.keymap.set("n", "<leader>cd", function()
  vim.diagnostic.open_float(0, { scope = "line" })
end, { desc = "Line diagnostics" })


-- setting up the numbers
vim.o.number = true
vim.o.relativenumber = true
-- deleting the chars on the left
vim.opt.fillchars = { eob = " " }
-- setting up word wraping
vim.opt.wrap = true
vim.opt.linebreak = true

-- yanks go to clipboard
vim.opt.clipboard = "unnamedplus"

-- deletes (d and D) do NOT go to clipboard
vim.keymap.set({ "n", "v" }, "d", '"_d')
vim.keymap.set({ "n", "v" }, "D", '"_D')

-- disable the command-line window (q:)
vim.keymap.set("n", "q:", "<Nop>", { silent = true })
vim.keymap.set("n", "q/", "<Nop>", { silent = true })
vim.keymap.set("n", "q?", "<Nop>", { silent = true })
vim.keymap.set("c", "<C-f>", "<Nop>", { silent = true })


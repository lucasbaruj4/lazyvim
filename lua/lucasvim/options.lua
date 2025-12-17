-- leader is space
vim.g.mapleader = " "

-- making sure diagnostics have rounded borders
vim.o.winborder = "double"

-- setting up the numbers
vim.o.number = true
vim.o.relativenumber = true
-- deleting the chars on the left
vim.opt.fillchars = { eob = " " }


-- deactivating wrap
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true

-- background to be the same as hacker terminal
vim.opt.termguicolors = true
-- Here I activate this command after the colorscheme has been set to override the background color and status line to my current terminal background.
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    -- main editor background
    vim.api.nvim_set_hl(0, "Normal",      { bg = "NONE", fg = "NONE" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#0a0a0a", fg = "NONE" })


    -- statusline + winbar (the gray strip in your screenshot)
    vim.api.nvim_set_hl(0, "StatusLine",   { bg = "NONE", fg = "#ffffff" })
    vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "NONE", fg = "#777777" })

    vim.api.nvim_set_hl(0, "WinBar",       { bg = "#0a0a0a", fg = "#ffffff" })
    vim.api.nvim_set_hl(0, "WinBarNC",     { bg = "#0a0a0a", fg = "#777777" })
     vim.api.nvim_set_hl(0, "Pmenu",     { bg = "#0a0a0a", fg = "#ffffff" })
    vim.api.nvim_set_hl(0, "PmenuSel",  { bg = "#0a0a0a", fg = "#00ff66" })
    vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#0a0a0a" })
    vim.api.nvim_set_hl(0, "PmenuThumb",{ bg = "#1f1f1f" })
    vim.api.nvim_set_hl(0, "Visual", { bg = "#ffffff", fg = "#000000" })
    vim.api.nvim_set_hl(0, "SignColumn", {bg = "NONE", fg = "NONE"})
  end,})
-- yanks go to clipboard
vim.opt.clipboard = "unnamedplus"

-- save with leader w instead of ":w"
vim.keymap.set("n", "<leader>w", ":w<Enter>")

-- save if they were change and quit with leader q instead of ":x"
vim.keymap.set("n", "<leader>q", ":x<Enter>")

-- go to the last part of the current line with leader l instead of "$"
vim.keymap.set("n", "<leader>l", "$")

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


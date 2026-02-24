-- Personal neovim config
-- Managed by chezmoi - edit in dotfiles repo, then `chezmoi apply`

-- =============================================================================
-- Bootstrap lazy.nvim
-- =============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Error cloning lazy.nvim:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

-- =============================================================================
-- Core Settings (before plugins)
-- =============================================================================

-- Leader key (space is modern default)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = false

-- Indentation (2 spaces default, matching mjr's CodeMode)
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- UI
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Splits (open right and below)
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Persistence
vim.opt.undofile = true
vim.opt.swapfile = false

-- Clipboard (system clipboard integration)
vim.opt.clipboard = "unnamedplus"

-- Mouse
vim.opt.mouse = "a"

-- Faster updates
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Whitespace visualization
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- =============================================================================
-- Filetype Detection
-- =============================================================================

vim.filetype.add({
  pattern = {
    -- VSCode config files are always JSONC
    [".*/%.vscode/.*%.json"] = "jsonc",
    -- Content-based: any .json file containing C-style comments
    [".*%.json"] = {
      priority = -1,
      function(path, bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 50, false)
        for _, line in ipairs(lines) do
          if line:find("^%s*//") or line:find("/%*") then
            return "jsonc"
          end
        end
      end,
    },
  },
})

-- =============================================================================
-- Basic Keymaps (before plugins)
-- =============================================================================

local keymap = vim.keymap.set

-- Clear search highlight
keymap("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Window navigation: Ctrl+H/J/K/L handled by smart-splits.nvim
-- (see lua/plugins/navigation.lua for cross-pane WezTerm integration)

-- Buffer navigation: Ctrl+N/P (matching mjr's init.vim preference)
keymap("n", "<C-n>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap("n", "<C-p>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })

-- Quick save
keymap("n", "<leader>w", "<cmd>w<CR>", { desc = "Save" })

-- Better indenting (stay in visual mode)
keymap("v", "<", "<gv")
keymap("v", ">", ">gv")

-- Move lines up/down
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Keep cursor centered when scrolling
keymap("n", "<C-d>", "<C-d>zz")
keymap("n", "<C-u>", "<C-u>zz")

-- Yank whole file (matching mjr's yp)
keymap("n", "yp", ":%y+<CR>", { desc = "Yank entire file" })

-- =============================================================================
-- Plugin Specifications
-- =============================================================================

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "solarized", "habamax" } },
  checker = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
})

-- =============================================================================
-- Colorscheme (after plugins load)
-- =============================================================================

vim.cmd.colorscheme("solarized")

-- =============================================================================
-- JSONL Notify Logger (runs after snacks.notifier replaces vim.notify)
-- =============================================================================

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local log_path = vim.fn.stdpath("log") .. "/notify.jsonl"
    local visual_notify = vim.notify
    vim.notify = function(msg, level, opts)
      local file = io.open(log_path, "a")
      if file then
        local ok, entry = pcall(vim.json.encode, {
          t = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          l = level or 2,
          m = msg,
          s = opts and opts.title or nil,
        })
        if ok then file:write(entry .. "\n") end
        file:close()
      end
      return visual_notify(msg, level, opts)
    end
  end,
})

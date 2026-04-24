-- Treesitter: syntax highlighting and more
-- ts-install.nvim restores auto_install behavior removed from nvim-treesitter's main branch.
-- nvim-treesitter provides parser compilation infrastructure and query files.
return {
  -- Parser auto-installation (replaces manual install + FileType autocmd)
  {
    "lewis6991/ts-install.nvim",
    opts = {
      auto_install = true,
      ensure_install = {
        "bash", "c", "css", "scss", "diff", "dockerfile",
        "html", "javascript", "jsdoc", "json", "jsonc",
        "lua", "luadoc", "luap", "markdown", "markdown_inline",
        "printf", "python", "query", "regex", "rust",
        "toml", "tsx", "typescript", "vim", "vimdoc", "xml", "yaml",
      },
    },
  },

  -- Treesitter core (query files, parser compilation, incremental selection)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup({})

      -- Incremental selection (matching mjr's 's' for expand)
      vim.keymap.set("n", "s", function()
        require("nvim-treesitter.incremental_selection").init_selection()
      end, { desc = "Start incremental selection" })
      vim.keymap.set("x", "s", function()
        require("nvim-treesitter.incremental_selection").node_incremental()
      end, { desc = "Expand selection" })
      vim.keymap.set("x", "S", function()
        require("nvim-treesitter.incremental_selection").node_decremental()
      end, { desc = "Shrink selection" })
    end,
  },

  -- TODO: nvim-treesitter-textobjects needs API update for main branch
  -- Disabled until we verify the correct API
  -- {
  --   "nvim-treesitter/nvim-treesitter-textobjects",
  --   branch = "main",
  --   dependencies = { "nvim-treesitter/nvim-treesitter" },
  -- },
}

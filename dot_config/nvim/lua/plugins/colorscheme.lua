-- Catppuccin colorscheme (mocha flavor)
-- Matches the catppuccin mocha theme used in tmux for a consistent terminal palette.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = false,
      styles = {
        comments = { "italic" },
        keywords = { "bold" },
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        indent_blankline = { enabled = true },
        mason = true,
        flash = true,
        which_key = true,
        snacks = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")

      -- Gitsigns line number colors (catppuccin mocha accents)
      local hl = vim.api.nvim_set_hl
      hl(0, "GitSignsAddNr", { fg = "#a6e3a1" })    -- green
      hl(0, "GitSignsChangeNr", { fg = "#f9e2af" })  -- yellow
      hl(0, "GitSignsDeleteNr", { fg = "#f38ba8" })  -- red
    end,
  },
}

-- Solarized colorscheme (matching mjr's preference)
return {
  {
    "maxmx03/solarized.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = { enabled = false },
      styles = {
        comments = { italic = true },
        keywords = { bold = true },
      },
    },
    config = function(_, opts)
      require("solarized").setup(opts)
      vim.o.background = "dark"

      -- Git highlighting for gitsigns (solarized colors)
      local hl = vim.api.nvim_set_hl
      -- Gitsigns line number colors (when numhl enabled)
      hl(0, "GitSignsAddNr", { fg = "#859900" })
      hl(0, "GitSignsChangeNr", { fg = "#b58900" })
      hl(0, "GitSignsDeleteNr", { fg = "#dc322f" })
    end,
  },
}

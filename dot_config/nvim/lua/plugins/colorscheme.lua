-- Solarized colorscheme with slate background overrides
-- Keeps solarized's accent/syntax colors but replaces blue-tinted backgrounds
-- with the greyscale slate palette from the legacy VSCode customizations.
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
      on_colors = function(colors, color)
        return {
          base03 = "#232323",  -- Normal bg (was #002b36)
          base02 = "#282828",  -- CursorLine, emphasis (was #073642)
          base04 = "#1c1c1c",  -- NormalFloat bg (was #002731)
          -- base01 left at solarized default (#586e75) for readable comments
        }
      end,
      on_highlights = function(colors, color)
        return {
          NormalFloat = { bg = "#1c1c1c", fg = colors.base0 },
          WinSeparator = { fg = "#282828", bg = "#151515" },
        }
      end,
    },
    config = function(_, opts)
      require("solarized").setup(opts)
      vim.o.background = "dark"

      local hl = vim.api.nvim_set_hl
      -- Gitsigns line number colors (solarized accents)
      hl(0, "GitSignsAddNr", { fg = "#859900" })
      hl(0, "GitSignsChangeNr", { fg = "#b58900" })
      hl(0, "GitSignsDeleteNr", { fg = "#dc322f" })
    end,
  },
}

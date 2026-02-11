-- snacks.nvim: modular UI layer (replaces multiple standalone plugins)
-- See: cdocs/proposals/2026-02-11-snacks-nvim-adoption.md
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- Phase 1: Zero-config foundations
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      scope = { enabled = true },
      words = { enabled = true },
      statuscolumn = { enabled = true },
    },
  },
}

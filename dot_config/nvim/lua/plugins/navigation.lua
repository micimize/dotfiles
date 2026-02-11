-- Seamless navigation between Neovim splits and WezTerm panes.
-- Requires corresponding config in dot_config/wezterm/wezterm.lua.
-- See: cdocs/proposals/2026-02-11-smart-splits-adoption.md
return {
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,  -- Must set IS_NVIM user var at startup for WezTerm detection
    opts = {
      at_edge = "stop",  -- Do not wrap; let WezTerm handle cross-pane navigation
    },
    keys = {
      -- Navigation: Ctrl+h/j/k/l
      { "<C-h>", function() require("smart-splits").move_cursor_left() end,  desc = "Move left (split/pane)" },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end,  desc = "Move down (split/pane)" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end,    desc = "Move up (split/pane)" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move right (split/pane)" },
      -- Resize: Ctrl+Alt+h/j/k/l (matches existing WezTerm resize bindings)
      { "<C-A-h>", function() require("smart-splits").resize_left() end,  desc = "Resize left" },
      { "<C-A-j>", function() require("smart-splits").resize_down() end,  desc = "Resize down" },
      { "<C-A-k>", function() require("smart-splits").resize_up() end,    desc = "Resize up" },
      { "<C-A-l>", function() require("smart-splits").resize_right() end, desc = "Resize right" },
    },
  },
}

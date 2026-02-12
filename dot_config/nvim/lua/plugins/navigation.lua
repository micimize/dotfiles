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
      -- Navigation: Ctrl+h/j/k/l (all modes -- pane nav is higher-order than vim modes)
      { "<C-h>", function() require("smart-splits").move_cursor_left() end,  mode = { "n", "i", "t" }, desc = "Move left (split/pane)" },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end,  mode = { "n", "i", "t" }, desc = "Move down (split/pane)" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end,    mode = { "n", "i", "t" }, desc = "Move up (split/pane)" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, mode = { "n", "i", "t" }, desc = "Move right (split/pane)" },
      -- Resize: Ctrl+Alt+h/j/k/l (matches existing WezTerm resize bindings)
      { "<C-A-h>", function() require("smart-splits").resize_left() end,  desc = "Resize left" },
      { "<C-A-j>", function() require("smart-splits").resize_down() end,  desc = "Resize down" },
      { "<C-A-k>", function() require("smart-splits").resize_up() end,    desc = "Resize up" },
      { "<C-A-l>", function() require("smart-splits").resize_right() end, desc = "Resize right" },
    },
    config = function(_, opts)
      require("smart-splits").setup(opts)

      -- FocusFromEdge: WezTerm sends this after ActivatePaneDirection lands on
      -- a Neovim pane, so the correct edge split gets focus. The direction arg
      -- is the side focus arrived from (e.g., "left" means we entered from the
      -- left, so focus the leftmost split).
      vim.api.nvim_create_user_command("FocusFromEdge", function(cmd)
        local wincmd = ({ left = "h", right = "l", up = "k", down = "j" })[cmd.args]
        if wincmd then vim.cmd("999wincmd " .. wincmd) end
      end, {
        nargs = 1,
        complete = function() return { "left", "right", "up", "down" } end,
      })
    end,
  },
}

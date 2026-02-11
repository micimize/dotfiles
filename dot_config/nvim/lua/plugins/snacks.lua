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

      -- Phase 2: Notification, indent, input, explorer
      notifier = {
        enabled = true,
        top_down = false,
        style = "compact",
        filter = function(notif)
          -- Suppress known noisy deprecation warnings visually
          -- They still hit the JSONL log via the wrapper in init.lua
          local suppressions = {
            "vim.treesitter.query.get_node_text",
            "vim.treesitter.query.get_files",
            "vim.lsp.get_active_clients",
            "is deprecated",
          }
          for _, pattern in ipairs(suppressions) do
            if notif.msg and notif.msg:find(pattern, 1, true) then
              return false
            end
          end
          return true
        end,
      },
      indent = {
        enabled = true,
        char = "│",
        scope = { enabled = true },
      },
      input = { enabled = true },
      explorer = { enabled = true },
      rename = { enabled = true },
      toggle = { enabled = true },
    },
    keys = {
      -- Explorer
      { "<leader>e", function() Snacks.explorer({ focus = true }) end, desc = "Reveal in explorer" },
      { "<leader>E", function() Snacks.explorer() end, desc = "Toggle explorer" },
      -- Notifications
      { "<leader>nh", function() Snacks.notifier.show_history() end, desc = "Notification history" },
      { "<leader>nd", function() Snacks.notifier.hide() end, desc = "Dismiss notifications" },
    },
    init = function()
      -- Set up toggles after snacks loads
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          -- Toggle keymaps (integrate with which-key)
          Snacks.toggle.diagnostics():map("<leader>td")
          Snacks.toggle.inlay_hints():map("<leader>th")
          Snacks.toggle.treesitter():map("<leader>tt")
          Snacks.toggle.words():map("<leader>tw")
          Snacks.toggle({
            name = "Auto Format",
            get = function() return not vim.b.autoformat_disabled end,
            set = function(state) vim.b.autoformat_disabled = not state end,
          }):map("<leader>tf")
        end,
      })
    end,
  },
}

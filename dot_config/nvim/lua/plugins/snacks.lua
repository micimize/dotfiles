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

      -- Phase 3: Dashboard
      dashboard = {
        enabled = true,
        preset = {
          keys = {
            { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "s", desc = "Restore Session", action = ":lua require('persistence').load()" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "recent_files", limit = 8, padding = 1 },
          { section = "projects", limit = 5, padding = 1 },
          { section = "startup" },
        },
      },

      -- Phase 4: Picker and bufdelete
      picker = {
        enabled = true,
        ui_select = true,
        sources = {
          files = { hidden = true },
          grep = { hidden = true },
        },
        win = {
          input = {
            keys = {
              ["<Esc>"] = { "close", mode = { "n", "i" } },
            },
          },
        },
      },
      bufdelete = { enabled = true },
    },
    keys = {
      -- Explorer
      { "<leader>e", function() Snacks.explorer({ focus = true }) end, desc = "Reveal in explorer" },
      { "<leader>E", function() Snacks.explorer() end, desc = "Toggle explorer" },
      -- Notifications
      { "<leader>nh", function() Snacks.notifier.show_history() end, desc = "Notification history" },
      { "<leader>nd", function() Snacks.notifier.hide() end, desc = "Dismiss notifications" },
      -- Picker (replaces telescope.nvim)
      { "<C-Space>", function() Snacks.picker.files() end, desc = "Find files" },
      { "<C-S-Space>", function() Snacks.picker.commands() end, desc = "Command palette" },
      { "<C-s>", function() Snacks.picker.files() end, desc = "Find files" },
      { "<leader>ff", function() Snacks.picker.files() end, desc = "Find files" },
      { "<leader>fg", function() Snacks.picker.grep() end, desc = "Live grep" },
      { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>fh", function() Snacks.picker.help() end, desc = "Help tags" },
      { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent files" },
      { "<leader>fc", function() Snacks.picker.commands() end, desc = "Commands" },
      { "<leader>fs", function() Snacks.picker.lsp_symbols() end, desc = "Document symbols" },
      { "<leader>fS", function() Snacks.picker.lsp_workspace_symbols() end, desc = "Workspace symbols" },
      { "<leader>gc", function() Snacks.picker.git_log() end, desc = "Git commits" },
      { "<leader>gs", function() Snacks.picker.git_status() end, desc = "Git status" },
      { "<leader>fw", function() Snacks.picker.grep_word() end, desc = "Grep word under cursor" },
      { "<leader>ft", function() Snacks.picker.todo_comments() end, desc = "Find todos" },
      -- Buffer delete (replaces :bdelete in init.lua)
      { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete buffer" },
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

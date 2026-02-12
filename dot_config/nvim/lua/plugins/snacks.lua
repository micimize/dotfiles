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
          header = "Neovim",
          keys = {
            { icon = " ", key = "f", desc = "Find File", hint = "<leader>ff", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "g", desc = "Find Text", hint = "<leader>fg", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent Files", hint = "<leader>fr", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "s", desc = "Restore Session", hint = "<leader>qs", action = ":lua require('persistence').load()" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", hint = ":Lazy", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", hint = ":qa", action = ":qa" },
          },
        },
        formats = {
          desc = function(item)
            if item.hint then
              local pad = string.rep(" ", 18 - #item.desc)
              return {
                { item.desc .. pad, hl = "SnacksDashboardDesc" },
                { item.hint, hl = "Comment" },
              }
            end
            return { { item.desc, hl = "SnacksDashboardDesc" } }
          end,
          file = function(item, ctx)
            local counter = vim.g._dashboard_file_counter or 0
            counter = counter + 1
            vim.g._dashboard_file_counter = counter
            local fname = vim.fn.fnamemodify(item.file, ":~")
            fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
            local dir, file = fname:match("^(.*/)(.+)$")
            -- Fill gap with right-aligned repeating key number as a faded leader
            if ctx.width then
              local fill_len = ctx.width - #fname
              if fill_len > 2 then
                local key_pat = item.key .. " "
                local inner = string.rep(key_pat, math.ceil((fill_len - 2) / #key_pat))
                -- Right-align: trim from the left so the pattern ends flush
                local trimmed = inner:sub(-(fill_len - 2))
                local fill = " " .. trimmed .. " "
                if dir then
                  return { { dir, hl = "dir" }, { file, hl = "file" }, { fill, hl = "SnacksDashboardStripe" } }
                end
                return { { fname, hl = "file" }, { fill, hl = "SnacksDashboardStripe" } }
              end
            end
            if dir then
              return { { dir, hl = "dir" }, { file, hl = "file" } }
            end
            return { { fname, hl = "file" } }
          end,
        },
        sections = {
          { section = "header", padding = { 0, 0 } },
          {
            text = (function()
              -- Build a justified 3x4 keybind hint grid
              local grid = {
                { "leader = Space",      "<leader>t_ = toggles",  "<leader>f_ = find",     "ge = diagnostics"  },
                { "<leader>e = explorer", "<leader>rn = rename",   "<leader>ca = code action", "gd = go to def" },
                { "<leader>bd = close buf", "<leader>n_ = notify", "<leader>q_ = sessions", "K = hover docs"   },
              }
              local col_widths = {}
              for _, row in ipairs(grid) do
                for c, cell in ipairs(row) do
                  col_widths[c] = math.max(col_widths[c] or 0, #cell)
                end
              end
              local sep = "   "
              local lines = {}
              for _, row in ipairs(grid) do
                local parts = {}
                for c, cell in ipairs(row) do
                  parts[c] = cell .. string.rep(" ", col_widths[c] - #cell)
                end
                lines[#lines + 1] = table.concat(parts, sep)
              end
              return table.concat(lines, "\n")
            end)(),
            hl = "SnacksDashboardDir",
            align = "center",
            padding = 1,
          },
          { section = "keys", gap = 0, padding = 1 },
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

      -- Stripe fill between file path and key on every other row
      vim.api.nvim_set_hl(0, "SnacksDashboardStripe", { fg = "#282828" })  -- slate bg_surface, barely visible

      -- Reset file counter when dashboard opens
      vim.api.nvim_create_autocmd("User", {
        pattern = "SnacksDashboardOpened",
        callback = function()
          vim.g._dashboard_file_counter = 0
        end,
      })
    end,
  },
}

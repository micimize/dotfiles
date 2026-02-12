-- UI components: bufferline, statusline, which-key
-- Explorer, notifications, indent, and input are handled by snacks.nvim (see snacks.lua)
return {
  -- Bufferline (tab-like buffer bar)
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    event = "VeryLazy",
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        show_buffer_close_icons = false,
        show_close_icon = false,
        separator_style = "thin",
        offsets = {
          {
            filetype = "snacks_layout_box",
            text = "Explorer",
            highlight = "Directory",
            separator = true,
          },
        },
      },
    },
    keys = {
      { "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "Pin buffer" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<CR>", desc = "Close unpinned" },
    },
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = {
        theme = {
          normal   = { a = { bg = "#333333", fg = "#93a1a1", gui = "bold" }, b = { bg = "#282828", fg = "#839496" }, c = { bg = "#232323", fg = "#586e75" } },
          insert   = { a = { bg = "#859900", fg = "#232323", gui = "bold" } },
          visual   = { a = { bg = "#b58900", fg = "#232323", gui = "bold" } },
          replace  = { a = { bg = "#dc322f", fg = "#232323", gui = "bold" } },
          command  = { a = { bg = "#268bd2", fg = "#232323", gui = "bold" } },
          inactive = { a = { bg = "#1c1c1c", fg = "#586e75" }, c = { bg = "#1c1c1c", fg = "#586e75" } },
        },
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  -- Which-key: shows keybinding hints
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = true },
      defaults = {
        mode = { "n", "v" },
      },
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)
      wk.add({
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>n", group = "notifications" },
        { "<leader>r", group = "refactor" },
        { "<leader>t", group = "toggle" },
      })
    end,
  },
}

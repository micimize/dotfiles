-- Slate/Solarized theme palette
-- Archived from dot_config/wezterm/wezterm.lua during tmux migration.
-- Greyscale "Slate" replacement for solarized base colors, drawn from legacy
-- VSCode customizations. Solarized accent colors (syntax highlighting) unchanged.
-- See: cdocs/proposals/2026-03-21-tmux-return-and-lace-into.md

local slate = {
  bg_deep    = "#151515", -- deepest: sidebar, tab bar, borders
  bg         = "#1c1c1c", -- primary background
  bg_raised  = "#232323", -- elevated: line highlight, hover
  bg_surface = "#282828", -- inactive tabs, pane dividers
  bg_select  = "#333333", -- selection, active items
  fg_dim     = "#586e75", -- muted text (solarized base01)
  fg         = "#839496", -- primary text (solarized base0)
  fg_bright  = "#93a1a1", -- emphasized text (solarized base1)
  -- Solarized accents (unchanged)
  yellow     = "#b58900",
  orange     = "#cb4b16",
  red        = "#dc322f",
  magenta    = "#d33682",
  violet     = "#6c71c4",
  blue       = "#268bd2",
  cyan       = "#2aa198",
  green      = "#859900",
}

-- Color scheme override table (applied via config.colors)
local colors = {
  background = slate.bg_raised,
  cursor_bg = slate.fg,
  cursor_border = slate.fg,
  selection_bg = slate.bg_select,
  selection_fg = slate.fg_bright,
  split = slate.bg_surface,
  tab_bar = {
    background = slate.bg_deep,
    active_tab = {
      bg_color = slate.bg_raised,
      fg_color = slate.fg_bright,
      intensity = "Bold",
    },
    inactive_tab = {
      bg_color = slate.bg_surface,
      fg_color = slate.fg_dim,
    },
    inactive_tab_hover = {
      bg_color = slate.bg_select,
      fg_color = slate.fg,
    },
    new_tab = {
      bg_color = slate.bg_deep,
      fg_color = slate.fg_dim,
    },
    new_tab_hover = {
      bg_color = slate.bg_select,
      fg_color = slate.fg,
    },
  },
  copy_mode_active_highlight_bg = { Color = slate.yellow },
  copy_mode_active_highlight_fg = { Color = slate.bg },
  copy_mode_inactive_highlight_bg = { Color = slate.bg_select },
  copy_mode_inactive_highlight_fg = { Color = slate.fg },
}

-- Inactive pane dimming
local inactive_pane_hsb = {
  saturation = 0.8,
  brightness = 0.7,
}

return {
  slate = slate,
  colors = colors,
  inactive_pane_hsb = inactive_pane_hsb,
}

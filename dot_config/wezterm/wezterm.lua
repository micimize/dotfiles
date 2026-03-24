-- Minimal wezterm config (dumb terminal mode)
-- Multiplexing handled by tmux. Wezterm is a rendering-only terminal.
-- Managed by chezmoi - edit in dotfiles repo, then `chezmoi apply`
-- Full theme archived at: archive/themes/slate-solarized.lua

local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- =============================================================================
-- Appearance
-- =============================================================================

config.color_scheme = "Catppuccin Mocha"

-- Override background to crust (#11111b) for maximum contrast
config.colors = {
  background = "#11111b",
}

config.font = wezterm.font("JetBrains Mono", { weight = "DemiBold" })
config.font_size = 10.0
config.freetype_load_flags = "NO_HINTING"
config.harfbuzz_features = { "calt=0", "clig=0", "liga=0" }

config.inactive_pane_hsb = {
  saturation = 0.8,
  brightness = 0.7,
}

-- =============================================================================
-- Window
-- =============================================================================

config.initial_cols = 200
config.initial_rows = 100
config.window_background_opacity = 1.0
config.window_padding = {
  left = "6px",
  right = "6px",
  top = "6px",
  bottom = "6px",
}
config.window_decorations = "TITLE | RESIZE"

-- Hide tab bar: tmux handles tabs/windows
config.enable_tab_bar = false

-- =============================================================================
-- Shell
-- =============================================================================

-- Auto-attach to tmux: join existing session or create new one
config.default_prog = { 'tmux', 'new-session', '-A', '-s', 'main' }

-- =============================================================================
-- Core Settings
-- =============================================================================

config.scrollback_lines = 99999
config.enable_scroll_bar = false
config.check_for_updates = false

-- Disable CSI u key encoding for compatibility with apps that expect traditional sequences.
config.enable_csi_u_key_encoding = false

-- =============================================================================
-- Mouse: simple primary selection (no copy mode callbacks)
-- =============================================================================

config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor("PrimarySelection"),
  },
}

-- =============================================================================
-- Keys: override defaults that conflict with tmux bindings
-- =============================================================================

config.keys = {
  -- Pass Ctrl+V through to tmux (WezTerm default: PasteFrom clipboard).
  -- tmux intercepts Ctrl+V for context-aware image paste (lace-paste-image).
  { key = 'v', mods = 'CTRL', action = wezterm.action.SendKey { key = 'v', mods = 'CTRL' } },
}

return config

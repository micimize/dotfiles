-- Personal wezterm config
-- Managed by chezmoi - edit in dotfiles repo, then `chezmoi apply`

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- =============================================================================
-- Appearance
-- =============================================================================

config.color_scheme = "Solarized Dark (Gogh)"
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 12.0
config.line_height = 1.2

-- Window
config.window_background_opacity = 0.95
config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false

-- =============================================================================
-- Shell
-- =============================================================================

config.default_prog = { '/home/mjr/.cargo/bin/nu' }

-- =============================================================================
-- Core Settings
-- =============================================================================

config.scrollback_lines = 99999
config.enable_scroll_bar = false
config.check_for_updates = false

-- Disable CSI u key encoding for compatibility with apps that expect traditional sequences.
-- Without this, shift+space sends [27;2;32~ which some tools (Claude Code) don't handle well.
config.enable_csi_u_key_encoding = false

-- =============================================================================
-- Multiplexing - Unix Domain (enables session persistence)
-- =============================================================================

config.unix_domains = {
  { name = "unix" },
}

-- Uncomment to auto-connect to mux on startup
-- config.default_gui_startup_args = { "connect", "unix" }

-- =============================================================================
-- Keybindings
-- Modeled after tmux config:
-- - Ctrl+H/J/K/L: pane navigation
-- - Alt+H/J/K/L: splits
-- - Alt+N/P: tab navigation
-- - Alt+C: copy mode
-- =============================================================================

config.leader = { key = "z", mods = "ALT", timeout_milliseconds = 1000 }

config.keys = {
  -- Pane navigation: Ctrl+H/J/K/L
  { key = "h", mods = "CTRL", action = act.ActivatePaneDirection("Left") },
  { key = "j", mods = "CTRL", action = act.ActivatePaneDirection("Down") },
  { key = "k", mods = "CTRL", action = act.ActivatePaneDirection("Up") },
  { key = "l", mods = "CTRL", action = act.ActivatePaneDirection("Right") },

  -- Splits: Alt+H/J/K/L (preserving cwd)
  { key = "l", mods = "ALT", action = act.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
  { key = "h", mods = "ALT", action = act.SplitPane({ direction = "Left", size = { Percent = 50 } }) },
  { key = "j", mods = "ALT", action = act.SplitPane({ direction = "Down", size = { Percent = 50 } }) },
  { key = "k", mods = "ALT", action = act.SplitPane({ direction = "Up", size = { Percent = 50 } }) },

  -- Tab management: Alt+N (new), Alt+N/P (cycle)
  { key = "n", mods = "ALT|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "n", mods = "ALT", action = act.ActivateTabRelative(1) },
  { key = "p", mods = "ALT", action = act.ActivateTabRelative(-1) },

  -- Close pane: Alt+W
  { key = "w", mods = "ALT", action = act.CloseCurrentPane({ confirm = true }) },

  -- Copy mode: Alt+C
  { key = "c", mods = "ALT", action = act.ActivateCopyMode },

  -- Workspace switching
  { key = "s", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },

  -- Quick workspace access
  { key = "1", mods = "LEADER", action = act.SwitchToWorkspace({ name = "main" }) },
  { key = "2", mods = "LEADER", action = act.SwitchToWorkspace({ name = "feature" }) },
  { key = "3", mods = "LEADER", action = act.SwitchToWorkspace({ name = "scratch" }) },

  -- Pane zoom toggle: Leader+Z
  { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

  -- Resize panes: Ctrl+Alt+H/J/K/L
  { key = "h", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "j", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
  { key = "k", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
  { key = "l", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },

  -- Quick actions
  { key = ":", mods = "LEADER", action = act.ActivateCommandPalette },
  { key = "r", mods = "LEADER", action = act.ReloadConfiguration },
}

-- =============================================================================
-- Lace Plugin (for devcontainer access)
-- Discovers running lace devcontainers via Docker and provides a project picker.
-- Plugin repo: https://github.com/weftwiseink/lace.wezterm
-- =============================================================================

local function get_lace_plugin_url()
  -- Use local checkout for development; set LACE_WEZTERM_DEV=1 to force local path,
  -- or fall back to local path if the checkout exists.
  local dev_override = os.getenv("LACE_WEZTERM_DEV")
  local local_path = wezterm.home_dir .. "/code/weft/lace.wezterm"
  if dev_override or wezterm.GLOBAL.lace_use_local then
    return "file://" .. local_path
  end
  -- Default to local checkout (switch to GitHub URL when plugin is stable):
  -- return "https://github.com/weftwiseink/lace.wezterm"
  return "file://" .. local_path
end

local ok, lace_plugin = pcall(wezterm.plugin.require, get_lace_plugin_url())
if ok then
  -- Configure lace devcontainer access.
  -- The new plugin uses Docker-based port-range discovery (ports 22425-22499)
  -- and pre-registers SSH domains for the entire range.
  lace_plugin.apply_to_config(config, {
    ssh_key = wezterm.home_dir .. "/.ssh/lace_devcontainer",
  })

  -- Leader+W: Open the lace project picker (discovers running devcontainers)
  table.insert(config.keys, {
    key = "w",
    mods = "LEADER",
    action = act.EmitEvent(lace_plugin.get_picker_event()),
  })
else
  wezterm.log_warn("Failed to load lace plugin: " .. tostring(lace_plugin))
  -- Fallback: just show workspace in status bar
  wezterm.on("update-status", function(window, pane)
    local workspace = window:active_workspace()
    window:set_left_status(wezterm.format({
      { Background = { Color = "#073642" } },
      { Foreground = { Color = "#2aa198" } },
      { Text = "  " .. workspace .. " " },
    }))
  end)
end

-- =============================================================================
-- Copy Mode Customization
-- =============================================================================

local copy_mode = nil
if wezterm.gui then
  copy_mode = wezterm.gui.default_key_tables().copy_mode
end

if copy_mode then
  config.key_tables = {
    copy_mode = copy_mode,
  }
end

-- =============================================================================
-- Startup
-- =============================================================================

wezterm.on("gui-startup", function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)

return config

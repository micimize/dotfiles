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
-- Loads from host path or container mount path
-- =============================================================================

local function get_lace_plugin_path()
  -- Check if running in a container with lace mounted as a plugin
  local is_container = os.getenv("REMOTE_CONTAINERS") ~= nil
  if is_container then
    return "file:///mnt/lace/plugins/lace/config/wezterm/lace-plugin"
  else
    -- Host path - adjust to your local lace checkout
    return "file://" .. wezterm.home_dir .. "/code/weft/lace/config/wezterm/lace-plugin"
  end
end

local ok, lace_plugin = pcall(wezterm.plugin.require, get_lace_plugin_path())
if ok then
  -- Configure lace devcontainer access
  lace_plugin.apply_to_config(config, {
    ssh_key = wezterm.home_dir .. "/.ssh/lace_devcontainer",
    domain_name = "lace",
    ssh_port = "localhost:2222",
  })

  -- Leader+D: Connect to lace devcontainer
  table.insert(config.keys, {
    key = "d",
    mods = "LEADER",
    action = lace_plugin.connect_action({
      domain_name = "lace",
      workspace_path = "/workspace",
      main_worktree = "lace",
    }),
  })

  -- Leader+W: Lace worktree picker
  table.insert(config.keys, {
    key = "w",
    mods = "LEADER",
    action = act.EmitEvent(lace_plugin.get_picker_event("lace")),
  })

  -- Configure dotfiles devcontainer access (different port)
  lace_plugin.apply_to_config(config, {
    ssh_key = wezterm.home_dir .. "/.ssh/dotfiles_devcontainer",
    domain_name = "dotfiles",
    ssh_port = "localhost:2223",
    workspace_path = "/workspaces",  -- devcontainer default
    main_worktree = "dotfiles",
    enable_status_bar = false,  -- Already registered by lace config
  })

  -- Leader+F: Connect to dotfiles devcontainer
  table.insert(config.keys, {
    key = "f",
    mods = "LEADER",
    action = lace_plugin.connect_action({
      domain_name = "dotfiles",
      workspace_path = "/workspaces",
      main_worktree = "dotfiles",
    }),
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

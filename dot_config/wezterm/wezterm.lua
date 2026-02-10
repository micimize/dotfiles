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
-- Mouse Bindings
-- Route mouse selection to PrimarySelection only (not system clipboard).
-- On Linux, the convention is: mouse select -> primary selection (middle-click),
-- explicit copy (Ctrl-C / y in copy mode) -> system clipboard.
-- =============================================================================

local function mouse_bind(dir, streak, button, mods, action)
  return {
    event = { [dir] = { streak = streak, button = button } },
    mods = mods,
    action = action,
  }
end

-- Mouse selection -> copy mode helper.
-- Saves selection to PrimarySelection, then enters copy mode.
-- NOTE: ActivateCopyMode clears the visual selection (compiled Rust, CopyOverlay
-- initializes with start=None). The text IS in PrimarySelection for middle-click.
-- To revert to simple selection without copy mode entry, replace the callback
-- bindings below with act.CompleteSelectionOrOpenLinkAtMouseCursor('PrimarySelection').
local function mouse_select_into_copy_mode(window, pane)
  if window:active_key_table() == 'copy_mode' then
    window:perform_action(act.CompleteSelection('PrimarySelection'), pane)
    return
  end
  local sel = window:get_selection_text_for_pane(pane)
  if sel ~= '' then
    window:perform_action(act.CompleteSelection('PrimarySelection'), pane)
    window:perform_action(act.ActivateCopyMode, pane)
  else
    window:perform_action(
      act.CompleteSelectionOrOpenLinkAtMouseCursor('PrimarySelection'), pane)
  end
end

config.mouse_bindings = {
  -- Single click release: enter copy mode if text selected, else open link
  mouse_bind('Up', 1, 'Left', 'NONE',
    wezterm.action_callback(mouse_select_into_copy_mode)),
  -- Shift+click (extend selection): primary only
  mouse_bind('Up', 1, 'Left', 'SHIFT',
    act.CompleteSelectionOrOpenLinkAtMouseCursor('PrimarySelection')),
  -- Alt+click: primary only
  mouse_bind('Up', 1, 'Left', 'ALT',
    act.CompleteSelection('PrimarySelection')),
  -- Shift+Alt+click: primary only
  mouse_bind('Up', 1, 'Left', 'SHIFT|ALT',
    act.CompleteSelectionOrOpenLinkAtMouseCursor('PrimarySelection')),
  -- Double click (word select): enter copy mode
  mouse_bind('Up', 2, 'Left', 'NONE',
    wezterm.action_callback(mouse_select_into_copy_mode)),
  -- Triple click (line select): enter copy mode
  mouse_bind('Up', 3, 'Left', 'NONE',
    wezterm.action_callback(mouse_select_into_copy_mode)),
}

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
-- Vim/tmux-like copy mode keybindings.
-- Enter copy mode: Alt+C
-- Limitations (upstream wezterm): no %, no W/B/E, no text objects, no count
-- prefix, no Ctrl-Y/Ctrl-E scroll, no marks, no registers.
-- See: https://github.com/wezterm/wezterm/issues/4471
-- =============================================================================

local copy_mode = nil
local search_mode = nil
if wezterm.gui then
  local defaults = wezterm.gui.default_key_tables()
  copy_mode = defaults.copy_mode
  search_mode = defaults.search_mode
end

if copy_mode then
  -- Helper: find and replace a binding in the key table by key+mods
  local function override_binding(tbl, key, mods, new_action)
    for i, binding in ipairs(tbl) do
      if binding.key == key and (binding.mods or 'NONE') == (mods or 'NONE') then
        tbl[i].action = new_action
        return
      end
    end
    -- Not found -- append
    table.insert(tbl, { key = key, mods = mods or 'NONE', action = new_action })
  end

  -- y: yank to clipboard + primary, scroll to bottom, exit copy mode
  -- MoveToScrollbackBottom returns the cursor to the live terminal area before closing.
  -- Note: 'ScrollToBottom' is NOT a valid CopyMode variant in wezterm 20240203;
  -- MoveToScrollbackBottom is the correct CopyMode action for this purpose.
  override_binding(copy_mode, 'y', 'NONE', act.Multiple {
    { CopyTo = 'ClipboardAndPrimarySelection' },
    { CopyMode = 'MoveToScrollbackBottom' },
    { CopyMode = 'Close' },
  })

  -- Y: yank entire line (enter line mode, copy, exit)
  -- New binding (no default Y in copy_mode). Selects the current line, copies, and exits.
  override_binding(copy_mode, 'Y', 'SHIFT', act.Multiple {
    { CopyMode = { SetSelectionMode = 'Line' } },
    { CopyTo = 'ClipboardAndPrimarySelection' },
    { CopyMode = 'MoveToScrollbackBottom' },
    { CopyMode = 'Close' },
  })

  -- Escape: always exit copy mode cleanly.
  -- Previous version tried vim-like "clear selection first, exit second" but
  -- get_selection_text_for_pane returns PrimarySelection content even without
  -- an active copy mode selection, causing Escape to appear stuck.
  override_binding(copy_mode, 'Escape', 'NONE', act.Multiple {
    { CopyMode = 'MoveToScrollbackBottom' },
    { CopyMode = 'Close' },
  })

  -- q: always exit copy mode (no selection, no copy)
  override_binding(copy_mode, 'q', 'NONE', act.Multiple {
    { CopyMode = 'ClearSelectionMode' },
    { CopyMode = 'MoveToScrollbackBottom' },
    { CopyMode = 'Close' },
  })

  config.key_tables = config.key_tables or {}
  config.key_tables.copy_mode = copy_mode
  config.key_tables.search_mode = search_mode
end

-- =============================================================================
-- Startup
-- =============================================================================

if not wezterm.GLOBAL.gui_startup_registered then
  wezterm.GLOBAL.gui_startup_registered = true
  wezterm.on("gui-startup", function(cmd)
    local tab, pane, window = wezterm.mux.spawn_window({
      workspace = "main",
      cwd = wezterm.home_dir,
    })
  end)
end

return config

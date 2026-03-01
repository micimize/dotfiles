-- Personal wezterm config
-- Managed by chezmoi - edit in dotfiles repo, then `chezmoi apply`

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- =============================================================================
-- Slate Palette
-- Greyscale replacement for solarized base colors, drawn from legacy VSCode
-- customizations. Solarized accent colors (syntax highlighting) are unchanged.
-- =============================================================================

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

-- =============================================================================
-- Appearance
-- =============================================================================

-- Keep the scheme for its 16 ANSI color definitions; override backgrounds/chrome below
config.color_scheme = "Solarized Dark (Gogh)"
-- Font: uncomment one line to switch. DemiBold compensates for NO_HINTING thin strokes.
-- JetBrains Mono is WezTerm's built-in; FiraCode and Iosevka installed to ~/.local/share/fonts/NerdFonts/.
config.font = wezterm.font("JetBrains Mono", { weight = "DemiBold" })
-- config.font = wezterm.font("FiraCode Nerd Font", { weight = "DemiBold" })
-- config.font = wezterm.font("Iosevka Nerd Font", { weight = "DemiBold" })
config.font_size = 10.0
-- config.line_height = 1.2
-- WezTerm uses fractional pixel positioning for glyphs, which can cause inconsistent
-- character rendering at small sizes. NO_HINTING avoids the worst conflicts between
-- FreeType hinting and WezTerm's sub-pixel layout. See: #3774
config.freetype_load_flags = "NO_HINTING"
config.harfbuzz_features = { "calt=0", "clig=0", "liga=0" } -- disable ligatures

-- Slate background and chrome overrides (merge with color_scheme's ANSI palette)
config.colors = {
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
  -- Copy mode: yellow highlight on active search match
  copy_mode_active_highlight_bg = { Color = slate.yellow },
  copy_mode_active_highlight_fg = { Color = slate.bg },
  copy_mode_inactive_highlight_bg = { Color = slate.bg_select },
  copy_mode_inactive_highlight_fg = { Color = slate.fg },
}

-- Dim inactive panes (recreates the tmux bg-contrast gutter effect)
config.inactive_pane_hsb = {
  saturation = 0.8,
  brightness = 0.7,
}

local border_color = slate.bg_surface
local border_width = "2px"
local border_padding = "6px"
-- Window
config.initial_cols = 200
config.initial_rows = 100
config.window_background_opacity = 0.95
config.window_padding = {
  left = border_padding,
  right = border_padding,
  top = border_padding,
  bottom = border_padding
}
config.window_decorations = "TITLE | RESIZE"
config.window_frame = {
  border_left_width = border_width,
  border_right_width = border_width,
  border_bottom_height = border_width,
  border_top_height = border_width,
  border_left_color = border_color,
  border_right_color = border_color,
  border_bottom_color = border_color,
  border_top_color = border_color,
}
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.tab_max_width = 40
config.show_new_tab_button_in_tab_bar = false

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
config.status_update_interval = 200 -- ms, fast mode detection for copy/search badges

-- Disable CSI u key encoding for compatibility with apps that expect traditional sequences.
-- Without this, shift+space sends [27;2;32~ which some tools (Claude Code) don't handle well.
config.enable_csi_u_key_encoding = false

-- =============================================================================
-- Multiplexing - Unix Domain (enables session persistence)
-- =============================================================================

config.unix_domains = {
  { name = "unix" },
}

config.default_gui_startup_args = { "connect", "unix" }

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
-- Smart Splits Integration (seamless neovim/wezterm pane navigation)
-- Requires smart-splits.nvim on the neovim side.
-- See: cdocs/proposals/2026-02-11-smart-splits-adoption.md
-- =============================================================================

local function is_nvim(pane)
  return pane:get_user_vars().IS_NVIM == "true"
end

local direction_keys = {
  Left = "h",
  Down = "j",
  Up = "k",
  Right = "l",
  h = "Left",
  j = "Down",
  k = "Up",
  l = "Right",
}

-- Send a Neovim ex command to a pane via synthetic keystrokes.
-- Uses <C-\><C-n> (force normal mode without triggering buffer-local Escape
-- mappings, e.g. snacks picker closes on Escape), then :<cmd><Enter>.
local function send_nvim_cmd(win, target_pane, cmd)
  local keys = {
    { SendKey = { key = "\\", mods = "CTRL" } },
    { SendKey = { key = "n", mods = "CTRL" } },
    { SendKey = { key = ":" } },
  }
  for i = 1, #cmd do
    table.insert(keys, { SendKey = { key = cmd:sub(i, i) } })
  end
  table.insert(keys, { SendKey = { key = "Enter" } })
  win:perform_action(act.Multiple(keys), target_pane)
end

-- Entry direction: when navigating INTO a Neovim pane, which edge should
-- get focus. Key "l" (navigating right) means entered from the left.
local entry_from = { h = "right", l = "left", k = "down", j = "up" }

local function split_nav(resize_or_move, key)
  local mods = resize_or_move == "resize" and "CTRL|ALT" or "CTRL"
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        win:perform_action({ SendKey = { key = key, mods = mods } }, pane)
      else
        if resize_or_move == "resize" then
          win:perform_action({ AdjustPaneSize = { direction_keys[key], 5 } }, pane)
        else
          -- Peek at the target pane before navigating
          local tab = win:active_tab()
          local target = tab:get_pane_direction(direction_keys[key])

          win:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)

          -- If we just landed on Neovim, focus the directionally-correct split
          if target and target:get_user_vars().IS_NVIM == "true" then
            send_nvim_cmd(win, target, "FocusFromEdge " .. entry_from[key])
          end
        end
      end
    end),
  }
end

-- =============================================================================
-- Keybindings
-- Modeled after tmux config:
-- - Ctrl+H/J/K/L: pane navigation (smart-splits aware)
-- - Ctrl+Alt+H/J/K/L: resize (smart-splits aware)
-- - Alt+H/J/K/L: splits
-- - Alt+N/P: tab navigation
-- - Alt+C: copy mode
-- =============================================================================

config.leader = { key = "z", mods = "ALT", timeout_milliseconds = 1000 }

config.keys = {
  -- Pane navigation: Ctrl+H/J/K/L (smart-splits aware)
  split_nav("move", "h"),
  split_nav("move", "j"),
  split_nav("move", "k"),
  split_nav("move", "l"),

  -- Splits: Alt+H/J/K/L (preserving cwd)
  { key = "l", mods = "ALT",       action = act.SplitPane({ direction = "Right", size = { Percent = 50 } }) },
  { key = "h", mods = "ALT",       action = act.SplitPane({ direction = "Left", size = { Percent = 50 } }) },
  { key = "j", mods = "ALT",       action = act.SplitPane({ direction = "Down", size = { Percent = 50 } }) },
  { key = "k", mods = "ALT",       action = act.SplitPane({ direction = "Up", size = { Percent = 50 } }) },

  -- Tab management: Alt+N (new), Alt+N/P (cycle)
  { key = "n", mods = "ALT|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "n", mods = "ALT",       action = act.ActivateTabRelative(1) },
  { key = "p", mods = "ALT",       action = act.ActivateTabRelative(-1) },

  -- Close pane: Alt+W
  { key = "w", mods = "ALT",       action = act.CloseCurrentPane({ confirm = true }) },

  -- Copy mode: Alt+C
  { key = "c", mods = "ALT",       action = act.ActivateCopyMode },

  -- Workspace switching
  { key = "s", mods = "LEADER",    action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },

  -- Quick workspace access
  { key = "1", mods = "LEADER",    action = act.SwitchToWorkspace({ name = "main" }) },
  { key = "2", mods = "LEADER",    action = act.SwitchToWorkspace({ name = "feature" }) },
  { key = "3", mods = "LEADER",    action = act.SwitchToWorkspace({ name = "scratch" }) },

  -- Pane zoom toggle: Leader+Z
  { key = "z", mods = "LEADER",    action = act.TogglePaneZoomState },

  -- Resize panes: Ctrl+Alt+H/J/K/L (smart-splits aware)
  split_nav("resize", "h"),
  split_nav("resize", "j"),
  split_nav("resize", "k"),
  split_nav("resize", "l"),

  -- Detach from mux domain (like tmux prefix+d)
  { key = "d", mods = "LEADER", action = act.DetachDomain 'CurrentPaneDomain' },

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
  -- Tab mode: projects open as tabs in the current window instead of
  -- separate workspaces. Tab titles are resolved by format-tab-title below.
  lace_plugin.apply_to_config(config, {
    ssh_key = wezterm.home_dir .. "/.config/lace/ssh/id_ed25519",
    connection_mode = "tab",
  })

  -- Leader+W: Open the lace project picker (discovers running devcontainers)
  table.insert(config.keys, {
    key = "w",
    mods = "LEADER",
    action = act.EmitEvent(lace_plugin.get_picker_event()),
  })

  -- Tab title resolution: prefer explicit tab title, then lace discovery
  -- cache (project name by domain port), then fall back to pane title.
  -- This makes lace tab titles immune to OSC title changes from TUIs.
  wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
    local title = lace_plugin.format_tab_title(tab)
    if #title > max_width - 2 then
      title = title:sub(1, max_width - 5) .. "..."
    end
    return " " .. title .. " "
  end)
else
  wezterm.log_warn("Failed to load lace plugin: " .. tostring(lace_plugin))
end

-- =============================================================================
-- Resurrect Plugin (cross-reboot session persistence)
-- Serializes workspace layouts to JSON on disk. Paired with unix domain mux
-- (live persistence) for two-layer coverage. Shell commands (`wez save/restore`)
-- communicate via OSC 1337 user variable IPC.
-- Plugin repo: https://github.com/MLFlexer/resurrect.wezterm
-- =============================================================================

local ok_resurrect, resurrect = pcall(
  wezterm.plugin.require,
  "https://github.com/MLFlexer/resurrect.wezterm"
)

if ok_resurrect and not wezterm.GLOBAL.resurrect_initialized then
  wezterm.GLOBAL.resurrect_initialized = true

  -- Override save directory to a stable path (default is inside the plugin's
  -- URL-encoded directory, which is fragile for shell-side access)
  resurrect.state_manager.change_state_save_dir(
    wezterm.home_dir .. "/.local/share/wezterm/resurrect/"
  )
  resurrect.state_manager.set_max_nlines(5000)

  resurrect.state_manager.periodic_save({
    interval_seconds = 300,
    save_workspaces = true,
    save_windows = true,
    save_tabs = true,
  })

  -- Parse IPC command: "action|arg|nonce" → action, arg (nonce discarded)
  local function parse_ipc(value)
    local parts = {}
    for part in value:gmatch("[^|]+") do
      table.insert(parts, part)
    end
    return parts[1] or "", parts[2] or ""
  end

  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name ~= "WEZ_SESSION_CMD" then return end
    local action, arg = parse_ipc(value)

    if action == "save" then
      local state = resurrect.workspace_state.get_workspace_state()
      if arg ~= "" then
        resurrect.state_manager.save_state(state, arg)
      else
        resurrect.state_manager.save_state(state)
      end
      local label = arg ~= "" and arg or window:active_workspace()
      window:toast_notification("wezterm", "Session saved: " .. label, nil, 3000)

    elseif action == "restore" then
      local state = resurrect.state_manager.load_state(arg, "workspace")
      if state and state.workspace then
        resurrect.workspace_state.restore_workspace(state, {
          window = window:mux_window(),
          relative = true,
          restore_text = true,
          close_open_tabs = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        })
        window:toast_notification("wezterm", "Session restored: " .. arg, nil, 3000)
      else
        window:toast_notification("wezterm", "No saved session: " .. arg, nil, 3000)
      end
    end
  end)

  wezterm.on("resurrect.error", function(err)
    wezterm.log_error("resurrect error: " .. tostring(err))
  end)
elseif not ok_resurrect then
  wezterm.log_warn("Failed to load resurrect plugin: " .. tostring(resurrect))
end

-- =============================================================================
-- Status Bar + Mode Indication
-- Unified handler: workspace (left), mode badge or clock (right).
-- No set_config_overrides — avoids Issue #5318 (key table stack clearing)
-- and the colors table replacement bug that wiped slate palette.
-- =============================================================================

wezterm.on("update-status", function(window, pane)
  local key_table = window:active_key_table()
  local is_copy = key_table == "copy_mode"
  local is_search = key_table == "search_mode"

  -- Right status: mode badge or clock
  local right
  if is_copy then
    right = wezterm.format({
      { Background = { Color = slate.yellow } },
      { Foreground = { Color = slate.bg_deep } },
      { Attribute = { Intensity = "Bold" } },
      { Text = " 󰆐 COPY " },
    })
  elseif is_search then
    right = wezterm.format({
      { Background = { Color = slate.blue } },
      { Foreground = { Color = slate.bg_deep } },
      { Attribute = { Intensity = "Bold" } },
      { Text = "  SEARCH " },
    })
  else
    right = wezterm.format({
      { Background = { Color = slate.bg_deep } },
      { Foreground = { Color = slate.fg_dim } },
      { Text = " " .. wezterm.strftime("%H:%M") .. "  " },
    })
  end
  window:set_right_status(right)

  -- Left status: workspace name (always visible)
  window:set_left_status(wezterm.format({
    { Background = { Color = slate.bg_deep } },
    { Foreground = { Color = slate.cyan } },
    { Text = "  " .. window:active_workspace() .. " " },
    { Foreground = { Color = slate.fg_dim } },
    { Text = " " },
  }))
end)

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

-- mux-startup fires once when the mux server first starts.
-- Does NOT fire on GUI reconnect — only on initial server spawn.
wezterm.on("mux-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)

return config

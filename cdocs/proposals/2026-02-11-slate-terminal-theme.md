---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-11T17:10:00-08:00"
task_list: styling/slate-theme
type: proposal
state: live
status: review_ready
tags: [styling, wezterm, neovim, theme, migration]
---

# Slate Terminal Theme

> BLUF: Replace the blue-tinted Solarized Dark backgrounds with a greyscale slate palette
> (`#151515`-`#333333`) drawn from the existing VSCode customizations, while keeping
> solarized's syntax colors intact. Simultaneously improve five UX qualities: pane divider
> visibility, copy-mode prominence, tab bar information density, and window border presence.
> All changes use existing WezTerm config options and Neovim highlight overrides -- no new
> plugins required. See `cdocs/reports/2026-02-11-terminal-styling-audit.md` for the full
> audit backing this proposal.

## Objective

Restore the visual qualities of the tmux+VSCode workflow that were lost during the
WezTerm migration:

1. **Greyscale slate backgrounds** instead of solarized's blue-tinted base colors.
2. **Visible pane gutters** that create spatial separation between panes.
3. **Prominent copy-mode cursor** (yellow) so it's immediately obvious when copy mode is active.
4. **Wider, more informative tabs** with workspace name and clock.
5. **Window border/frame** to give WezTerm a more finished, grabbable feel.

## Background

### Source Palette

The greyscale slate palette comes from the user's long-standing VSCode `colorCustomizations`
(recovered from `archive/legacy/vscode/settings.jsonc`):

```
#151515  -- deepest background (sidebar, secondary surfaces)
#1c1c1c  -- primary background (editor, main content)
#232323  -- elevated surfaces (line highlight, hover)
#282828  -- tab bar, inactive tabs
#333333  -- selection, active list items
```

These replace solarized's `base03` (`#002b36`), `base02` (`#073642`), and `base01`
(`#586e75`). Solarized content colors (`base0`/`base1` for text, and the eight accent
colors) remain unchanged.

### Legacy tmux Pane Gutter

The old tmux config used `window-style bg=brightblack` to give inactive panes a lighter
background (`#586e75` in solarized). The active pane kept `bg=black` (`#073642`). This
background differential created a "gutter" effect -- the inactive pane's lighter surface
itself was the visual separator, making the thin border line almost unnecessary.

### WezTerm Styling Affordances (from research)

Key config options available:

- **`colors` table**: Override any scheme color including `background`, `split`,
  `copy_mode_active_highlight_bg/fg`, `copy_mode_inactive_highlight_bg/fg`, `tab_bar.*`.
- **`inactive_pane_hsb`**: Adjust hue/saturation/brightness of inactive panes globally.
- **`window_frame`**: Border color, size, and font for the fancy tab bar title area.
- **`window_decorations`**: `"RESIZE"` (current), `"TITLE|RESIZE"`, `"INTEGRATED_BUTTONS|RESIZE"`.
- **`tab_max_width`**: Controls maximum tab width (default 16, can increase).
- **`update-status` event**: Programmatic left/right status bar content (workspace, clock).
- **`underline_thickness`**: Affects pane split line width (side effect: also affects URL underlines).

### Neovim Styling Affordances

- **`solarized.nvim` palette overrides**: The plugin accepts custom palette tables.
- **`WinSeparator` highlight group**: Controls split divider `fg`/`bg`.
- **`fillchars`**: Can change the vertical separator character (e.g., space for invisible, `│` for visible).
- **`lualine` theme**: Can be customized to match slate palette.
- **`bufferline` highlights**: Accepts custom highlight overrides.

## Proposed Solution

### Shared Palette Constants

Define the slate palette once at the top of `wezterm.lua` and as a table in
`colorscheme.lua` for neovim:

```lua
-- Slate palette (greyscale replacement for solarized base colors)
local slate = {
  bg_deep    = "#151515",  -- deepest: sidebar, secondary
  bg         = "#1c1c1c",  -- primary background
  bg_raised  = "#232323",  -- elevated: line highlight, hover
  bg_surface = "#282828",  -- tab bar, inactive tabs
  bg_select  = "#333333",  -- selection, active items
  fg_dim     = "#586e75",  -- muted text (solarized base01)
  fg         = "#839496",  -- primary text (solarized base0)
  fg_bright  = "#93a1a1",  -- emphasized text (solarized base1)
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
```

### WezTerm Changes

#### 1. Base Colors

Override the scheme's background colors via the `colors` table:

```lua
config.colors = {
  background = slate.bg,
  cursor_bg = slate.fg,
  cursor_border = slate.fg,
  selection_bg = slate.bg_select,
  selection_fg = slate.fg_bright,
  split = slate.bg_surface,    -- pane divider color
  -- Tab bar (retro style)
  tab_bar = {
    background = slate.bg_deep,
    active_tab = {
      bg_color = slate.bg,
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
  -- Copy mode: yellow cursor for high visibility
  copy_mode_active_highlight_bg = { Color = slate.yellow },
  copy_mode_active_highlight_fg = { Color = slate.bg },
  copy_mode_inactive_highlight_bg = { Color = slate.bg_select },
  copy_mode_inactive_highlight_fg = { Color = slate.fg },
}
```

#### 2. Pane Dividers / Gutter Effect

Two complementary mechanisms:

```lua
-- Dim inactive panes slightly (recreates the tmux bg contrast effect)
config.inactive_pane_hsb = {
  saturation = 0.8,
  brightness = 0.7,
}
```

The `colors.split` (set to `slate.bg_surface` = `#282828`) makes the divider line
a visible but not harsh grey. Combined with `inactive_pane_hsb` dimming, inactive
panes appear recessed while the active pane stays crisp -- similar to the old tmux gutter.

> NOTE: `underline_thickness` could make the split line thicker, but it also affects
> URL underlines globally. Not recommended unless the side effect is acceptable.

#### 3. Copy Mode Visibility

The `copy_mode_active_highlight_bg` set to `slate.yellow` (`#b58900`) creates a bold
yellow highlight on the active match, closely matching the tmux copy-mode cursor.
The inactive match uses the standard selection color for differentiation.

#### 4. Tab Bar: Wider Tabs + Status Content

```lua
config.tab_max_width = 40
config.show_new_tab_button_in_tab_bar = false
```

Add an `update-status` handler for workspace name and clock:

```lua
wezterm.on("update-status", function(window, pane)
  local workspace = window:active_workspace()
  local time = wezterm.strftime("%H:%M")

  window:set_left_status(wezterm.format({
    { Background = { Color = slate.bg_deep } },
    { Foreground = { Color = slate.cyan } },
    { Text = "  " .. workspace .. " " },
    { Foreground = { Color = slate.fg_dim } },
    { Text = " " },
  }))

  window:set_right_status(wezterm.format({
    { Background = { Color = slate.bg_deep } },
    { Foreground = { Color = slate.fg_dim } },
    { Text = " " .. time .. "  " },
  }))
end)
```

> NOTE: The existing lace plugin fallback already sets left status. The `update-status`
> handler should be unified -- either lace provides full status or we use our own.
> Recommend always setting our own and letting lace extend it if loaded.

#### 5. Window Border

```lua
config.window_decorations = "RESIZE"
config.window_frame = {
  border_left_width = "4px",
  border_right_width = "4px",
  border_bottom_height = "4px",
  border_top_height = "4px",
  border_left_color = slate.bg_deep,
  border_right_color = slate.bg_deep,
  border_bottom_color = slate.bg_deep,
  border_top_color = slate.bg_deep,
}
config.window_padding = { left = 8, right = 8, top = 8, bottom = 4 }
```

The `window_frame` border creates a dark frame around the terminal content.
Slightly increased `window_padding` adds breathing room inside the content area.
Keeping `RESIZE` decorations means no OS title bar but the dark border makes the
window edge easy to grab.

### Neovim Changes

#### Colorscheme Overrides

Update `lua/plugins/colorscheme.lua` to override solarized base colors:

```lua
opts = {
  palette = {
    base03  = "#151515",  -- darkest bg
    base02  = "#1c1c1c",  -- primary bg
    base01  = "#333333",  -- comments, secondary
    -- Keep content/accent colors as default solarized
  },
  transparent = { enabled = false },
  -- ...existing styles...
}
```

> NOTE: Need to verify that `maxmx03/solarized.nvim` supports `palette` overrides.
> If not, use `on_highlights` callback or post-setup `nvim_set_hl` overrides.

#### Window Separator

Add to the colorscheme `config` function:

```lua
-- Slate-colored window separators
hl(0, "WinSeparator", { fg = "#282828", bg = "#151515" })
```

Setting `bg` on `WinSeparator` creates a visible gutter column in the separator
character's background, visually similar to the tmux approach.

#### Lualine Theme

Update lualine to use a custom theme or override sections:

```lua
theme = {
  normal   = { a = { bg = "#282828", fg = "#93a1a1", gui = "bold" }, b = { bg = "#232323", fg = "#839496" }, c = { bg = "#1c1c1c", fg = "#586e75" } },
  insert   = { a = { bg = "#859900", fg = "#1c1c1c", gui = "bold" } },
  visual   = { a = { bg = "#b58900", fg = "#1c1c1c", gui = "bold" } },
  replace  = { a = { bg = "#dc322f", fg = "#1c1c1c", gui = "bold" } },
  command  = { a = { bg = "#268bd2", fg = "#1c1c1c", gui = "bold" } },
  inactive = { a = { bg = "#151515", fg = "#586e75" }, c = { bg = "#151515", fg = "#586e75" } },
},
```

## Important Design Decisions

### Keep Solarized Syntax Colors

**Decision:** Override only background/chrome colors, keep solarized accent colors for syntax.

**Why:** The solarized accent palette (yellow, cyan, green, etc.) is carefully designed for
contrast and readability. The VSCode customizations followed this same strategy: slate
backgrounds + solarized syntax. Switching to a fully different theme would change muscle
memory and code-reading habits simultaneously with the infrastructure change.

### Retro Tab Bar (not Fancy)

**Decision:** Keep `use_fancy_tab_bar = false` and style the retro tab bar.

**Why:** The retro tab bar renders inside the terminal surface and is more customizable
via `colors.tab_bar`. The fancy tab bar uses OS-native rendering with limited color control.
The retro bar also matches the tmux-style bottom bar aesthetic.

### `inactive_pane_hsb` Dimming vs. Background Override

**Decision:** Use `inactive_pane_hsb` for the gutter effect rather than trying to set
different backgrounds per pane.

**Why:** WezTerm doesn't support per-pane background colors in config. `inactive_pane_hsb`
globally dims inactive panes (saturation and brightness), which produces the desired
active-vs-inactive contrast. The exact values (0.8 sat, 0.7 brightness) are starting
points to tune interactively.

### `window_frame` Border vs. `INTEGRATED_BUTTONS`

**Decision:** Use `window_frame` border with `RESIZE` decorations rather than switching
to `INTEGRATED_BUTTONS|RESIZE`.

**Why:** `INTEGRATED_BUTTONS` adds window management buttons (close/minimize/maximize) to
the tab bar, which isn't needed for this use case. The goal is a subtle dark border for
visual containment and grab-ability. `window_frame` border achieves this cleanly without
UI chrome overhead. On Linux/Wayland the border adds the necessary grab target without
a title bar.

### Unified Status Handler

**Decision:** Always register our own `update-status` handler; let lace extend rather
than replace it.

**Why:** The current code only sets status in the lace fallback path. If lace loads, it
owns the status bar entirely. With the new design, we always want workspace + clock.
Lace can add its devcontainer indicator alongside.

## Edge Cases / Challenging Scenarios

### Solarized.nvim Palette Override Support

The `maxmx03/solarized.nvim` plugin may not accept a `palette` key in opts. If so,
use `on_highlights` or manual `nvim_set_hl` calls after `colorscheme` load. Verify
during Phase 2.

### Terminal ANSI Color Conflicts

WezTerm's `color_scheme` sets the 16 ANSI colors. Our `colors` table only overrides
specific named keys (background, split, etc.) and does NOT override the ANSI palette.
CLI tools that use ANSI colors (ls, git diff, etc.) will continue using solarized's
standard ANSI mapping. If ANSI `black` (`color0`) still shows as solarized `#073642`
in TUI backgrounds, we may need to override `ansi[1]` to `#1c1c1c`.

### Lace Plugin Status Bar Conflict

The lace plugin calls `set_left_status` in its own `update-status` handler. If both
handlers run, the last one wins. Solution: check if lace is loaded and either merge
status content or let lace call our format function.

### Bufferline Theme Mismatch

Bufferline auto-detects the colorscheme, but if solarized's base colors are overridden
via `nvim_set_hl`, bufferline may not pick up the changes. May need explicit
`highlights` overrides in bufferline opts.

## Implementation Phases

### Phase 1: WezTerm Base Colors + Pane Dividers

**Scope:** Define slate palette, add `colors` table, set `inactive_pane_hsb`, set
`colors.split`.

**Files:** `dot_config/wezterm/wezterm.lua`

**Verification:**
1. Baseline capture: `wezterm show-keys --lua > /tmp/wez_keys_before.lua`
2. `ls-fonts` stderr check for parse errors.
3. `show-keys` diff to confirm no binding regression.
4. Visual: background should be dark grey, not blue. Inactive panes visibly dimmed.
5. `chezmoi apply` + confirm hot-reload.

### Phase 2: Neovim Slate Overrides

**Scope:** Override solarized.nvim base colors, set `WinSeparator` highlight, update
lualine theme, check bufferline.

**Files:** `dot_config/nvim/lua/plugins/colorscheme.lua`, `dot_config/nvim/lua/plugins/ui.lua`

**Verification:**
1. `chezmoi apply --force` to deploy.
2. Headless: load config, check `Normal` bg is `#1c1c1c`, `WinSeparator` fg is `#282828`.
3. Live: open splits, verify separator color and gutter effect.
4. Live: confirm lualine sections use slate background, mode colors are correct.
5. Confirm bufferline picks up new background or add explicit highlights.

### Phase 3: Copy Mode Visibility

**Scope:** Add `copy_mode_active_highlight_bg/fg` and `copy_mode_inactive_highlight_bg/fg`
to WezTerm `colors` table.

**Files:** `dot_config/wezterm/wezterm.lua`

**Verification:**
1. `ls-fonts` parse check.
2. Enter copy mode (`Alt-C`), search for text, confirm yellow highlight on active match.
3. Confirm inactive matches use muted selection color.
4. Test yank (`y`) exits cleanly.

### Phase 4: Tab Bar + Status

**Scope:** Set `tab_max_width`, register `update-status` handler with workspace + clock,
unify with lace plugin status.

**Files:** `dot_config/wezterm/wezterm.lua`

**Verification:**
1. `ls-fonts` parse check.
2. Tabs should be wider, showing full workspace context.
3. Left status: workspace name in cyan. Right status: clock.
4. If lace loads, devcontainer indicator should appear alongside (not replace) workspace.
5. Switch workspaces and confirm status updates.

### Phase 5: Window Border

**Scope:** Add `window_frame` border settings, adjust `window_padding`.

**Files:** `dot_config/wezterm/wezterm.lua`

**Verification:**
1. `ls-fonts` parse check.
2. Visual: dark border visible around terminal window.
3. Window is easily grabbable on all edges.
4. Tab bar and content area still render correctly within the frame.
5. Resize from all edges works.

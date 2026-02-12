---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-11T17:05:00-08:00"
task_list: styling/audit
type: report
state: live
status: complete
tags: [status, styling, wezterm, neovim, tmux, migration]
---

# Terminal Styling Audit: WezTerm, Neovim, and Legacy tmux

> BLUF: The current WezTerm + Neovim setup uses stock Solarized Dark with minimal
> customization, losing several UX qualities from the old tmux+VSCode workflow:
> greyscale slate backgrounds, prominent copy-mode cursor, informative status bar,
> and visually distinct pane gutters. All five desired changes are achievable with
> existing WezTerm and Neovim configuration options.

## Context / Background

Migration from tmux to WezTerm is functionally complete (smart-splits, copy mode,
workspaces), but the visual layer was carried over as-is with stock Solarized Dark.
The old setup combined a customized tmux theme with VSCode's greyscale slate palette.
This report audits the current state and identifies the gap.

## Key Findings

### Current WezTerm Styling (`dot_config/wezterm/wezterm.lua`)

| Setting | Current Value | Notes |
|---------|--------------|-------|
| `color_scheme` | `"Solarized Dark (Gogh)"` | Blue-tinted base colors (#002b36, #073642) |
| `font` | JetBrains Mono Medium, 12pt | Line height 1.2 |
| `window_background_opacity` | 0.95 | Slight transparency |
| `window_padding` | 4px all sides | Minimal |
| `window_decorations` | `"RESIZE"` | No title bar, no integrated buttons |
| `tab_bar_at_bottom` | true | Retro (non-fancy) tab bar |
| `use_fancy_tab_bar` | false | Plain text tabs |
| `tab_max_width` | (default: 16) | Not set, uses narrow default |
| Copy mode colors | (defaults) | No custom highlight colors |
| Pane split color | (defaults) | Thin 1px line, scheme default |
| Status bar | Workspace name only (fallback) | Lace plugin overrides when loaded |

**Not configured:** `inactive_pane_hsb`, `window_frame`, `tab_max_width`,
`colors.copy_mode_*`, `colors.split`, `underline_thickness`.

### Current Neovim Styling

| Component | Plugin/Setting | Notes |
|-----------|---------------|-------|
| Colorscheme | `maxmx03/solarized.nvim` (dark) | Standard solarized dark |
| Statusline | lualine.nvim, `solarized_dark` theme | Powerline separators |
| Bufferline | bufferline.nvim, thin separators | At top |
| Window separator | Default (`WinSeparator` hl group) | Thin `│` character, scheme color |
| `fillchars` | Not customized | Default vert separator character |
| Dashboard | snacks.nvim | Custom stripe fill using `#073642` |

### Legacy tmux Styling (from `dot_tmux.conf`, deleted in commit `742fd97`)

**Pane Gutter Effect:**
```
set-window-option -g window-style bg=brightblack
```
In solarized, `brightblack` maps to `#586e75` (base01). Inactive panes got this lighter
background while the active pane kept `bg=black` (`#073642` / base02). This created a
visible "gutter" between panes -- the inactive pane background itself acted as padding
around the active content.

**Pane Borders:**
```
set-option -g pane-border-style fg=black        # base02 (#073642) -- nearly invisible
set-option -g pane-active-border-style fg=brightgreen  # base01
```
Borders were subtle, relying on the background contrast rather than bright lines.

**Status Bar:**
- Position: top, 2 status lines (double-height)
- Left: date, time, battery %, session name
- Right: empty
- Active window: `bg=black,fg=default,bold`
- Inactive window: `fg=brightblue` (base0)
- Clock: green
- VSCode sessions auto-hid status bar

**Copy Mode:**
- Vi mode-keys, entered with `Alt-C`
- tmux copy mode uses a prominent yellow/highlighted cursor by default

### Legacy VSCode Greyscale Slate Palette

From `workbench.colorCustomizations` in `archive/legacy/vscode/settings.jsonc`:

| Role | Hex | Solarized Equivalent |
|------|-----|---------------------|
| Sidebar background | `#151515` | Replaces base03 (#002b36) |
| Main background | `#1c1c1c` | Replaces base03 |
| Line highlight | `#232323` | Replaces base02 (#073642) |
| Tab bar / inactive tabs | `#282828` | Replaces base02 |
| List selection | `#333333` | Replaces base01 (#586e75) |
| Selection highlight | `#b79a42` (34% opacity) | Yellow accent, muted |

This palette keeps solarized's syntax highlighting (cyan, green, yellow, etc.) but replaces
the blue-tinted backgrounds with neutral dark greys. The effect is "solarized syntax on a
slate canvas."

## Gap Analysis

| Desired Change | Current State | Feasibility |
|---------------|---------------|-------------|
| 1. Greyscale slate base | Blue solarized (#002b36) | WezTerm: custom `colors` table override. Neovim: solarized.nvim palette override or custom highlights. |
| 2. Pane divider gutter | Thin 1px default line | WezTerm: `colors.split` + `inactive_pane_hsb` for dimming. `underline_thickness` affects split line width (side effect on underlines). Neovim: `WinSeparator` hl + `fillchars`. |
| 3. Prominent copy mode | Default (subtle) | WezTerm: `colors.copy_mode_active_highlight_bg/fg` and `copy_mode_inactive_highlight_bg/fg`. Yellow cursor achievable. |
| 4. Wider tabs + status | Narrow tabs, workspace only | WezTerm: `tab_max_width`, `update-status` event for right status (clock, workspace). Retro tab bar already active. |
| 5. App border / frame | `RESIZE` (borderless) | WezTerm: `window_frame` with `border_*` settings, or `INTEGRATED_BUTTONS\|RESIZE` for title bar integration. `window_padding` increase helps too. |

## Recommendations

1. Define a shared color palette (the VSCode slate values) as constants at the top of
   `wezterm.lua` and as highlight overrides in neovim's colorscheme config.
2. Tackle changes in phases: base colors first (highest visual impact), then dividers,
   copy mode, tabs, and border.
3. Use the WezTerm validation workflow (CLAUDE.md) after each phase to catch regressions.
4. Consider whether neovim should switch to a slate-native theme (e.g., a custom
   solarized.nvim palette) or use highlight overrides on top of solarized.

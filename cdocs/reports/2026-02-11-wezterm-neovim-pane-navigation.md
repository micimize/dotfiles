---
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T21:04:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: report
state: live
status: done
tags: [wezterm, neovim, navigation, pane-management, analysis]
last_reviewed:
  status: accepted
  by: "claude-opus-4-6"
  at: 2026-02-11T21:10:00-05:00
  round: 1
---

# WezTerm + Neovim Seamless Pane Navigation: Options Analysis

> BLUF: **smart-splits.nvim** is the clear best option for seamless Ctrl+h/j/k/l navigation between WezTerm panes and Neovim splits. It is the only actively maintained solution with first-class WezTerm support, directional resizing, and a robust user-variable IPC mechanism. The current config has a keybinding collision -- WezTerm intercepts Ctrl+h/j/k/l before Neovim sees them -- that smart-splits solves with a well-established two-sided coordination pattern.

## Context / Background

### The Problem

The current dotfiles setup binds `Ctrl+h/j/k/l` in **both** WezTerm (`ActivatePaneDirection`) and Neovim (`<C-w>h/j/k/l`). WezTerm intercepts these keys first, so:

- When Neovim runs in a single WezTerm pane, `Ctrl+h/j/k/l` always navigates WezTerm panes (or does nothing if there's only one pane) instead of navigating between Neovim splits.
- When both WezTerm panes and Neovim splits exist, there is no way to seamlessly move between them. You are stuck in one world or the other.

### The tmux Precedent

This was a solved problem in the tmux era. [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) (~6,100 stars, still maintained) established the pattern:

1. **tmux side:** Detect if the foreground process is vim/nvim. If yes, forward the keystroke. If no, handle pane navigation.
2. **Vim side:** If at an edge split (no more splits in that direction), shell out to `tmux select-pane` to hand off to tmux.

This two-sided coordination creates the illusion of a single unified spatial layout -- you press Ctrl+l and focus moves right regardless of whether the next pane is a Vim split or a tmux pane.

---

## Key Findings

- **smart-splits.nvim** is the dominant solution with ~1,500 stars, active development through 2025+, and first-class WezTerm support including navigation AND resizing.
- **Navigator.nvim** has WezTerm support via a wiki page but is effectively abandoned (last release April 2022, 8 unmerged PRs).
- Several smaller plugins exist (wezterm-move.nvim, wezterm-mux.nvim) but are either archived or minimally adopted. The archived wezterm-mux.nvim explicitly recommends smart-splits as its successor.
- **No Neovim plugin can be avoided.** WezTerm can detect nvim and forward keys, but Neovim must detect edge splits and delegate back. Both sides are required.
- WezTerm's **user variable system** (`pane:get_user_vars()`) is the preferred IPC mechanism over process name detection (`pane:get_foreground_process_name()`), because it works over SSH and avoids OS process table overhead.

---

## Option 1: smart-splits.nvim (Recommended)

**GitHub:** [mrjones2014/smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim)
**Stars:** ~1,500 | **License:** MIT | **Last release:** v2.0.5 (Oct 2024), active commits through 2025+

### How It Works

**Neovim side:** The plugin sets an `IS_NVIM` user variable via WezTerm escape sequences on startup and clears it on `ExitPre`. Navigation functions detect edge splits and, when at an edge, invoke the WezTerm CLI to activate the adjacent WezTerm pane.

**WezTerm side:** An `action_callback` on each Ctrl+h/j/k/l binding checks `pane:get_user_vars().IS_NVIM`. If `'true'`, it forwards the key to Neovim via `SendKey`. If not, it calls `ActivatePaneDirection`.

### What It Provides

| Feature | Supported |
|---|---|
| Directional navigation (Ctrl+h/j/k/l) | Yes |
| Directional resizing (configurable mod) | Yes |
| Edge wrapping (wrap around to first pane) | Yes |
| Buffer swapping between splits | Yes |
| Multi-multiplexer (tmux, WezTerm, Kitty, Zellij) | Yes |
| Works over SSH | Yes (with user vars) |
| Lazy-loadable | No (must set IS_NVIM at startup) |

### Integration With Current Config

The existing keybinding scheme maps directly for navigation:

| Current Binding | Current Action | smart-splits Replacement |
|---|---|---|
| `Ctrl+h/j/k/l` | `act.ActivatePaneDirection` | Conditional: forward to nvim OR navigate WezTerm |
| `Ctrl+Alt+h/j/k/l` | `act.AdjustPaneSize` | Conditional: forward to nvim OR resize WezTerm |
| `<C-h/j/k/l>` (nvim) | `<C-w>h/j/k/l` | `smart-splits.move_cursor_*` |

### Keybinding Conflict: Alt+h/j/k/l

The smart-splits README example uses `META` (Alt) for resize, but `Alt+h/j/k/l` is already bound to **WezTerm split creation** (`SplitPane`). These cannot coexist on the same modifier.

**Recommended resolution:** Keep the existing binding scheme:
- `Ctrl+h/j/k/l` -- navigation (smart-splits conditional)
- `Ctrl+Alt+h/j/k/l` -- resize (smart-splits conditional)
- `Alt+h/j/k/l` -- WezTerm split creation (unchanged, always handled by WezTerm)

This preserves the current muscle memory for splits while adding smart-splits coordination to navigation and resize. The WezTerm-side `split_nav()` helper from the smart-splits README should use `'CTRL|ALT'` as the resize modifier instead of `'META'`.

### Known Limitations

- **Cannot lazy-load** when using WezTerm integration. The `IS_NVIM` user var must be set at startup. If lazy-loaded, the WezTerm side must fall back to `pane:get_foreground_process_name()` which is slower, does not work over SSH, and may be unreliable with nushell as the default shell (the process tree may show `nu` rather than `nvim` depending on how the query traverses child processes).
- **User vars lost on mux detach/reattach.** Tracked in [wezterm#5832](https://github.com/wezterm/wezterm/issues/5832). **This is a concrete near-term risk, not theoretical:** the current wezterm.lua already configures `unix_domains = { { name = "unix" } }` and has an auto-connect line commented out. If persistent sessions are enabled, detaching and reattaching will lose the `IS_NVIM` flag. A `FocusGained` autocmd that re-sets the user var is the likely workaround.
- **Maintainer bandwidth.** An October 2025 meta-issue called for additional maintainers.

---

## Option 2: Navigator.nvim

**GitHub:** [numToStr/Navigator.nvim](https://github.com/numToStr/Navigator.nvim)
**Stars:** ~430 | **License:** MIT | **Last release:** v0.6 (April 2022)

### How It Works

WezTerm emits custom events (`ActivatePaneDirection-left`, etc.) from keybindings. Event handlers check if vim is the foreground process. Neovim-side commands (`NavigatorLeft`, etc.) call `wezterm cli activate-pane-direction` when at an edge.

### Limitations

- **Effectively unmaintained.** 8 unmerged PRs, 6 open issues, no releases since April 2022.
- **No resize support.** Navigation only.
- **Process name detection only.** No user-var approach, so SSH/multiplexer sessions are unreliable.
- A [known bug (#20)](https://github.com/numToStr/Navigator.nvim/issues/20) with pane dimming after navigation.

### Verdict

Not recommended. The abandonment risk is too high and it lacks features smart-splits provides.

---

## Option 3: wezterm-move.nvim (Minimal Alternative)

**GitHub:** [letieu/wezterm-move.nvim](https://github.com/letieu/wezterm-move.nvim)
**Stars:** ~42 | **License:** MIT

### How It Works

~30 lines of Lua. Neovim side detects edge splits and calls `wezterm cli activate-pane-direction`. WezTerm side uses `pane:get_foreground_process_name()` to detect nvim.

### Tradeoffs

- **Pro:** Extremely minimal, easy to audit, fully lazy-loadable.
- **Con:** No resize support, no user-var detection, WezTerm-only (no tmux/kitty fallback), minimal community, no edge wrapping.

### Verdict

Viable if you want absolute minimalism and are willing to give up resize integration and robustness. For most users, smart-splits is worth the modest additional complexity.

---

## Option 4: Pure WezTerm (No Neovim Plugin)

### How It Works

WezTerm's `action_callback` checks `pane:get_foreground_process_name()` for nvim. If detected, forward `Ctrl+h/j/k/l` as `SendKey`. If not, call `ActivatePaneDirection`. No Neovim plugin needed.

### The Catch

This only solves the WezTerm-to-Neovim direction. Neovim's default `<C-w>h` at an edge split does nothing -- it cannot tell WezTerm to navigate. You get "navigation into Neovim" but not "navigation out of Neovim." This is a half-solution.

### Verdict

Insufficient for the full seamless experience. You still need Neovim-side edge detection.

---

## Option 5: Archived / Abandoned Projects

These are documented for completeness but should not be adopted:

| Plugin | Stars | Status | Notes |
|---|---|---|---|
| [jonboh/wezterm-mux.nvim](https://github.com/jonboh/wezterm-mux.nvim) | ~9 | Archived Nov 2023 | Recommends smart-splits |
| [aca/wezterm.nvim](https://github.com/aca/wezterm.nvim) | ~50 | Abandoned Dec 2021 | Required Go binary |
| [Mrngilles/nvim-wezterm-navigation](https://github.com/Mrngilles/nvim-wezterm-navigation) | ~0 | Abandoned Apr 2022 | No community adoption |

---

## Comparison Matrix

| Criterion | smart-splits | Navigator.nvim | wezterm-move | Pure WezTerm |
|---|---|---|---|---|
| Navigation | Full | Full | Full | Half (into nvim only) |
| Resizing | Yes | No | No | Separate bindings |
| IPC Method | User vars | Process name | Process name | Process name |
| SSH support | Yes | Unreliable | Unreliable | Unreliable |
| Active maintenance | Yes | No | Low | N/A |
| Stars | ~1,500 | ~430 | ~42 | N/A |
| Lazy-loadable | No | Yes | Yes | N/A |
| Config complexity | Moderate (both sides) | Moderate (both sides) | Low (both sides) | Low (WezTerm only) |
| Multi-mux support | tmux/WezTerm/Kitty/Zellij | tmux/WezTerm | WezTerm only | WezTerm only |

---

## Recommendations

1. **Adopt smart-splits.nvim.** It is the clear winner on every axis that matters: maintenance, features, IPC quality, and community adoption.

2. **Replace the current `Ctrl+h/j/k/l` and `Ctrl+Alt+h/j/k/l` bindings in both configs** with the coordinated smart-splits pattern. Specifically: `Ctrl+h/j/k/l` for conditional navigation, `Ctrl+Alt+h/j/k/l` for conditional resize, and leave `Alt+h/j/k/l` unchanged for WezTerm split creation.

3. **Do not lazy-load smart-splits.** It must set the `IS_NVIM` user variable at Neovim startup for the WezTerm side to detect it.

4. **Test the mux detach/reattach scenario** if you use `wezterm connect unix` for persistent sessions. The user-var loss on reattach ([wezterm#5832](https://github.com/wezterm/wezterm/issues/5832)) may require a workaround (e.g., an autocmd that re-sets the user var on `FocusGained`).

---

## Sources

### Primary
- [mrjones2014/smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) -- README, wiki, issues
- [christoomey/vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) -- The original pattern
- [numToStr/Navigator.nvim](https://github.com/numToStr/Navigator.nvim) -- README, WezTerm wiki page

### WezTerm Capabilities
- [WezTerm user-var-changed event](https://wezterm.org/recipes/passing-data.html)
- [WezTerm pane:get_foreground_process_name](https://wezterm.org/config/lua/pane/get_foreground_process_name.html)
- [WezTerm discussion #6184 -- Application-dependent keybindings](https://github.com/wezterm/wezterm/discussions/6184)
- [WezTerm issue #5832 -- User vars lost on mux reattach](https://github.com/wezterm/wezterm/issues/5832)

### Other Plugins Evaluated
- [letieu/wezterm-move.nvim](https://github.com/letieu/wezterm-move.nvim)
- [jonboh/wezterm-mux.nvim](https://github.com/jonboh/wezterm-mux.nvim) (archived)
- [willothy/wezterm.nvim](https://github.com/willothy/wezterm.nvim) (utilities, not navigation)
- [winter-again/wezterm-config.nvim](https://github.com/winter-again/wezterm-config.nvim) (config overrides only)
- [aca/wezterm.nvim](https://github.com/aca/wezterm.nvim) (abandoned)

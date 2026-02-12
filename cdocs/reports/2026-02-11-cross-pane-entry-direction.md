---
title: "Cross-Pane Entry Direction: Options for Directionally-Correct Split Focus"
date: 2026-02-11
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T23:55:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: report
state: live
status: done
tags: [smart-splits, wezterm, neovim, navigation, entry-direction, investigation]
---

# Cross-Pane Entry Direction: Options for Directionally-Correct Split Focus

> BLUF: No existing plugin solves the entry-direction problem out of the box. The most
> promising approach is a **WezTerm-side post-navigation fixup**: after
> `ActivatePaneDirection` lands on a Neovim pane, WezTerm sends a synthetic keypress
> (e.g. `<C-w>h` or `<C-w>l`) to force Neovim to the directionally-correct edge split.
> This requires only changes to `wezterm.lua` and no Neovim plugin modifications. A more
> robust alternative uses a custom Neovim autocommand triggered by a WezTerm user-var
> signal carrying the entry direction, but adds complexity on both sides.

## 1. Problem Statement

When navigating FROM a WezTerm terminal pane INTO a Neovim instance that has multiple
splits, focus lands on whichever Neovim split was last active -- not the one
directionally adjacent to the WezTerm pane.

### Reproduction

```
Layout: [WezTerm pane A] | [Neovim split 1] [Neovim split 2 (last focused)]

1. User is in WezTerm pane A, presses Ctrl+l (move right)
2. WezTerm action_callback: current pane is not Neovim -> ActivatePaneDirection("Right")
3. WezTerm activates the Neovim pane (the whole pane, not a specific split)
4. Neovim restores focus to split 2 (last active)
5. User expected to land in split 1 (the leftmost, closest to where they came from)
```

### Why It Happens

The problem is an abstraction mismatch. WezTerm knows about *panes* but not about
Neovim's internal *window splits*. When WezTerm activates a pane, it hands focus to the
terminal process running in that pane. Neovim then resumes with its internal cursor
position unchanged -- it has no idea focus arrived from the left.

The same problem exists (and has never been solved) for vim-tmux-navigator,
Navigator.nvim, wezterm-move.nvim, and every other cross-multiplexer navigation plugin.
They all solve *outbound* navigation (Neovim detects edge, hands off to multiplexer)
but not *inbound* navigation (multiplexer hands off to Neovim, landing on correct split).

## 2. smart-splits.nvim Capabilities

### What It Provides

- **Edge detection**: Uses `vim.fn.winnr(count .. dir_key)` to detect when the cursor
  is at the edge of the Neovim split layout. When `winnr('1l')` equals `winnr()`, there
  is no window to the right, so smart-splits hands off to the multiplexer.
- **Multiplexer handoff**: Calls `wezterm cli activate-pane-direction <dir>` to navigate
  out of Neovim into the next WezTerm pane.
- **`at_edge` configuration**: Accepts `'stop'`, `'wrap'`, `'split'`, or a **custom
  function** with a context object containing direction and multiplexer state.
- **WezTerm backend**: Communicates via `wezterm cli` commands (`get-pane-direction`,
  `activate-pane-direction`, `list --format json`).

### What It Does NOT Provide

- **No inbound direction awareness.** smart-splits has no mechanism to know which
  direction focus arrived from when Neovim gains focus.
- **No `FocusGained` handler.** The plugin does not hook into Neovim's `FocusGained`
  autocommand.
- **No API to focus a specific edge split.** There is no `focus_edge_window('left')`
  function exposed.
- **No open issues or planned features** for this problem. A search of the GitHub
  issues tracker returned zero results for entry direction, focus correction, or
  inbound navigation.

### Relevant Source (edge detection)

From `lua/smart-splits/api.lua`:

```lua
local win_to_move_to = vim.fn.winnr(vim.v.count1 .. dir_key)
local win_before = vim.v.count1 == 1
  and vim.fn.winnr()
  or vim.fn.winnr(vim.v.count1 - 1 .. dir_key)
local will_wrap = win_to_move_to == win_before
-- If will_wrap is true, we are at the edge.
```

This same `winnr()` pattern can be reused in a custom solution to find and focus edge
windows.

## 3. Alternative Plugins Assessment

### 3.1 Navigator.nvim (numToStr)

- **WezTerm support**: Yes, via wiki-documented config.
- **Entry direction handling**: No. Same inbound focus problem.
- **Maintenance**: Last release April 2022 (v0.6), 38 total commits. Effectively
  unmaintained.
- **Assessment**: No advantage over smart-splits for this problem. Less maintained.

### 3.2 wezterm-move.nvim (letieu)

- **WezTerm support**: Yes (WezTerm-specific).
- **Entry direction handling**: No. ~30 lines of code, purely a passthrough.
- **Maintenance**: Minimal codebase, unclear activity.
- **Assessment**: Too minimal. No edge detection, no multiplexer handoff from Neovim
  side.

### 3.3 wezterm-mux.nvim (jonboh)

- **WezTerm support**: Yes (WezTerm-specific).
- **Entry direction handling**: No. Same architecture as vim-tmux-navigator.
- **Maintenance**: Small project.
- **Assessment**: Similar approach to Navigator.nvim but WezTerm-specific.

### 3.4 wezterm.nvim (willothy)

- **WezTerm support**: Yes (utility library for WezTerm CLI).
- **Entry direction handling**: No, but provides useful primitives: tab management, pane
  switching, and task spawning via `wezterm cli`.
- **Maintenance**: Active.
- **Assessment**: Could be a building block for a custom solution, providing a Lua
  wrapper around `wezterm cli` commands.

### 3.5 vim-tmux-navigator (christoomey)

- **WezTerm support**: No (tmux only).
- **Entry direction handling**: No. The original plugin that established the pattern.
  Same inbound focus limitation.
- **Maintenance**: Active (~6,100 stars).
- **Assessment**: Not applicable (tmux only), but confirms this is an unsolved problem
  across the entire ecosystem.

**Summary**: No existing plugin solves inbound entry direction. This is a gap in the
entire Neovim + terminal multiplexer navigation ecosystem.

## 4. Solution Approaches

### 4.1 WezTerm-Side Post-Navigation Fixup (Recommended)

**Concept**: After `ActivatePaneDirection` lands on a Neovim pane, immediately send a
keypress to Neovim that forces focus to the directionally-correct edge split.

**How it works**:

1. Before activating, use `tab:get_pane_direction(dir)` to peek at the target pane.
2. Check if the target pane is Neovim (via `user_vars.IS_NVIM`).
3. If yes, activate the pane, then send a "move to edge" keypress.
4. The edge keypress uses Neovim's `<C-w>` commands with a large count to slam focus
   to the correct edge (e.g., `999<C-w>h` for entering from the left).

**Implementation**:

```lua
-- In wezterm.lua, replace the split_nav move handler:
local function split_nav(resize_or_move, key)
  local mods = resize_or_move == "resize" and "CTRL|ALT" or "CTRL"
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        -- Current pane is Neovim: forward the key to smart-splits
        win:perform_action({ SendKey = { key = key, mods = mods } }, pane)
      else
        if resize_or_move == "resize" then
          win:perform_action({ AdjustPaneSize = { direction_keys[key], 5 } }, pane)
        else
          -- Moving from non-Neovim pane. Check what is in that direction.
          local tab = win:active_tab()
          local target_pane = tab:get_pane_direction(direction_keys[key])

          -- Activate the target pane
          win:perform_action(
            { ActivatePaneDirection = direction_keys[key] }, pane)

          -- If the target is Neovim, send edge-focus keypress
          if target_pane
            and target_pane:get_user_vars().IS_NVIM == "true"
          then
            -- Navigating right (key="l") means we entered from the left,
            -- so focus the LEFTMOST Neovim split (wincmd h).
            local opposite = {
              h = "l",  -- navigating left  -> entered from right -> rightmost
              l = "h",  -- navigating right -> entered from left  -> leftmost
              k = "j",  -- navigating up    -> entered from below -> bottommost
              j = "k",  -- navigating down  -> entered from above -> topmost
            }
            local wincmd_key = opposite[key]

            -- Send Escape (ensure normal mode), then 999<C-w>{dir}.
            -- The count of 999 slams focus to the edge; wincmd stops
            -- at the boundary so overshooting is harmless.
            win:perform_action(
              act.Multiple({
                { SendKey = { key = "Escape" } },
                { SendKey = { key = "9" } },
                { SendKey = { key = "9" } },
                { SendKey = { key = "9" } },
                { SendKey = { key = "w", mods = "CTRL" } },
                { SendKey = { key = wincmd_key } },
              }),
              target_pane
            )
          end
        end
      end
    end),
  }
end
```

**Timing concern**: `ActivatePaneDirection` and the subsequent `SendKey` calls happen
within the same `action_callback`. WezTerm actions via `perform_action` are synchronous
within the callback, so the pane activation completes before the `SendKey` calls. The
`SendKey` calls target `target_pane` (the Neovim pane), which is now the active pane.

**Caveats**:

- **Mode disruption**: The `Escape` + `<C-w>` sequence will exit insert mode if the
  user was typing. This is acceptable because pane navigation typically happens in
  normal mode, and the user was in a different WezTerm pane (not in Neovim) before
  this action.
- **Visual flash**: Neovim may briefly show the last-active split before jumping to the
  edge. This should be imperceptible (sub-frame).
- **Count prefix**: `999<C-w>h` is a blunt instrument. It works because `<C-w>h` stops
  at the edge; repeating past the edge is a no-op.
- **Non-split Neovim**: If Neovim has only one window (no splits), the `<C-w>h`
  sequence is a no-op, which is correct.
- **Special windows**: Sidebar plugins (neo-tree, snacks explorer) may catch the edge
  focus. The user would land on the sidebar rather than the "main" editing split.
  This is arguably correct (it IS the edge window) but may not be desired.

**Advantages**:

- Zero changes to Neovim config.
- Zero new plugins or dependencies.
- Uses only stable WezTerm APIs (`get_pane_direction`, `get_user_vars`, `SendKey`).
- Degrades gracefully: if `IS_NVIM` is not set, behaves like standard navigation.

### 4.2 Simplified WezTerm-Side: Use `<C-w>t`/`<C-w>b` Idiom

Instead of `999<C-w>h`, Neovim has dedicated "go to top-left window" and "go to
bottom-right window" commands:

- `<C-w>t` -- focus the top-left window
- `<C-w>b` -- focus the bottom-right window

These are closer to what we want for vertical arrangements but do not map cleanly to
all four directions. For a layout like:

```
[WezTerm] | [NV1 (left)] [NV2 (right)]
```

Entering from the left, we want NV1. `<C-w>t` gives us the top-left window, which
may or may not be NV1 depending on the overall layout.

**Assessment**: Too imprecise for general use. The `999<C-w>{dir}` approach is more
reliable.

### 4.3 User-Var Signal + Neovim Autocommand (Most Robust)

**Concept**: WezTerm signals the entry direction to Neovim via a user variable or
injected escape sequence. A Neovim autocommand reads the signal and focuses the correct
edge split.

**WezTerm side**:

```lua
-- In the action_callback, after ActivatePaneDirection:
if target_pane:get_user_vars().IS_NVIM == "true" then
  -- Inject an OSC 1337 SetUserVar to signal the entry direction.
  -- This goes to the OUTPUT side of the pane, so Neovim's terminal
  -- emulator processes it. But Neovim is not a terminal emulator --
  -- it's a TUI app. The escape sequence would appear as garbage.
  -- THIS APPROACH DOES NOT WORK for Neovim.
end
```

**Problem**: `inject_output` sends to the terminal emulator's output stream, which is
processed by WezTerm's own terminal emulation layer for that pane. Neovim, running as
a TUI application inside the pane, receives input from stdin, not from the terminal's
output stream. So `inject_output` of an OSC 1337 would be processed by WezTerm itself
(setting a user var on the pane), not by Neovim.

**Revised approach using `send_paste`**:

```lua
-- WezTerm side: send a special command string to Neovim's stdin
if target_pane:get_user_vars().IS_NVIM == "true" then
  local dir = direction_keys[key]  -- "Left", "Right", "Up", "Down"
  -- Send a Neovim command via stdin using feedkeys.
  -- We need to enter command mode and run a Lua function.
  -- Use --no-paste equivalent: send raw keystrokes.
  win:perform_action(act.Multiple({
    { SendKey = { key = "Escape" } },
    { SendKey = { key = ":" } },
  }), target_pane)
  -- Then type the lua command
  target_pane:send_paste("lua require('edge-focus').focus('" .. dir .. "')")
  win:perform_action(
    { SendKey = { key = "Enter" } }, target_pane)
end
```

**Neovim side** (`lua/edge-focus.lua`):

```lua
local M = {}

--- Focus the edge window in the given direction.
--- @param direction string "Left"|"Right"|"Up"|"Down"
function M.focus(direction)
  local dir_map = {
    Left  = "h",
    Right = "l",
    Up    = "k",
    Down  = "j",
  }
  -- To find the edge on the side we ENTERED from, we go to the OPPOSITE edge.
  -- Entering from the left (direction=Right) means go to the leftmost split (h).
  local opposite_map = {
    Left  = "l",  -- entered from right side
    Right = "h",  -- entered from left side
    Up    = "j",  -- entered from bottom
    Down  = "k",  -- entered from top
  }
  local wincmd = opposite_map[direction]
  if wincmd then
    vim.cmd("999wincmd " .. wincmd)
  end
end

return M
```

**Assessment**: More extensible (the Neovim module can do smarter things than raw
`wincmd`), but the `send_paste` + command-line injection approach is fragile:

- It visibly flashes the command line.
- It can interfere with user input if timing overlaps.
- It requires Neovim to be in a state where `:` enters command mode (not in a prompt,
  not in a terminal buffer, etc.).

### 4.4 Custom Neovim Keymap as Entry Point (Cleanest)

**Concept**: Define a dedicated "enter from direction" keymap in Neovim that WezTerm
sends instead of relying on `ActivatePaneDirection` + post-fixup.

**Neovim side**:

```lua
-- In navigation.lua or a dedicated module
-- These keymaps are NOT for the user to press. They are synthetic keymaps
-- that WezTerm sends after activating the Neovim pane.
local function focus_edge(dir)
  -- Map entry direction to the wincmd for the edge on the entry side.
  -- "from_left" means focus came from the left, so focus the leftmost split.
  local wincmd_map = {
    from_left  = "h",
    from_right = "l",
    from_above = "k",
    from_below = "j",
  }
  local wincmd = wincmd_map[dir]
  if wincmd then
    vim.cmd("999wincmd " .. wincmd)
  end
end

-- Use unlikely key combinations that won't conflict with normal usage.
-- These are "protocol" keys between WezTerm and Neovim.
vim.keymap.set("n", "<C-\\><C-h>", function() focus_edge("from_left") end,
  { desc = "Entry focus: from left" })
vim.keymap.set("n", "<C-\\><C-l>", function() focus_edge("from_right") end,
  { desc = "Entry focus: from right" })
vim.keymap.set("n", "<C-\\><C-k>", function() focus_edge("from_above") end,
  { desc = "Entry focus: from above" })
vim.keymap.set("n", "<C-\\><C-j>", function() focus_edge("from_below") end,
  { desc = "Entry focus: from below" })
```

**WezTerm side**:

```lua
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
          local tab = win:active_tab()
          local target = tab:get_pane_direction(direction_keys[key])

          -- Navigate to the target pane
          win:perform_action(
            { ActivatePaneDirection = direction_keys[key] }, pane)

          -- If target is Neovim, send the entry-direction protocol key
          if target and target:get_user_vars().IS_NVIM == "true" then
            -- Send Escape to ensure normal mode, then the protocol sequence
            win:perform_action(act.Multiple({
              { SendKey = { key = "Escape" } },
              { SendKey = { key = "\\", mods = "CTRL" } },
              { SendKey = { key = key, mods = "CTRL" } },
            }), target)
          end
        end
      end
    end),
  }
end
```

**Advantages**:

- Clean separation: WezTerm sends a well-defined signal, Neovim interprets it.
- No visible command-line flash.
- The Neovim handler can be arbitrarily smart (skip sidebars, handle floating windows,
  respect locked splits, etc.).
- The protocol keys (`<C-\><C-h>` etc.) are in the "unused" keyspace -- `<C-\>` is
  traditionally reserved for terminal escape and rarely bound in Neovim.
- Works regardless of Neovim's current mode (the `Escape` ensures normal mode first).

**Disadvantages**:

- Requires changes on both sides (WezTerm + Neovim).
- The `Escape` key may dismiss popups, close floating windows, or exit visual mode.
  This is the same tradeoff as approach 4.1 and is acceptable for the same reason:
  the user is entering Neovim from an external pane, not actively editing.
- The protocol keymaps must never be bound to anything else.

### 4.5 FocusGained + WezTerm CLI Query (Neovim-Only)

**Concept**: On `FocusGained`, Neovim queries WezTerm's pane layout via `wezterm cli`
to infer the entry direction, then focuses the correct edge split.

**Implementation**:

```lua
-- Neovim autocommand
vim.api.nvim_create_autocmd("FocusGained", {
  callback = function()
    -- Only act if there are multiple windows
    if #vim.api.nvim_list_wins() <= 1 then return end

    -- Query WezTerm for the pane layout
    local result = vim.fn.system("wezterm cli list --format json")
    local ok, panes = pcall(vim.json.decode, result)
    if not ok then return end

    -- Find our pane and the previously active pane
    local my_pane_id = tonumber(os.getenv("WEZTERM_PANE"))
    -- Problem: WEZTERM_PANE gives us our pane ID, but we don't know
    -- which pane was previously active or which direction focus came from.
    -- The `list` output shows is_active but not "previously active".

    -- Alternative: use pane geometry to infer adjacency
    -- This requires knowing which pane was focused before us, which
    -- WezTerm's CLI does not expose.
  end,
})
```

**Assessment**: This approach **does not work** as designed. The fundamental problem is
that `FocusGained` fires after the focus change is complete, and WezTerm's CLI does not
expose "which pane was previously focused" or "which direction the focus change came
from." The `wezterm cli list` output shows current state only, not history.

One could work around this by having WezTerm set a user var (e.g.,
`ENTRY_DIRECTION=Left`) on the Neovim pane before activating it, then reading it in
the `FocusGained` handler. But that brings us back to approach 4.3 with the added
complexity of `FocusGained` timing.

### 4.6 smart-splits Custom `at_edge` Handler (Outbound Only)

It is worth noting that smart-splits' custom `at_edge` function provides a context
object with the multiplexer and direction:

```lua
opts = {
  at_edge = function(ctx)
    -- ctx.direction: 'left'|'right'|'up'|'down'
    -- ctx.mux: multiplexer object with WezTerm CLI methods
    -- ctx.mux:current_pane_at_edge(direction): boolean
    -- ctx.mux:next_pane(direction): navigate to next pane
    -- ctx.split(): create a new split
    -- ctx.wrap(): wrap to opposite side
  end,
}
```

This is powerful for **outbound** navigation (Neovim to WezTerm) but does not help with
**inbound** navigation (WezTerm to Neovim). When focus arrives at Neovim from WezTerm,
smart-splits' `at_edge` is not invoked because smart-splits is not the one initiating
the navigation.

## 5. Comparison Matrix

| Approach | Changes Needed | Robustness | Complexity | Visible Side Effects |
|---|---|---|---|---|
| 4.1 Post-nav `999<C-w>` | WezTerm only | Good | Low | None (sub-frame) |
| 4.2 `<C-w>t`/`<C-w>b` | WezTerm only | Poor | Low | None |
| 4.3 User-var signal | Both sides | Fair | High | Command-line flash |
| **4.4 Protocol keymap** | **Both sides** | **Best** | **Medium** | **None** |
| 4.5 FocusGained query | Neovim only | Broken | High | N/A |
| 4.6 smart-splits at_edge | N/A | N/A (outbound) | N/A | N/A |

## 6. Recommendation

**Start with Approach 4.1** (WezTerm-side `999<C-w>{dir}`) for immediate results with
minimal changes. It requires editing only `wezterm.lua` and has no Neovim-side
dependencies.

**Graduate to Approach 4.4** (protocol keymap) if any of these arise:

- Sidebar plugins (neo-tree, snacks explorer) interfere with the edge-focus behavior
  and you want to skip them.
- You need the Neovim handler to do something smarter than raw `wincmd` (e.g., focus
  the nearest *file-editing* window, not any window).
- The `Escape` + `999<C-w>` sequence causes problems in specific edge cases.

Approach 4.4 is the architecturally cleanest solution. It establishes a clear protocol
between WezTerm and Neovim, is invisible to the user, and allows the Neovim side to
evolve independently.

### Suggested Implementation Plan

1. **Phase 1**: Implement approach 4.1 in `wezterm.lua`. Test with single-split and
   multi-split Neovim layouts. Verify no regressions in non-Neovim pane navigation.
2. **Phase 2**: If Phase 1 works well, optionally implement approach 4.4 by adding the
   protocol keymaps in Neovim and switching WezTerm to send those instead of raw
   `999<C-w>`.
3. **Phase 3** (optional): File a feature request on smart-splits.nvim proposing an
   `on_entry` callback or `FocusGained` handler that receives direction context. If
   accepted, this would be the ideal long-term solution.

## 7. Key WezTerm APIs Referenced

| API | Purpose | Docs |
|---|---|---|
| `tab:get_pane_direction(dir)` | Look ahead at adjacent pane | [MuxTab/get_pane_direction](https://wezterm.org/config/lua/MuxTab/get_pane_direction.html) |
| `pane:get_user_vars()` | Check IS_NVIM flag | [pane/get_user_vars](https://wezterm.org/config/lua/pane/get_user_vars.html) |
| `window:perform_action(SendKey, pane)` | Send keystrokes to specific pane | [keyassignment/SendKey](https://wezterm.org/config/lua/keyassignment/SendKey.html) |
| `pane:inject_output(text)` | Inject escape sequences (local panes only) | [pane/inject_output](https://wezterm.org/config/lua/pane/inject_output.html) |
| `pane:send_paste(text)` | Send text as if pasted | [pane/send_paste](https://wezterm.org/config/lua/pane/send_paste.html) |
| `tab:panes_with_info()` | Get all pane positions and sizes | [MuxTab/panes_with_info](https://wezterm.org/config/lua/MuxTab/panes_with_info.html) |

## 8. Key Neovim APIs Referenced

| API | Purpose |
|---|---|
| `vim.fn.winnr('1h')` | Get window number in direction (edge detection) |
| `vim.cmd('999wincmd h')` | Move to leftmost window |
| `vim.api.nvim_list_wins()` | List all window IDs |
| `vim.api.nvim_win_get_position(win)` | Get `[row, col]` position of window |
| `vim.fn.winlayout()` | Get tree structure of window layout |
| `FocusGained` autocommand | Fires when terminal pane gains focus |

## Sources

- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) -- primary
  navigation plugin, README and source code reviewed
- [WezTerm issue #2374](https://github.com/wezterm/wezterm/issues/2374) -- ambiguous
  direction resolution for ActivatePaneDirection (fixed with recency-based selection)
- [Navigator.nvim](https://github.com/numToStr/Navigator.nvim) -- alternative plugin,
  WezTerm wiki integration reviewed
- [wezterm-move.nvim](https://github.com/letieu/wezterm-move.nvim) -- minimal
  alternative, source reviewed
- [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) -- original
  pattern for cross-multiplexer navigation
- [WezTerm passing data recipes](https://wezterm.org/recipes/passing-data.html) --
  user vars mechanism documentation
- [wezterm.nvim (willothy)](https://github.com/willothy/wezterm.nvim) -- WezTerm
  utility library for Neovim
- [WezTerm Discussion #4067](https://github.com/wezterm/wezterm/discussions/4067) --
  seamless pane/window navigation discussion

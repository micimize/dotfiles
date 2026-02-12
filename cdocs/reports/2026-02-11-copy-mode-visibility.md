---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-11T18:30:00-08:00"
task_list: styling/copy-mode
type: report
state: archived
status: complete
tags: [investigation, styling, wezterm, copy-mode, ux, modal-state]
---

# Copy Mode Visibility: Approaches Beyond Cursor Color

> BLUF: WezTerm's copy mode cursor uses the same `cursor_bg`/`cursor_fg` as normal
> mode -- there is no separate copy-mode cursor color. However, three powerful runtime
> APIs (`window:active_key_table()`, `window:set_config_overrides()`, and
> `set_left/right_status()`) combine to enable dynamic, multi-layered mode indication
> that surpasses the old tmux yellow cursor. The recommended approach is a combination
> of a bold status bar indicator, dynamic window border color, and tab title annotation
> -- all driven from a single `update-status` event handler.

## Context / Background

The slate theme proposal (see `cdocs/proposals/2026-02-11-slate-terminal-theme.md`,
Phase 3) originally planned to use `copy_mode_active_highlight_bg` set to yellow for
copy mode visibility. On closer investigation, those settings only affect **search
match highlights within copy mode** -- not the cursor itself. The cursor in copy mode
is the same block cursor used in normal mode, styled by `cursor_bg`/`cursor_fg`.

This means the original Phase 3 approach produces a yellow highlight only when the user
searches for text in copy mode. Simply entering copy mode (Alt+C) with no selection or
search produces **no visible difference** from normal mode beyond a "Copy Mode:" prefix
in the tab title that's easy to miss in a busy tab bar.

The old tmux setup had a prominent yellow cursor in copy mode that was immediately
obvious. We need to find alternative approaches that achieve the same "at a glance"
recognizability.

## Key Findings

### WezTerm's Runtime APIs for Mode Detection

- **`window:active_key_table()`**: Returns `"copy_mode"` or `"search_mode"` when
  those key tables are active, `nil` otherwise. Queryable from any event handler.

- **`window:set_config_overrides()`**: Can dynamically change almost any config
  property at runtime -- including `window_frame` border colors, `window_background_opacity`,
  colors table entries, and more. Changes take effect immediately.

- **`set_left_status()` / `set_right_status()`**: Rich text formatting via
  `wezterm.format()` supports colors, bold, italic, underline, and nerd font icons.

- **`update-status` event**: Fires periodically (frequency controlled by
  `status_update_interval`, default ~1s). Can query `active_key_table()` and update
  all visual indicators from a single handler. The event fires on mode changes as well
  as periodically.

- **`format-tab-title` event**: Receives tab/pane info; WezTerm automatically prepends
  "Copy Mode:" to `pane:get_title()` when copy mode is active. Can be used to restyle
  the active tab.

### What Other Tools Do

**Tmux**: Changes the entire status bar background color when in copy mode via
conditional formatting (`#{?pane_in_mode,...}`). The `tmux-mode-indicator` plugin adds
bold colored labels. Some configs change pane border colors dynamically.

**Zellij**: Always-visible bottom bar shows current mode name AND available keybindings
for that mode. The design philosophy is "never have to guess" -- the interface is
self-documenting at all times.

**Community WezTerm configs**: `modal.wezterm`, `wezterm-status`, and `sravioli/wezterm`
all use status bar indicators with nerd font icons and contrasting background colors.
The common pattern is icon + mode name + colored background in the right status area.

### Limitations and Gotchas

- **`update-status` timing**: There may be a brief delay (~1 status update interval)
  between entering copy mode and the visual change appearing. In practice this is
  sub-second and not perceptible.

- **Bug #5318**: `set_config_overrides()` called during key table transitions can
  interfere with the active key table under certain conditions. Calling it from
  `update-status` (which fires after the transition completes) avoids this.

- **Window-scoped**: Copy mode is per-pane but visual overrides are per-window. If
  you have multiple panes and enter copy mode in one, the entire window's border/status
  changes. This is actually desirable -- it makes the mode change more visible.

- **No per-pane styling**: `inactive_pane_hsb` is global. There's no API to dim or
  highlight individual panes differently (tracked in wezterm issue #5330).

## Approach Catalog

### Approach 1: Status Bar Mode Indicator

**Mechanism**: `update-status` handler checks `active_key_table()`, updates right
status with a bold colored label.

**Appearance**: A bright yellow-on-black or black-on-yellow badge reading `COPY` in
the right status area. Optionally includes a nerd font icon (e.g., `󰆐` for clipboard).
Could also show available keybindings (Zellij-style).

**Pros**:
- Always visible regardless of terminal content
- Zero configuration complexity
- Natural integration with the slate proposal's planned `update-status` handler
- Can extend to search mode, leader key pending, etc.

**Cons**:
- Located at the bottom edge of the screen; may not catch peripheral vision if focus
  is on content mid-screen
- Competes for space with clock/workspace info

**Feasibility**: High. ~10 lines of Lua in the existing `update-status` handler.

### Approach 2: Dynamic Window Border Color

**Mechanism**: `set_config_overrides()` changes `window_frame` border colors when
copy mode is active. Border shifts from the default dark slate (`#151515`) to a
signal color (yellow `#b58900` or orange `#cb4b16`).

**Appearance**: The entire window border becomes a warm signal color. Creates a
peripheral "frame" visible even when focus is on content.

**Pros**:
- Visible from peripheral vision -- the whole window edge lights up
- Works naturally with the slate proposal's planned `window_frame` borders
- Very "tmux-like" in feel -- the environment itself changes, not just a label

**Cons**:
- The entire window changes, which may feel heavy if copy mode is entered often
  for quick yanks
- `window_frame` override must include all border dimensions (not just colors),
  or it resets to defaults

**Feasibility**: High. ~10 lines of Lua. Must re-specify border widths in the
override to avoid losing them.

### Approach 3: Dynamic Background Opacity

**Mechanism**: `set_config_overrides()` changes `window_background_opacity` from
0.95 to 1.0 (or lower to e.g. 0.85) when copy mode is active.

**Appearance**: The terminal becomes fully opaque or slightly more transparent,
creating a subtle "feel" change.

**Pros**:
- Subtle, ambient indicator
- No screen space used

**Cons**:
- Very subtle -- may not meet the "immediately obvious" requirement
- The 5% opacity change from 0.95 to 1.0 is barely perceptible
- Lowering opacity might hurt readability

**Feasibility**: High but low value. Not recommended as a primary indicator.

### Approach 4: Tab Title Annotation

**Mechanism**: `format-tab-title` handler detects "Copy Mode:" prefix in
`pane:get_title()` and changes the active tab's background color.

**Appearance**: The active tab changes from the normal slate background to a
signal color (yellow/orange).

**Pros**:
- Visible in the tab bar, complementary to status bar indicator
- Provides redundant signal via a different visual channel

**Cons**:
- Relies on WezTerm's internal title prefixing behavior
- Tab bar is at the bottom; similar location to status bar indicator

**Feasibility**: Medium. Requires a `format-tab-title` handler which adds some
complexity.

### Approach 5: Combined Status + Border (Recommended)

**Mechanism**: A single `update-status` handler that:
1. Checks `active_key_table()`
2. Updates right status with a mode badge (approach 1)
3. Sets config overrides for border color (approach 2)
4. Optionally updates left status to prepend a mode prefix

**Appearance**: When copy mode activates:
- Right status shows `  COPY ` on a yellow background
- Window border shifts to yellow
- When copy mode exits, everything returns to normal

**Pros**:
- Multiple redundant signals across different visual areas
- Both peripheral (border) and focal (status bar) indicators
- Single handler, simple implementation
- Directly integrates with the slate proposal's planned status bar and border features
- Can be extended to indicate search mode, leader key state, etc.

**Cons**:
- Must handle the `window_frame` override carefully (re-specify all dimensions)
- Slightly more visual "weight" than a single indicator

**Feasibility**: High. ~20 lines of Lua total.

### Approach 6: Zellij-Style Keybinding Display

**Mechanism**: When copy mode is active, replace the normal status bar content
entirely with a keybinding reference showing the most common copy mode actions.

**Appearance**: Normal status shows `workspace | clock`. Copy mode replaces it
with something like: `COPY  y=yank  v=visual  /=search  q=quit`

**Pros**:
- Self-documenting -- no need to memorize keybindings
- Maximally informative use of the status area
- Addresses both visibility and discoverability

**Cons**:
- Loses workspace/clock info while in copy mode
- More complex handler logic
- May feel cluttered for experienced users

**Feasibility**: High. Compatible with approach 5 (could show keybindings in left
status, mode badge in right status).

## Recommendations

### Primary: Approach 5 (Combined Status + Border)

This provides the strongest visibility with the cleanest integration into the existing
slate proposal. The border color change gives peripheral awareness (replacing the old
tmux yellow cursor's "the whole mode feels different" quality), while the status badge
gives explicit confirmation.

### Enhancement: Borrow from Approach 6

Show abbreviated keybindings in the mode badge or left status during copy mode.
Something like `  COPY  y yank  /search  Esc quit` keeps it compact while being
self-documenting. This is especially valuable because WezTerm copy mode keybindings
are customized and not obvious to recall.

### Implementation Sketch

```lua
wezterm.on("update-status", function(window, pane)
  local key_table = window:active_key_table()
  local is_copy = key_table == "copy_mode"
  local is_search = key_table == "search_mode"

  -- Dynamic border color
  local overrides = window:get_config_overrides() or {}
  if is_copy or is_search then
    overrides.window_frame = {
      border_left_width = "4px", border_right_width = "4px",
      border_bottom_height = "4px", border_top_height = "4px",
      border_left_color = slate.yellow, border_right_color = slate.yellow,
      border_bottom_color = slate.yellow, border_top_color = slate.yellow,
    }
  else
    overrides.window_frame = nil  -- falls back to config default (slate.bg_deep)
  end
  window:set_config_overrides(overrides)

  -- Right status: mode badge
  local right = ""
  if is_copy then
    right = wezterm.format({
      { Background = { Color = slate.yellow } },
      { Foreground = { Color = slate.bg } },
      { Attribute = { Intensity = "Bold" } },
      { Text = " 󰆐 COPY " },
    })
  elseif is_search then
    right = wezterm.format({
      { Background = { Color = slate.blue } },
      { Foreground = { Color = slate.bg } },
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

  -- Left status: workspace (always shown)
  window:set_left_status(wezterm.format({
    { Background = { Color = slate.bg_deep } },
    { Foreground = { Color = slate.cyan } },
    { Text = "  " .. window:active_workspace() .. " " },
    { Foreground = { Color = slate.fg_dim } },
    { Text = " " },
  }))
end)
```

### Integration with Slate Proposal

This approach supersedes the original Phase 3 and merges with Phase 4. Rather than
three separate pieces (Phase 3 copy mode colors + Phase 4 status bar + Phase 5
border), they become a unified "status + mode indication" implementation:

1. **Phase 3 original scope** (copy mode highlight colors) stays -- yellow search
   highlights are still useful. But the headline feature becomes the combined
   status/border indicator.
2. **Phase 4** (tab bar + status) merges with the mode indicator -- the
   `update-status` handler handles both workspace/clock display and mode indication.
3. **Phase 5** (window border) is needed earlier since the border is the canvas for
   the mode indication. Move border setup to Phase 1 or 3.

### Possible Refinement: `status_update_interval`

If the default polling interval causes a perceptible delay between entering copy mode
and seeing the visual change, set:

```lua
config.status_update_interval = 200  -- milliseconds, default is ~1000
```

This makes the visual transition near-instant at negligible performance cost.

## Iterative Testing Plan

WezTerm has no headless GUI testing capability. `wezterm cli send-text` goes to the
PTY, not the key binding layer, so there is no way to programmatically trigger
`ActivateCopyMode` from outside the process. `wezterm cli list --format json` does
not expose `active_key_table` or `config_overrides`. This means mode-switching visual
behavior **requires manual verification** at certain stages.

The plan below maximizes automated coverage and structures the manual steps into a
repeatable checklist. Each layer catches a different class of failure.

### Layer 0: Baseline Capture (Before Any Changes)

Run once before implementation begins. These snapshots are the reference for
detecting silent regressions throughout all phases.

```bash
# Capture current key tables
wezterm show-keys --lua > /tmp/wez_keys_before.lua
wezterm show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_before.lua
wezterm show-keys --lua --key-table search_mode > /tmp/wez_search_mode_before.lua

# Capture current tab bar state (for visual diff later)
wezterm cli list --format json > /tmp/wez_list_before.json
```

### Layer 1: Static Config Validation (Automated, After Every Edit)

This catches syntax errors, invalid enum variants, and config parse failures.
Run after every edit to `wezterm.lua`, before deploying.

```bash
# Step 1: Lua syntax check (fast, catches typos before wezterm even loads)
luac -p dot_config/wezterm/wezterm.lua \
  && echo "PASS: syntax" || echo "FAIL: syntax"

# Step 2: Full config evaluation via ls-fonts stderr
wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts \
  2>/tmp/wez_stderr.txt 1>/dev/null
if grep -qi 'error\|panic\|traceback' /tmp/wez_stderr.txt; then
  echo "FAIL: config evaluation"
  cat /tmp/wez_stderr.txt
else
  echo "PASS: config evaluation"
fi

# Step 3: Verify key tables are not silently dropped
wezterm --config-file dot_config/wezterm/wezterm.lua \
  show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_after.lua
if diff -q /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_after.lua > /dev/null; then
  echo "PASS: copy_mode table unchanged"
else
  echo "INFO: copy_mode table changed (review diff)"
  diff /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_after.lua
fi

# Step 4: Verify main key bindings preserved
wezterm --config-file dot_config/wezterm/wezterm.lua \
  show-keys --lua > /tmp/wez_keys_after.lua
diff /tmp/wez_keys_before.lua /tmp/wez_keys_after.lua
```

**What this catches**: Syntax errors, invalid CopyMode variants in `act.Multiple`,
nil references, plugin load failures, accidental key binding drops.

**What this misses**: Logic errors in `update-status` handler (the handler body is
syntactically valid Lua but may not produce correct visual output). Also misses
errors inside `wezterm.action_callback` closures (validated at key-press time only).

### Layer 2: Handler Instrumentation (Temporary, Remove After Validation)

Add diagnostic logging to the `update-status` handler during development. This lets
you confirm the handler fires, detects mode correctly, and applies overrides --
without relying on visual inspection alone.

```lua
-- Add these lines at the TOP of the update-status handler body (temporary)
local diag_mode = key_table or "normal"
wezterm.log_info("update-status: mode=" .. diag_mode)
if is_copy then
  wezterm.log_info("update-status: applying copy_mode overrides")
end
```

After deploying, enter copy mode manually (Alt+C), wait 1s, then check:

```bash
# Check the latest GUI log for handler output
LATEST_LOG=$(ls -t /run/user/1000/wezterm/wezterm-gui-log-*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
  grep "update-status:" "$LATEST_LOG" | tail -10
fi
```

**Expected output when entering copy mode:**
```
update-status: mode=copy_mode
update-status: applying copy_mode overrides
```

**Expected output after exiting:**
```
update-status: mode=normal
```

If "mode=copy_mode" never appears, the handler is either not registered, not firing,
or `active_key_table()` is not returning the expected value.

**Important**: Remove diagnostic logging before final commit. The `update-status`
handler fires frequently and log spam will affect performance.

### Layer 3: Deploy + Hot-Reload Validation (Automated)

Run after Layer 1 passes. Deploys the config and checks for hot-reload errors.

```bash
# Deploy
chezmoi apply --force

# Wait for hot-reload
sleep 3

# Check for errors in latest GUI process log
LATEST_LOG=$(ls -t /run/user/1000/wezterm/wezterm-gui-log-*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
  if grep -qi 'error.*lua\|failed to apply\|traceback' "$LATEST_LOG" | tail -5; then
    echo "FAIL: hot-reload errors detected"
  else
    echo "PASS: no hot-reload errors"
  fi
fi

# Healthcheck: wezterm mux is responsive
if wezterm cli list > /dev/null 2>&1; then
  echo "PASS: mux responsive"
else
  echo "FAIL: mux unresponsive (config may have crashed)"
fi
```

**What this catches**: Runtime errors that occur when the `update-status` handler
fires for the first time after hot-reload. Also catches config evaluation failures
that cause wezterm to fall back to defaults.

### Layer 4: Title-Based Mode Detection (Semi-Automated)

WezTerm prepends "Copy Mode:" to the pane/window title when copy mode is active.
This IS visible in `wezterm cli list --format json`. While you must enter copy mode
manually, you can verify the state programmatically afterward.

```bash
# 1. Manually press Alt+C to enter copy mode, then run:
wezterm cli list --format json | python3 -c "
import json, sys
panes = json.load(sys.stdin)
active = [p for p in panes if p.get('is_active')]
if not active:
    print('FAIL: no active pane found')
elif 'Copy Mode:' in active[0].get('title', ''):
    print('PASS: copy mode detected in active pane title')
    print('  title:', active[0]['title'])
else:
    print('INFO: copy mode NOT detected in title (may not be in copy mode)')
    print('  title:', active[0]['title'])
"

# 2. Press Escape to exit copy mode, then run the same command again:
# Should now show INFO (no copy mode prefix)
```

**What this catches**: Confirms that WezTerm itself recognizes the copy mode state.
If the title shows "Copy Mode:" but the visual indicators don't appear, the bug is
in the `update-status` handler logic. If the title does NOT show "Copy Mode:", the
issue is that copy mode didn't actually activate (binding problem).

### Layer 5: Manual Visual Verification Checklist

Run through this checklist after Layers 1-4 pass. Each item is a discrete visual
assertion. Mark pass/fail for each.

#### 5a. Copy Mode Entry (Alt+C)

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Press Alt+C | Copy mode activates | |
| 2 | Right status area | Shows ` 󰆐 COPY ` badge on yellow background | |
| 3 | Window border | Changes to yellow/signal color | |
| 4 | Cursor | Block cursor visible, can move with h/j/k/l | |
| 5 | Left status area | Still shows workspace name | |

#### 5b. Copy Mode Exit (Escape)

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Press Escape | Copy mode exits | |
| 2 | Right status area | Badge disappears, shows clock | |
| 3 | Window border | Reverts to default slate color | |
| 4 | Left status area | Still shows workspace name | |

#### 5c. Search Mode (Enter copy mode, then press /)

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Alt+C then / | Search prompt appears | |
| 2 | Right status area | Shows `  SEARCH ` badge on blue background | |
| 3 | Window border | Yellow (or blue, depending on design choice) | |
| 4 | Press Escape (exit search) | Reverts to copy mode indicators | |
| 5 | Press Escape again (exit copy) | Reverts to normal indicators | |

#### 5d. Multi-Pane Scenario

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Split pane (Alt+L) | Two panes visible | |
| 2 | Enter copy mode in left pane (Alt+C) | Copy mode active in left pane | |
| 3 | Window border | Yellow (window-level, covers both panes) | |
| 4 | Right status | Shows COPY badge | |
| 5 | Navigate to right pane (Ctrl+L) | Copy mode exits, right pane active | |
| 6 | Window border | Reverts to default | |
| 7 | Right status | Badge disappears | |

#### 5e. Rapid Toggle (Stress Test)

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Alt+C, Escape, Alt+C, Escape (rapid) | Mode toggles without artifacts | |
| 2 | Status bar | Updates correctly each time, no stale state | |
| 3 | Window border | Toggles without flicker or stuck color | |

#### 5f. Copy Mode Functionality (Regression)

Verify that the visual changes haven't broken the actual copy mode operations.

| # | Check | Expected | Pass? |
|---|-------|----------|-------|
| 1 | Alt+C, then v (visual select) | Selection begins | |
| 2 | Move with j/k, then y | Text yanked to clipboard + primary | |
| 3 | Paste with Ctrl+V elsewhere | Yanked text appears | |
| 4 | Alt+C, then Y (yank line) | Full line yanked, exits copy mode | |
| 5 | Alt+C, then q | Exits without copying | |
| 6 | Mouse select text (click-drag) | Enters copy mode with text in primary | |

### Layer 6: Debug Overlay Introspection (Optional, For Debugging Failures)

If any Layer 5 check fails, use the WezTerm debug overlay to inspect internal state.

```
1. Press Ctrl+Shift+L to open debug overlay
2. Switch to the "REPL" tab
3. Enter copy mode in another tab (Alt+C), then return to debug overlay tab

Queries to run in the REPL:

  -- Check active key table
  return window:active_key_table()
  -- Expected in copy mode: "copy_mode"
  -- Expected in normal: nil

  -- Check config overrides
  return window:get_config_overrides()
  -- Expected in copy mode: table with window_frame overrides
  -- Expected in normal: empty table or nil

  -- Check if handler is storing state in GLOBAL (if instrumented)
  return wezterm.GLOBAL.last_mode
```

**Note**: The debug overlay itself may affect the active key table since it's a
different tab. Query the state after the `update-status` handler has had time to
fire (~1-2s).

### Layer 7: Regression After Subsequent Phases

After implementing each subsequent phase of the slate migration, re-run Layers 1
and 5f to ensure copy mode bindings and visual indicators survived.

The minimum regression check after each phase:

```bash
# Quick automated regression
luac -p dot_config/wezterm/wezterm.lua && echo "syntax OK"
wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 2>&1 1>/dev/null \
  | grep -i error && echo "FAIL" || echo "parse OK"
wezterm --config-file dot_config/wezterm/wezterm.lua \
  show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_check.lua
diff /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_check.lua \
  && echo "copy_mode bindings unchanged" \
  || echo "REVIEW: copy_mode bindings changed"
```

Then manually: Alt+C, verify badge + border, Escape, verify revert.

### Testing Limitations Summary

| What | Automatable? | How |
|------|-------------|-----|
| Config syntax | Yes | `luac -p` |
| Config evaluation | Yes | `ls-fonts` stderr |
| Key table preservation | Yes | `show-keys` diff |
| Handler registration | Yes | `ls-fonts` catches syntax errors in `wezterm.on()` body |
| Handler fires correctly | Partial | Log inspection (requires manual mode entry) |
| Copy mode detected | Partial | `cli list --format json` title check (requires manual entry) |
| Status bar content | No | GUI-rendered, not queryable via CLI |
| Border color change | No | GUI-rendered, not queryable via CLI |
| Visual correctness | No | Manual checklist (Layer 5) |
| Override state | No | Debug overlay REPL only (Layer 6) |

The fundamental gap is that no CLI command can trigger `ActivateCopyMode` or query
visual rendering state. The testing plan compensates by layering automated checks
(which catch ~80% of failures) with a structured manual checklist (which catches
the remaining visual/logic issues).

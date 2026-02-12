---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-12T14:00:00-08:00"
task_list: styling/copy-mode
type: report
state: live
status: in_review
tags: [investigation, wezterm, copy-mode, ux, per-pane-styling, api-research]
---

# Copy Mode Pane Emphasis: API Affordances and Approach Tradeoffs

> BLUF: WezTerm has no first-class per-pane styling API. The only true per-pane
> visual mechanism is OSC 11 (terminal escape sequences) injected via
> `pane:inject_output()`. All other APIs (`set_config_overrides`, `colors.split`,
> `inactive_pane_hsb`, `window_frame`) are window-global. A hybrid approach
> combining OSC 11 pane backgrounds with status bar badges offers the best
> balance of per-pane specificity and reliability, but has meaningful tradeoffs
> around TUI app compat that must be weighed against simpler window-level
> approaches.

## Current State and Diagnosed Bugs

The current `update-status` handler has two bugs:

### Bug 1: `overrides.colors` replaces rather than merges

```lua
overrides.colors = { split = split_copy_mode }  -- line 372
```

`set_config_overrides` replaces nested tables wholesale. Setting `colors` to
`{ split = "#6b5300" }` wipes the entire `config.colors` table — background,
cursor, tab bar, copy mode highlights — and the color scheme's solarized
defaults fill the gaps. This causes the "reverts to old solarized colors
app-wide" symptom.

**Fix (any approach):** Either duplicate all `config.colors` keys in the
override, or avoid overriding `colors` entirely.

### Bug 2: `set_config_overrides` clears key table stack (Issue #5318)

Calling `window:set_config_overrides()` triggers an internal config reload that
clears the key table stack. The handler calls this every 200ms, which fights
against copy mode staying active. Copy mode persists only because the handler
re-evaluates before the clearing takes full effect — a race condition.

**Fix (any approach using overrides):** Guard with a dirty check so
`set_config_overrides` is only called when values actually change.

### Bug 3: Copy mode state lost on focus change

`window:active_key_table()` returns `nil` when the user navigates away from the
copy-mode pane (copy mode exits on focus change — this is WezTerm's design, not
a bug). The "muted emphasis when unfocused" goal requires a mechanism that
persists independently of the key table.

## Goals (from user requirements)

| # | Goal | Description |
|---|------|-------------|
| G1 | Max emphasis (focused + copy) | Immediately obvious that the focused pane is in copy mode |
| G2 | Muted emphasis (unfocused + copy) | Background indication that a pane was/is in copy mode |
| G3 | Easy state discrimination | At a glance, distinguish: normal, copy-focused, copy-unfocused |
| G4 | No color regression | Slate palette must remain intact during mode changes |
| G5 | Reliable | No race conditions, no fighting with key table stack |

**Note on G2:** WezTerm exits copy mode when a pane loses focus. "Unfocused but
in copy mode" is not a real WezTerm state. This goal could be reinterpreted as
either (a) a brief visual afterglow when leaving copy mode, or (b) reframing
the desire as ensuring the active-pane copy indication is strong enough on its
own.

## API Surface Summary

| API | Scope | Per-pane? | Dynamic? | Key table safe? |
|-----|-------|-----------|----------|----------------|
| `config.colors` | Window | No | Via overrides | No (#5318) |
| `config.window_frame` | Window | No | Via overrides | No (#5318) |
| `config.inactive_pane_hsb` | Window (all inactive) | No | Via overrides | No (#5318) |
| `colors.split` | Window (all dividers) | No | Via overrides | No (#5318) |
| `set_right_status` / `set_left_status` | Window (tab bar) | No | Yes | Yes |
| `format-tab-title` event | Per-tab | No | Yes | Yes |
| OSC 11 (`pane:inject_output`) | Per-pane | **Yes** | Yes | Yes |
| OSC 4 (palette entries) | Per-pane | **Yes** | Yes | Yes |
| `config.background` layers | Window | No | Via overrides | No (#5318) |

## Approach Catalog

### Approach A: Status Bar Only (No Pane Styling)

Keep the status badge (COPY/SEARCH) in the right status area. Remove all
`set_config_overrides` usage. Accept that the only copy mode indicator is the
tab bar badge.

**Implementation:** ~5 lines removed, 0 added. Delete the overrides block from
the handler.

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Partial | Badge visible but no in-pane signal |
| G2 | No | No unfocused state |
| G3 | Partial | Only two states: badge / no badge |
| G4 | Yes | No overrides = no color regression |
| G5 | Yes | No overrides = no race conditions |

**Jankiness: 0/5.** Clean, minimal, reliable. Trades emphasis for simplicity.

---

### Approach B: OSC 11 Pane Background Tint

Inject OSC 11 escape sequences to shift the copy-mode pane's background to a
warm-tinted slate (e.g., `#2a2520` — slate with a subtle amber undertone).
Reset to `#232323` on exit. Combine with status badge.

**Implementation:**

```lua
-- On copy mode enter (detected via title prefix or key table):
pane:inject_output('\x1b]11;rgb:2a/25/20\x07')

-- On copy mode exit:
pane:inject_output('\x1b]11;rgb:23/23/23\x07')
```

Detection: Check `pane:get_title()` for `"Copy mode:"` prefix in the
`update-status` handler. Track last-known state per pane ID to only inject on
transitions.

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Pane bg visually distinct + badge |
| G2 | Partial | See "unfocused" note below |
| G3 | Yes | Three visual states possible |
| G4 | Yes | No overrides, slate untouched |
| G5 | Mostly | No #5318 risk; inject_output has caveats |

**Unfocused behavior:** WezTerm exits copy mode on focus change, which also
clears the title prefix. The OSC 11 background would persist in the pane's
terminal state after copy mode exits (until explicitly reset), creating a
natural "afterglow." However, the `update-status` handler would detect the
title change and reset it. This could be made intentional — delay the reset by
N ticks to create a fade-out period.

**Caveats:**
- `inject_output` only works on local panes (not mux/ssh domains)
- OSC 11 changes the default bg; existing on-screen cells keep their old color
  until the application redraws. Full-screen TUI apps (nvim, htop) override it
  entirely with their own backgrounds on next redraw.
- If the pane is running nvim, nvim's own bg (#232323) will paint over the
  OSC 11 color on the next screen redraw, making the tint invisible inside nvim.
- Shell prompts and new output would appear with the tinted bg, creating a
  two-tone effect if the pane has existing content.

**Jankiness: 3/5.** The two-tone issue and TUI app incompatibility make this
unreliable for panes running anything other than a bare shell.

---

### Approach C: Window Frame Border Color (Fixed)

Use `set_config_overrides` to change `window_frame` border color during copy
mode (the original proposal approach), but fix bugs #1 and #2:

1. Override `window_frame` only (not `colors`) to avoid palette wipe
2. Guard with dirty-check to avoid repeated `set_config_overrides` calls

**Implementation:**

```lua
local last_mode = nil

wezterm.on("update-status", function(window, pane)
  local key_table = window:active_key_table()
  local mode = key_table or "normal"

  if mode ~= last_mode then
    last_mode = mode
    local overrides = window:get_config_overrides() or {}
    if mode == "copy_mode" or mode == "search_mode" then
      overrides.window_frame = {
        border_left_width = "4px", border_right_width = "4px",
        border_bottom_height = "4px", border_top_height = "4px",
        border_left_color = slate.yellow, border_right_color = slate.yellow,
        border_bottom_color = slate.yellow, border_top_color = slate.yellow,
      }
    else
      overrides.window_frame = nil
    end
    window:set_config_overrides(overrides)
  end

  -- Status badges (always, no overrides needed) ...
end)
```

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Whole window border lights up + badge |
| G2 | No | Border reverts when copy mode exits (focus change) |
| G3 | Partial | Two states: border on/off |
| G4 | Yes | Only `window_frame` overridden, not `colors` |
| G5 | Mostly | Dirty check mitigates #5318 but doesn't eliminate it |

**Jankiness: 1/5.** Clean and simple, but the #5318 risk remains (one call on
transition instead of every tick, but still present).

---

### Approach D: OSC 11 + Dimmed Inactive HSB (Hybrid)

Combine OSC 11 for per-pane background tint with increased
`inactive_pane_hsb` dimming during copy mode. The copy-mode pane gets a warm
tint AND stands out more because inactive panes dim further.

**Implementation:**

```lua
local last_mode = nil

wezterm.on("update-status", function(window, pane)
  local key_table = window:active_key_table()
  local mode = key_table or "normal"

  -- Per-pane: OSC 11 background tint
  if mode ~= last_mode then
    if mode == "copy_mode" then
      pane:inject_output('\x1b]11;rgb:2a/25/20\x07')
    elseif last_mode == "copy_mode" then
      pane:inject_output('\x1b]11;rgb:23/23/23\x07')
    end

    -- Window-level: increase inactive pane dimming during copy mode
    local overrides = window:get_config_overrides() or {}
    if mode == "copy_mode" or mode == "search_mode" then
      overrides.inactive_pane_hsb = { saturation = 0.6, brightness = 0.5 }
    else
      overrides.inactive_pane_hsb = nil
    end
    window:set_config_overrides(overrides)

    last_mode = mode
  end

  -- Status badges ...
end)
```

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Warm pane bg + aggressive dimming of others + badge |
| G2 | No | Both reset on focus change |
| G3 | Yes | Strong contrast between active-copy and inactive |
| G4 | Mostly | `inactive_pane_hsb` override is safe; OSC 11 has caveats |
| G5 | Mostly | Dirty check helps; OSC 11 caveats for TUI apps |

**Jankiness: 3/5.** Same OSC 11 TUI compat issues as Approach B, plus `set_config_overrides` once on transition.

---

### Approach E: Tab Title Styling + Status Badge (No Overrides)

Avoid all `set_config_overrides`. Use `format-tab-title` to change the active
tab's appearance when copy mode is detected (via title prefix), plus the
status badge. Zero override calls = zero #5318 risk.

**Implementation:**

```lua
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local title = tab.active_pane.title
  local is_copy = title:find("^Copy mode:") ~= nil
  local bg = is_copy and slate.yellow or (tab.is_active and slate.bg_raised or slate.bg_surface)
  local fg = is_copy and slate.bg_deep or (tab.is_active and slate.fg_bright or slate.fg_dim)
  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = " " .. (is_copy and "COPY" or tab.tab_index + 1) .. " " },
  }
end)
```

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Partial | Tab + badge change, no in-pane signal |
| G2 | No | Tab reverts when copy exits |
| G3 | Partial | Tab bar is small; relies on noticing it |
| G4 | Yes | No overrides |
| G5 | Yes | No overrides = no #5318 |

**Jankiness: 0/5.** Very clean, but low emphasis — everything happens in the
tab bar area.

---

### Approach F: Background Layer Overlay (Gradient Tint)

Use `config.background` with a gradient overlay layer that becomes visible
during copy mode via `set_config_overrides`. The gradient could be a subtle
amber-to-transparent vignette.

**Implementation:**

```lua
-- During copy mode:
overrides.background = {
  { source = { Color = slate.bg_raised }, width = "100%", height = "100%" },
  { source = { Gradient = {
      colors = { "#2a200800", "#2a200840" },  -- amber tint, subtle
      orientation = "Vertical",
    }},
    width = "100%", height = "100%",
    opacity = 0.15,
  },
}
```

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Whole window gets ambient tint |
| G2 | No | Resets with mode |
| G3 | Partial | Ambient but subtle |
| G4 | Mostly | Adds a layer, doesn't remove slate bg |
| G5 | No | Uses `set_config_overrides` (#5318) |

**Jankiness: 2/5.** Elegant visually but the background layer API is complex
and this still triggers #5318. The gradient affects the entire window, not the
specific pane.

---

### Approach G: Maximized Inactive Dimming + Status Badge (No Per-Pane)

Accept the window-level limitation. During copy mode, dramatically increase
`inactive_pane_hsb` dimming so the copy-mode pane (which is always the active
pane) stands out strongly by contrast. No per-pane styling needed because the
active pane is always the copy-mode pane.

**Implementation:**

```lua
local last_mode = nil

wezterm.on("update-status", function(window, pane)
  local key_table = window:active_key_table()
  local mode = key_table or "normal"

  if mode ~= last_mode then
    last_mode = mode
    local overrides = window:get_config_overrides() or {}
    if mode == "copy_mode" or mode == "search_mode" then
      overrides.inactive_pane_hsb = { saturation = 0.4, brightness = 0.4 }
    else
      overrides.inactive_pane_hsb = nil
    end
    window:set_config_overrides(overrides)
  end

  -- Status badges ...
end)
```

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Active pane pops via contrast with aggressively dimmed neighbors |
| G2 | No | Dimming reverts with mode |
| G3 | Yes | Two states: heavy dim (copy) vs normal dim |
| G4 | Yes | Only `inactive_pane_hsb` overridden |
| G5 | Mostly | Dirty check; one override call on transition |

**Jankiness: 1/5.** Simple, effective for multi-pane layouts. Less useful in
single-pane (no neighbors to dim). The "copy mode is special" feeling comes
from the sudden contrast shift.

---

### Approach H: Window Frame + Increased Dimming + Status Badge (Combined)

Combine Approaches C and G: yellow window border + aggressive inactive pane
dimming + status badge. Maximum emphasis through multiple channels. Single
guarded `set_config_overrides` call on mode transition.

| Goal | Met? | Notes |
|------|------|-------|
| G1 | Yes | Border + dimming contrast + badge (triple signal) |
| G2 | No | All revert on exit |
| G3 | Yes | Strong multi-channel differentiation |
| G4 | Yes | `window_frame` + `inactive_pane_hsb` only |
| G5 | Mostly | One guarded override call on transition |

**Jankiness: 1/5.** Most emphasis per unit of complexity.

## Comparative Matrix

| Approach | G1 Emphasis | G2 Persist | G3 Discrim | G4 No Regress | G5 Reliable | Jank | Complexity |
|----------|-------------|------------|------------|----------------|-------------|------|------------|
| A: Badge only | Low | No | Low | Yes | Yes | 0 | Trivial |
| B: OSC 11 bg | High | Partial* | High | Yes | Mostly | 3 | Medium |
| C: Window frame | High | No | Medium | Yes | Mostly | 1 | Low |
| D: OSC 11 + dim | High | No | High | Mostly | Mostly | 3 | Medium |
| E: Tab title | Low | No | Low | Yes | Yes | 0 | Low |
| F: Bg gradient | Medium | No | Medium | Mostly | No | 2 | High |
| G: Heavy dim | High | No | High | Yes | Mostly | 1 | Low |
| H: Frame + dim | **Highest** | No | **Highest** | Yes | Mostly | 1 | Low |

*OSC 11 "persist" is an artifact (bg color lingers in terminal state) not true
mode persistence. It has the TUI two-tone problem.

## Reassessing G2 (Unfocused Persistence)

WezTerm architecturally cannot have an unfocused pane in copy mode — focus
change exits copy mode. The G2 goal has three possible reinterpretations:

1. **Afterglow:** Brief visual fade-out after exiting copy mode (purely
   cosmetic, ~1s delay before reverting indicators). Achievable with a timer
   in the handler.
2. **Accept the limitation:** Copy mode is inherently focused. Make the focused
   signal strong enough that G2 is unnecessary.
3. **Rethink the workflow:** If the desire is to have persistent selection
   across panes, that's a different feature (multi-pane selection) that WezTerm
   doesn't support.

Interpretation 2 is the most pragmatic. Interpretation 1 adds complexity for
marginal benefit.

## Recommendation

**Approach H (Window Frame + Increased Dimming + Status Badge)** offers the
strongest emphasis with the least complexity and no per-pane hacks. It addresses
the core need: when you enter copy mode, the environment unmistakably changes.

The OSC 11 approaches (B, D) are the only ones that can mark a specific pane,
but their TUI incompatibility makes them unreliable for general use (nvim panes
would not show the tint).

If future WezTerm releases add `pane:set_config_overrides()` (requested in
multiple issues), this becomes trivially solvable. Until then, the window-level
approach is the right tradeoff.

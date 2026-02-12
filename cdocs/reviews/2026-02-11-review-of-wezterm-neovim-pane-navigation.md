---
review_of: cdocs/reports/2026-02-11-wezterm-neovim-pane-navigation.md
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T21:10:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: review
state: live
status: done
tags: [fresh_agent, architecture, keybinding_conflict, missing_validation]
---

# Review: WezTerm + Neovim Seamless Pane Navigation Options Analysis

## Summary Assessment

The report provides a thorough landscape analysis of solutions for seamless WezTerm/Neovim pane navigation. The problem statement is accurate and verified against the actual config files. The recommendation of smart-splits.nvim is well-supported by evidence. Three issues need attention: a keybinding conflict between smart-splits resize defaults and the existing `Alt+h/j/k/l` split bindings, an underexplored interaction with the `unix_domains` mux configuration, and a missing note about the `nushell` default shell's impact on process detection fallbacks.

## Section-by-Section Findings

### BLUF
**Non-blocking.** Clear, accurate, and actionable. Correctly identifies the keybinding collision as the root problem.

### Context / Background
**Non-blocking.** The problem statement is verified: `init.lua:83-86` maps `<C-h/j/k/l>` to `<C-w>h/j/k/l`, and `wezterm.lua:124-127` maps the same keys to `ActivatePaneDirection`. The report correctly explains that WezTerm intercepts first.

One clarification worth adding: the comment in `wezterm.lua:82` says "Window navigation: Ctrl+H/J/K/L (matches wezterm, tmux)" -- suggesting the user intended these to work together, confirming the pain point.

### Option 1: smart-splits.nvim
**Blocking (partial).** The technical analysis is strong, but the "Integration With Current Config" table has a gap:

The report says `Ctrl+Alt+h/j/k/l` resize bindings map to smart-splits resize. But the smart-splits README example uses `META` (Alt) for resize, which collides with the existing `Alt+h/j/k/l` split bindings (`wezterm.lua:130-133`). The report needs to explicitly call out this collision and suggest a resolution. Options include:

1. Keep `Alt+h/j/k/l` for WezTerm splits and use `Ctrl+Alt+h/j/k/l` for smart-splits resize (matching the existing resize bindings).
2. Remap WezTerm splits to a leader-based binding and reclaim `Alt+h/j/k/l` for resize.

Without addressing this, the implementation will either break split creation or resize.

### Option 1: Known Limitations
**Blocking.** The mux detach/reattach limitation deserves stronger emphasis. The config already has `unix_domains = { { name = "unix" } }` (line 47-49), meaning persistent sessions are configured even if not auto-connected. If the user enables `default_gui_startup_args = { "connect", "unix" }` (currently commented out at line 52), the user-var loss becomes a daily annoyance. The report should note that the existing config has unix_domains configured and flag this as a concrete risk, not a theoretical one.

### Option 2-5
**Non-blocking.** Thorough and well-reasoned dismissals. The archived wezterm-mux.nvim recommending smart-splits is a strong data point.

### Comparison Matrix
**Non-blocking.** The matrix is useful. Consider adding a row for "Default shell compatibility" since the dotfiles use nushell (`/home/mjr/.cargo/bin/nu`), and process name detection via `pane:get_foreground_process_name()` may return the shell name rather than nvim when nvim is launched as a child process of nushell. This matters for the fallback path.

### Recommendations
**Non-blocking.** Recommendation 2 says "The Alt-based split/resize bindings can remain as-is or be unified through smart-splits' resize support." This is too vague -- the Alt conflict described above means they cannot simply "remain as-is" if smart-splits resize uses Alt. Tighten this to a specific binding plan.

**Non-blocking.** Missing a recommendation to update the comment in `init.lua:82` ("matches wezterm, tmux") to reflect the new smart-splits integration.

## Verdict

**Revise.** The core analysis and recommendation are sound. Two blocking issues need resolution before this report can inform an implementation proposal:

1. The `Alt+h/j/k/l` keybinding conflict between WezTerm splits and smart-splits resize must be explicitly addressed with a concrete resolution.
2. The unix_domains mux configuration in the existing wezterm.lua must be called out as a concrete (not theoretical) risk for user-var loss.

## Action Items

1. [blocking] Add a subsection under "Integration With Current Config" addressing the `Alt+h/j/k/l` collision between WezTerm split creation and smart-splits resize. Propose a specific binding resolution.
2. [blocking] Strengthen the mux detach/reattach limitation to note that `unix_domains` is already configured in the current wezterm.lua, making this a near-term risk rather than a hypothetical.
3. [non-blocking] Add a note about nushell as the default shell and its potential impact on process-name-based fallback detection.
4. [non-blocking] Tighten Recommendation 2 to specify concrete keybinding assignments rather than "can remain as-is or be unified."
5. [non-blocking] Note that `init.lua:82` comment referencing tmux should be updated when implementing.

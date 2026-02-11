---
title: "Smart-Splits Adoption: Implementation Devlog"
date: 2026-02-11
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T22:45:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: devlog
state: live
status: review_ready
tags: [smart-splits, wezterm, neovim, navigation, handoff]
last_reviewed:
  status: revision_requested
  by: "@claude-opus-4-6"
  at: 2026-02-11T23:30:00-05:00
  round: 1
---

# Smart-Splits Adoption: Devlog

## Objective

Implement seamless `Ctrl+h/j/k/l` navigation between WezTerm panes and Neovim splits
by installing smart-splits.nvim and updating both configs. This is a two-phase change
with automated test gates at each phase.

Full spec: [cdocs/proposals/2026-02-11-smart-splits-adoption.md](../proposals/2026-02-11-smart-splits-adoption.md)

## Context for Implementor

### What exists today

- **Neovim** (`dot_config/nvim/init.lua:83-86`): `<C-h/j/k/l>` mapped to `<C-w>h/j/k/l`
- **WezTerm** (`dot_config/wezterm/wezterm.lua:124-127`): Same keys bound to `ActivatePaneDirection`
- **Collision**: WezTerm intercepts first, so Neovim split navigation is broken when panes exist

### What we're building

A two-sided coordination pattern where WezTerm checks `pane:get_user_vars().IS_NVIM`
before deciding whether to forward keys or handle pane navigation itself. smart-splits.nvim
on the Neovim side sets the user var and delegates to WezTerm CLI at edge splits.

### Key documents (read these before starting)

| Document | What it covers | Priority |
|----------|---------------|----------|
| [Proposal](../proposals/2026-02-11-smart-splits-adoption.md) | Full implementation spec with code, design decisions, test plan | **Read fully** |
| [CLAUDE.md](/var/home/mjr/code/personal/dotfiles/CLAUDE.md) | WezTerm validation workflow (mandatory for Phase 2) | **Read the WezTerm section** |
| [Neovim testing report](../reports/2026-02-11-playwright-for-neovim.md) | Headless test methodology, UIEnter trick, keymap encoding | Reference as needed |
| [WezTerm testing report](../reports/2026-02-11-playwright-for-wezterm.md) | 4-layer validation stack, action_callback gaps | Reference as needed |
| [Options analysis](../reports/2026-02-11-wezterm-neovim-pane-navigation.md) | Why smart-splits, not alternatives | Skim if curious |

### Files you will touch

| File | Action |
|------|--------|
| `dot_config/nvim/lua/plugins/navigation.lua` | **Create** -- smart-splits plugin spec |
| `dot_config/nvim/init.lua` | **Edit** -- remove lines 83-86 (`<C-h/j/k/l>` keymaps), update comment on line 82 |
| `dot_config/nvim/test/config_test.lua` | **Edit** -- add smart-splits test assertions |
| `dot_config/wezterm/wezterm.lua` | **Edit** -- add `is_nvim()`/`split_nav()` helpers, replace 8 static bindings |

### Files you must NOT touch

`editor.lua`, `snacks.lua`, `ui.lua`, any other plugin spec, mouse bindings, copy mode,
lace plugin, leader bindings, `Alt+h/j/k/l` split bindings, appearance settings, startup section.

## Plan

### Phase 1: Neovim side

1. Run baseline headless test suite, save results
2. Create `navigation.lua` with smart-splits spec (code in proposal)
3. Remove old `<C-h/j/k/l>` keymaps from `init.lua`
4. Add smart-splits assertions to `config_test.lua`
5. `chezmoi apply`, open Neovim to trigger lazy.nvim install
6. Run updated test suite -- all tests must pass (`cquit 0`)
7. Manual check: Neovim splits navigate with `Ctrl+h/l`

### Phase 2: WezTerm side

1. Capture `show-keys` baselines (full + copy_mode)
2. Add `is_nvim()` and `split_nav()` to `wezterm.lua`
3. Replace 8 static bindings with `split_nav()` calls
4. Run 4-layer validation: `luac -p` -> `ls-fonts` stderr -> `show-keys` diff -> binding assertions
5. `chezmoi apply`, check GUI hot-reload logs
6. `wezterm cli list` health check
7. Pane topology integration test
8. Manual cross-boundary navigation verification

## Testing Approach

**Test-first with automated gates.** No phase advances without its automated tests passing.

- **Neovim**: Headless Lua assertion suite via `nvim --headless -u <config> -c "luafile test.lua"`.
  Uses `cquit` for proper exit codes. ~570ms for full suite.
  Critical trick: `vim.api.nvim_exec_autocmds("UIEnter", {})` to trigger VeryLazy plugins.
- **WezTerm**: 4-layer stack (`luac -p` / `ls-fonts` stderr / `show-keys` diff / `cli` integration).
  `action_callback` logic cannot be tested programmatically -- manual verification required.
- **Keymap encoding gotcha**: `nvim_get_keymap` returns `<C-H>` (uppercase) for `<C-h>`,
  and `<C-M-H>` for `<C-A-h>`. Check actual lhs values, don't guess.

See the proposal's Test Plan section for all commands.

## Implementation Notes

### Phase 1 (Neovim)

Created the headless test suite from scratch (the report's appendix had a verified 32-test script). Baseline: 32/32 passing. Made all three file changes per proposal. On first test run, 2 resize keymap tests failed: the proposal claimed `<C-A-h>` encodes as `<C-M-H>` in `nvim_get_keymap`, but the actual encoding is `<M-C-H>` (Meta before Ctrl). Fixed the test assertions and re-ran: 42/42 passing.

> NOTE(opus/implementation): The proposal's keymap encoding table was wrong for Ctrl+Alt combos. The gotcha in the user instructions ("nvim_get_keymap returns `<C-M-H>` not `<C-A-h>`") is also incorrect for this Neovim version (0.11.6). The actual order is `<M-C-H>`. Always dump actual lhs values rather than trusting documentation.

### Phase 2 (WezTerm)

All edits matched the proposal exactly. The 4-layer validation caught one false-positive: `ActivatePaneDirection` and `AdjustPaneSize` still appear in `show-keys` output because WezTerm has built-in arrow-key defaults (Shift+Ctrl+Arrows for pane navigation, Shift+Alt+Ctrl+Arrows for resize). These are not our h/j/k/l bindings. The custom h/j/k/l bindings correctly show as `act.EmitEvent 'user-defined-N'` (how `action_callback` renders in `show-keys`).

> NOTE(opus/implementation): The proposal's binding assertion script (`grep -q "action_callback"`) does not match the actual `show-keys` output format. `action_callback` renders as `act.EmitEvent 'user-defined-N'` in the output. Future test plans should use the `EmitEvent` pattern.

### Manual verification gap

Cross-boundary navigation (Neovim-to-WezTerm and WezTerm-to-Neovim) cannot be tested programmatically because `action_callback` logic only executes at keypress time. The `show-keys` output confirms the callbacks are registered, but the `is_nvim()` conditional and the `SendKey`/`ActivatePaneDirection` branching can only be verified by pressing the actual keys.

## Changes Made

| File | Description |
|------|-------------|
| `dot_config/nvim/lua/plugins/navigation.lua` | **Created** -- smart-splits.nvim plugin spec with `lazy = false`, `at_edge = "stop"`, Ctrl+h/j/k/l navigation and Ctrl+Alt+h/j/k/l resize keymaps |
| `dot_config/nvim/init.lua` | **Edited** -- removed 4 old `<C-h/j/k/l>` -> `<C-w>h/j/k/l` keymaps, updated comment to reference smart-splits |
| `dot_config/nvim/test/config_test.lua` | **Created** -- 42-assertion headless test suite covering core settings, plugin loading, keymaps, error detection, and smart-splits integration |
| `dot_config/wezterm/wezterm.lua` | **Edited** -- added `is_nvim()`, `direction_keys`, `split_nav()` helpers; replaced 8 static Ctrl/Ctrl+Alt h/j/k/l bindings with `split_nav()` calls |

## Verification

### Phase 1: Neovim headless test suite (42/42 passing)

```
PASS: leader is space
PASS: number enabled
PASS: relativenumber enabled
PASS: tabstop is 2
PASS: shiftwidth is 2
PASS: expandtab enabled
PASS: clipboard is unnamedplus
PASS: termguicolors enabled
PASS: lazy.nvim loads
PASS: plugin count > 20
PASS: snacks.nvim registered
PASS: snacks.nvim loaded
PASS: nvim-treesitter registered
PASS: nvim-treesitter loaded
PASS: solarized.nvim registered
PASS: solarized.nvim loaded
PASS: gitsigns.nvim registered
PASS: which-key.nvim registered
PASS: which-key.nvim loaded
PASS: lualine.nvim registered
PASS: lualine.nvim loaded
PASS: flash.nvim registered
PASS: flash.nvim loaded
PASS: <leader>w mapped to save
PASS: <C-n> mapped to bnext
PASS: <leader>ff mapped (snacks picker)
PASS: <leader>e mapped (snacks explorer)
PASS: <leader>bd mapped (snacks bufdelete)
PASS: smart-splits.nvim registered
PASS: smart-splits.nvim loaded
PASS: require('smart-splits') works
PASS: <C-h> mapped (smart-splits move left)
PASS: <C-j> mapped (smart-splits move down)
PASS: <C-k> mapped (smart-splits move up)
PASS: <C-l> mapped (smart-splits move right)
PASS: <C-A-h> mapped (smart-splits resize left)
PASS: <C-A-l> mapped (smart-splits resize right)
PASS: <C-h> is NOT <C-w>h anymore
PASS: v:errmsg is empty
PASS: no errors in :messages
PASS: require('snacks') works
PASS: require('gitsigns') works after load

========================================
Results: 42 passed, 0 failed, 42 total
========================================
EXIT: 0
```

### Phase 2: WezTerm 4-layer validation

```
Layer 1 PASS: Lua syntax OK (luac -p)
Layer 2 PASS: Config parsed OK (ls-fonts stderr clean)
Layer 3 PASS: not defaults (config loaded)
Layer 3 PASS: copy_mode unchanged
Layer 3 PASS: Ctrl+h -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+Alt+h -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+j -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+Alt+j -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+k -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+Alt+k -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+l -> EmitEvent (action_callback)
Layer 3 PASS: Ctrl+Alt+l -> EmitEvent (action_callback)
Layer 3 PASS: Alt+h/j/k/l SplitPane present
Layer 3 PASS: Alt+c CopyMode present
Layer 4 PASS: no hot-reload errors in GUI log
Layer 4 PASS: mux healthy (wezterm cli list succeeded)
Layer 4 PASS: pane topology correct
```

### Manual verification (required)

The following scenarios require human testing because `action_callback` only executes at keypress time:

1. Neovim-only navigation: Ctrl+h/l between Neovim splits
2. Cross-boundary: Neovim rightmost split -> Ctrl+l -> WezTerm pane
3. Cross-boundary: WezTerm pane -> Ctrl+h -> Neovim split
4. Non-Neovim: Two terminal panes, Ctrl+h/l navigates between them
5. Unaffected: Alt+h/j/k/l still creates WezTerm splits

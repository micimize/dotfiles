---
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-24T19:00:00-05:00
task_list: dotfiles/reduce-ctrl-hjkl-latency
type: devlog
state: live
status: wip
tags: [neovim, wezterm, navigation, latency, smart-splits]
---

# Reduce Ctrl+HJKL Navigation Latency: Devlog

## Objective

Implement the proposal at `cdocs/proposals/2026-02-24-reduce-ctrl-hjkl-latency.md`.
Eliminate 60-300ms of synchronous subprocess blocking on every edge-of-splits
Ctrl+HJKL keypress by disabling smart-splits' auto-detected WezTerm multiplexer and
replacing it with a single async subprocess call. Also improve ESC and leader-key
responsiveness via timeout tuning.

## Plan

### Phase 1: Fix the delay (navigation.lua)
1. Add `init` function with `vim.g.smart_splits_multiplexer_integration = false`
2. Replace `at_edge = "stop"` with async `vim.system()` edge handler
3. Add manual IS_NVIM user variable setup in `config` function
4. Validate: headless syntax check, IS_NVIM verification, keymap verification

### Phase 2: Timeout hygiene (init.lua + editor.lua)
1. Change `timeoutlen` from 300 to 200
2. Add `ttimeoutlen = 10`
3. Change `better-escape` timeout from 300 to 200
4. Validate: headless setting verification

### Phase 3: Deploy and verify
1. `chezmoi apply --force`
2. Run validation scripts against running nvim instance
3. Commit

## Testing Approach

Automated validation via headless nvim scripts for:
- Config syntax (nvim -l loadfile check)
- IS_NVIM user variable emission (check smart-splits autoload functions exist)
- Keymap registration (C-h/j/k/l still mapped with callbacks)
- Timeout settings (timeoutlen=200, ttimeoutlen=10)
- Mux disabled (multiplexer_integration == false)

Manual verification deferred to user for actual latency feel.

## Implementation Notes

- **M.__mux cache problem**: Setting `multiplexer_integration = false` in lazy.nvim `opts`
  is too late — the wezterm module is cached in `M.__mux` during plugin load before
  `setup()` runs. Solution: use `vim.g.smart_splits_multiplexer_integration = false` in
  lazy.nvim `init` function (runs before plugin loads).
- **IS_NVIM dependency**: Disabling the mux also prevents `mux.on_init()` from setting the
  IS_NVIM user variable. Without it, WezTerm can't distinguish nvim panes. Solution:
  manually call `smart_splits#write_wezterm_var` / `smart_splits#format_wezterm_var` in the
  `config` function, plus VimResume/VimLeavePre autocmds.
- **Headless validation**: Initial `vim.defer_fn` approach with `XDG_CONFIG_HOME` override
  hung indefinitely (likely lazy.nvim plugin operations). Replaced with `nvim --headless -c`
  using `vim.defer_fn` + `io.open` for reliable output, plus 30s timeout wrapper.

## Changes Made

| File | Description |
|------|-------------|
| `dot_config/nvim/lua/plugins/navigation.lua` | Disable mux via `vim.g` in `init`, async `at_edge` handler, manual IS_NVIM setup |
| `dot_config/nvim/init.lua` | `timeoutlen` 300→200, add `ttimeoutlen = 10` |
| `dot_config/nvim/lua/plugins/editor.lua` | `better-escape` timeout 300→200 |

## Verification

### Syntax Checks

All three files pass `nvim -l loadfile()` syntax validation.

### Headless Functional Validation

```
mux_integration_g=false
timeoutlen=200
ttimeoutlen=10
ss_mux_integration=false
at_edge_type=function
mux_get_nil=true
C-h_mapped=true
FocusFromEdge_exists=true
```

All 8 checks pass. Deployed via `chezmoi apply --force`.

### Manual Verification

Deferred to user for actual latency feel on Ctrl+HJKL keypresses.

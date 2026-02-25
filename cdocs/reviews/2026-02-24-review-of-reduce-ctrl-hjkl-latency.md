---
review_of: cdocs/proposals/2026-02-24-reduce-ctrl-hjkl-latency.md
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-24T12:00:00-05:00
task_list: dotfiles/navigation-latency
type: review
state: live
status: done
tags: [rereview_agent, root_cause_analysis, code_trace, neovim, wezterm, smart-splits, mux_cache_bug]
---

# Review Round 2: Reduce Ctrl+HJKL Navigation Latency

## Round 1 Resolution

The first review correctly identified that `ttimeoutlen`/`timeoutlen` do not affect
Ctrl+HJKL latency (single-byte control characters, no prefix ambiguity). All three
blocking action items from round 1 have been addressed: the proposal has been
rewritten with the actual root cause (synchronous `wezterm cli` subprocess spawns
from smart-splits' auto-detected multiplexer backend). The BLUF, root cause analysis,
and proposed fix are now centered on this real issue.

## Summary Assessment

The rewritten proposal correctly identifies the dominant latency source: smart-splits
auto-detects WezTerm via `$TERM_PROGRAM`, enabling a multiplexer backend that spawns
2-7 synchronous `wezterm cli` subprocesses on every edge keypress. The code walkthrough
is accurate and the proposed fix (`multiplexer_integration = false` plus a custom async
`at_edge` function) is architecturally sound. However, the proposal has one critical
implementation gap: smart-splits caches the multiplexer module in `mux/init.lua:M.__mux`
during plugin startup, and this cache is never invalidated by `setup()`. Setting
`multiplexer_integration = false` in opts will NOT prevent subprocess spawns because
`M.get()` returns the cached wezterm module before checking the config value.
Verdict: **Revise** -- the fix needs one additional mechanism to bypass the mux cache.

## Section-by-Section Findings

### BLUF

The BLUF now accurately describes the problem: smart-splits spawns 2-7 synchronous
`wezterm cli` subprocesses at every edge press. The claim that this happens "even with
`at_edge = "stop"`" is correct -- `mux.move_pane()` is called before the `at_edge`
string check (api.lua:393 vs. 411). The subprocess count estimates (2 minimum, up to 7
with navigation) are substantiated by the code trace in `mux/wezterm.lua`.

The BLUF correctly relegates `ttimeoutlen` and `timeoutlen` to secondary improvements.

**Category: no issues.**

### Root Cause Analysis

The code trace through `api.lua:391-395` -> `mux.move_pane()` -> `mux/wezterm.lua` is
accurate. I verified each step against the source:

- `api.lua:391`: `will_wrap` is true when at edge (correct).
- `api.lua:393`: `mux.move_pane(direction, will_wrap, at_edge)` is called before the
  `at_edge == 'stop'` check on line 411 (correct).
- `mux/init.lua:83-117`: `move_pane()` calls `M.get()` to get the multiplexer, then
  calls `multiplexer.is_in_session()` and `multiplexer.current_pane_at_edge(direction)`.
- `mux/wezterm.lua:114-116`: `is_in_session()` calls `current_pane_id()` which calls
  `current_pane_info()` which calls `wezterm_exec({ 'list', '--format', 'json' })` --
  a synchronous subprocess via `vim.system(cmd):wait()`.
- `mux/wezterm.lua:100-106`: `current_pane_at_edge()` calls
  `wezterm_exec({ 'get-pane-direction', direction })` -- another synchronous subprocess.

The subprocess count table in the proposal is accurate:
- Steps 1-2 (is_in_session + current_pane_at_edge) run on every edge press: 2 calls minimum.
- Steps 3-5 only run when there IS another WezTerm pane: up to 5 additional calls via
  `move_multiplexer_inner()` which calls `current_pane_id()` before and after `next_pane()`.

One minor correction: `current_pane_info()` has its own `init_tab_id()` call on first
invocation (wezterm.lua:50-52), which adds yet another `wezterm cli list --format json`
call the very first time. This is a one-time cost, not per-keypress.

**Category: no issues.** The root cause analysis is now correct.

### Proposed Fix: `multiplexer_integration = false`

The proposal claims that setting `multiplexer_integration = false` in opts will cause
`mux.get()` to return `nil` immediately via `mux/init.lua:54-59`. This is the critical
flaw.

**The `M.__mux` cache invalidation bug.** The initialization sequence is:

1. Plugin loads (`lazy = false`), sourcing `plugin/smart-splits.lua`.
2. Line 7: `set_default_multiplexer()` auto-detects WezTerm, sets
   `config.multiplexer_integration = "wezterm"`.
3. Line 8: `startup()` calls `require('smart-splits.mux').get()`, which finds
   `config.multiplexer_integration == "wezterm"`, requires `mux.wezterm`, and caches
   it: `M.__mux = wezterm_module`.
4. Lazy.nvim calls `config()` -> `setup({multiplexer_integration = false, ...})`.
5. `setup()` sets `config.multiplexer_integration = false`, but does NOT clear `M.__mux`.

The re-startup guard in `config.lua:121-128` has a bug -- the condition
`#tostring(original_mux or '') == 0` evaluates to `#"wezterm" == 0` which is `false`,
so the guard never fires and `startup()` is never re-called:

```lua
if
  original_mux ~= nil                          -- "wezterm" ~= nil  -> true
  and original_mux ~= false                    -- "wezterm" ~= false -> true
  and #tostring(original_mux or '') == 0       -- #"wezterm" == 0   -> FALSE
  and original_mux ~= config.multiplexer_integration
then
  mux_utils.startup()  -- never reached
end
```

Even if it did re-run startup, there is no code anywhere in smart-splits that sets
`M.__mux = nil`. The cache is write-once, never cleared.

Consequence: after `setup()`, `M.get()` still returns the cached wezterm module because
line 50 (`if M.__mux ~= nil then return M.__mux end`) short-circuits before the
`config.multiplexer_integration` check on line 54-59. Every call to `mux.move_pane()`
still reaches `multiplexer.is_in_session()` and spawns subprocesses.

**Workarounds (pick one):**

**(A) Pre-empt auto-detection with `vim.g`** (cleanest). Add an `init` function to the
lazy spec that runs before the plugin loads:

```lua
{
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  init = function()
    vim.g.smart_splits_multiplexer_integration = false
  end,
  opts = {
    at_edge = function(ctx) ... end,
  },
  ...
}
```

`set_default_multiplexer()` checks `vim.g.smart_splits_multiplexer_integration` early
(config.lua:80-91) and sets `config.multiplexer_integration = false` before `startup()`
runs. Then `M.get()` in `startup()` finds `config.multiplexer_integration == false`,
returns nil, and `M.__mux` is never set.

**(B) Clear the cache manually after setup:**

```lua
config = function(_, opts)
  require("smart-splits").setup(opts)
  require("smart-splits.mux").__mux = nil  -- bust the cache
  ...
end
```

This works but reaches into internal state. Option A is preferable.

**(C) Set `multiplexer_integration = false` in opts AND clear cache** -- belt and
suspenders.

**Category: blocking.** The proposed fix will not work as written. The `M.__mux` cache
must be prevented from being set (option A) or explicitly cleared (option B).

### Proposed Fix: Custom Async `at_edge` Function

Assuming the mux cache issue is resolved, the `at_edge` function approach is correct:

1. `mux.move_pane()` returns `false` instantly (no multiplexer).
2. `api.lua:398`: `type(at_edge) == 'function'` is true.
3. `ctx.direction` is the `SmartSplitsDirection` value (`'left'`/`'right'`/`'up'`/`'down'`)
   from `types.lua:14`. The mapping table
   `{ left = 'Left', right = 'Right', up = 'Up', down = 'Down' }` correctly converts
   to WezTerm CLI's expected capitalized direction arguments, matching `dir_keys_wezterm`
   in `mux/wezterm.lua:5-10`.
4. `vim.system()` without `:wait()` and without a callback is valid Neovim API usage.
   It spawns the process asynchronously and returns a `SystemObj`. The process runs in
   the background. Since this is called from the main event loop (keymap handler), the
   `vim.system()` call itself is safe.

**One edge case:** if the user presses Ctrl+L rapidly at the edge (say 5 times in 500ms),
5 async `wezterm cli activate-pane-direction Right` processes will be spawned. Each one
tries to activate the pane to the right. WezTerm handles these idempotently (activating
an already-active pane is a no-op), so there is no correctness issue -- just 5 wasted
process spawns. This is not a realistic concern for normal usage.

**Another edge case:** the fire-and-forget `vim.system()` call does not check the exit
code. If `wezterm cli` fails (e.g., wezterm is not running, or the pane direction does
not exist), the failure is silently ignored. For the "no pane in that direction" case,
this is actually desirable -- it acts like `at_edge = "stop"` but with a brief async
attempt. For genuine errors (wezterm not running), silent failure is acceptable for a
personal config.

**Category: no issues** (contingent on resolving the mux cache issue).

### Changes 2-4: Timeout Adjustments

These are correctly scoped as secondary improvements unrelated to the primary Ctrl+HJKL
fix. The analysis is accurate:

- `ttimeoutlen = 10`: improves ESC responsiveness (300ms -> 10ms), explicitly noted as
  unrelated to Ctrl+HJKL. Correct.
- `timeoutlen = 200`: improves leader-key responsiveness (300ms -> 200ms). No impact on
  Ctrl+HJKL. Correct.
- `better-escape = 200`: consistency improvement. Correct.

**Category: no issues.**

### Tradeoffs Table

The table accurately captures the benefit/risk for each change. The FocusFromEdge note
is a good addition -- it correctly identifies that cross-WezTerm-pane nvim-to-nvim
navigation loses directional edge focus. The mitigation suggestion (user variable +
`user-var-changed` event) is viable if the case ever matters.

**Category: no issues.**

### Test Plan

The test plan covers the key scenarios: single nvim window, multiple splits, edge with
adjacent WezTerm pane, and the timeout changes. It lacks a negative test for the mux
cache issue (verifying that no `wezterm cli list` subprocesses are spawned during edge
presses), but this is pragmatically testable by checking whether the perceived latency
actually improves.

**Category: non-blocking.** Consider adding: "verify no stale subprocess spawns by running
`strace -f -e trace=execve -p <nvim_pid>` while pressing Ctrl+HJKL at the edge."

### Implementation

The two-phase approach is clean. Phase 1 (navigation.lua) is the critical fix. Phase 2
(timeout hygiene) is independent and low-risk.

The implementation section references `init.lua` for timeout settings but does not
specify the exact file path. This should be clarified (presumably
`dot_config/nvim/init.lua` or wherever `vim.opt` settings live).

**Category: non-blocking.**

## Verdict

**Revise.** The root cause analysis is now correct, the code trace is accurate, and the
architectural approach (disable multiplexer, async edge handler) is sound. The one
blocking issue is that `multiplexer_integration = false` in opts alone will not prevent
subprocess spawns due to the `M.__mux` cache in `mux/init.lua`. The fix needs either
`vim.g.smart_splits_multiplexer_integration = false` in an `init` function (preferred)
or a manual cache clear after `setup()`.

All round 1 blocking items have been addressed. This round introduces one new blocking
item (the cache bug) and two non-blocking suggestions.

## Action Items

1. [blocking] Address the `M.__mux` cache invalidation issue. The recommended approach
   is to add `init = function() vim.g.smart_splits_multiplexer_integration = false end`
   to the lazy.nvim plugin spec. This prevents the wezterm module from being cached during
   `startup()`, making `mux.move_pane()` return `false` instantly as the proposal intends.
   Alternative: clear `require("smart-splits.mux").__mux = nil` in the `config` function
   after `setup()`.

2. [non-blocking] Consider adding a verification step to the test plan that confirms no
   `wezterm cli` subprocesses are spawned during Ctrl+HJKL edge presses (e.g., via strace
   or by temporarily adding `vim.notify("mux.get called")` to the mux module).

3. [non-blocking] Clarify the exact file path for Phase 2 timeout settings in the
   Implementation section.

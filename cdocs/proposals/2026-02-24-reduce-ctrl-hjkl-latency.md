---
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-24T00:00:00-05:00
type: proposal
state: live
status: implementation_wip
tags: [neovim, wezterm, navigation, latency, smart-splits]
last_reviewed:
  status: revision_requested
  by: "claude-opus-4-6"
  at: 2026-02-24T18:00:00-05:00
  round: 2
---

# Reduce Ctrl+HJKL Navigation Latency

> BLUF: smart-splits.nvim auto-detects WezTerm and spawns **2-7 synchronous
> `wezterm cli` subprocesses** on every edge-of-splits keypress — even with
> `at_edge = "stop"`, because the multiplexer is queried before the stop behavior
> is evaluated. With a single nvim window (no splits), every Ctrl+HJKL press is
> an edge press, so every press pays this cost (~100-350ms). The fix: disable
> auto-detected multiplexer via `vim.g` before the plugin loads, manually set the
> IS_NVIM user variable (which the mux normally handles), and replace the edge
> handler with a single async subprocess call. Secondary: `ttimeoutlen = 10` and
> `timeoutlen = 200` improve ESC and leader-key responsiveness.

## Root Cause: Synchronous `wezterm cli` Subprocess Spawns

### How the delay happens

smart-splits.nvim auto-detects WezTerm at startup via `$TERM_PROGRAM` and enables
its built-in WezTerm multiplexer backend (`lua/smart-splits/mux/wezterm.lua`). This
happens even though `multiplexer_integration` is not set in our config — the
auto-detection in `config.set_default_multiplexer()` sets it to `"wezterm"`.

When Ctrl+HJKL is pressed and the cursor is at the edge of all nvim splits (or there
are no splits at all), `move_cursor()` in `api.lua:391` calls `mux.move_pane()`
**before** checking `at_edge = "stop"`:

```lua
-- api.lua:391-395
if will_wrap then
    if mux.move_pane(direction, will_wrap, at_edge) then  -- ALWAYS called first
      return
    end
    -- at_edge is only checked AFTER mux fails
    if at_edge == 'stop' then return end
```

Inside `mux.move_pane()`, the WezTerm backend spawns synchronous subprocesses via
`vim.system(cmd):wait()` (blocks the entire Neovim event loop):

| Step | Subprocess spawned | Purpose |
|------|--------------------|---------|
| 1 | `wezterm cli list --format json` | `is_in_session()` → get current pane info |
| 2 | `wezterm cli get-pane-direction <dir>` | `current_pane_at_edge()` → check if at WezTerm edge |
| 3* | `wezterm cli list --format json` | `current_pane_id()` before navigation |
| 4* | `wezterm cli activate-pane-direction` | Actually navigate |
| 5* | `wezterm cli list --format json` | `current_pane_id()` after, to verify move |

Steps 3-5 only run when there IS another WezTerm pane in that direction. Steps 1-2
run on **every** edge press regardless of `at_edge` setting.

### Why it's so slow

Each subprocess spawn involves: `fork()` → `exec(wezterm)` → CLI connects to running
WezTerm via Unix socket → RPC → JSON response → Neovim parses JSON. Estimated ~30-60ms
per call. Two calls minimum = ~60-120ms. With navigation (5 calls) = ~150-300ms.

### When it triggers

- **Single nvim window (no splits):** Every Ctrl+HJKL press is an edge press. Every
  press pays the full subprocess cost.
- **Multiple splits, navigating within:** No subprocess overhead. Only `vim.fn.winnr()`
  checks, which are instant.
- **Multiple splits, at the edge:** 2-5 subprocess calls.

## Proposed Fix

### The `M.__mux` cache problem

Setting `multiplexer_integration = false` in lazy.nvim's `opts` table is **not
sufficient**. The plugin's load sequence is:

1. `plugin/smart-splits.lua` runs → `set_default_multiplexer()` auto-detects WezTerm
2. `startup()` calls `mux.get()` → loads and **caches** wezterm module in `M.__mux`
3. `mux.on_init()` sets `IS_NVIM` user variable via OSC 1337 escape sequence
4. lazy.nvim calls `setup(opts)` → overrides config, but `M.__mux` is already cached

Subsequent `M.get()` calls check `M.__mux ~= nil` first (line 50) and return the
cached module, completely bypassing the `multiplexer_integration == false` check.

### Solution: `vim.g` pre-plugin + manual IS_NVIM

smart-splits explicitly supports pre-plugin configuration via
`vim.g.smart_splits_multiplexer_integration` (checked in `config.lua:80-91` before
auto-detection runs). Setting this to `false` in lazy.nvim's `init` function (which
runs before the plugin loads) prevents auto-detection entirely.

However, disabling the mux also prevents `on_init()` from running, which means the
`IS_NVIM` user variable is never set. Without it, WezTerm's `is_nvim(pane)` check
always returns false, breaking the conditional dispatch. We must set IS_NVIM manually.

### Change 1: navigation.lua — disable mux, manual IS_NVIM, async edge handler

```lua
return {
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    init = function()
      -- Disable mux BEFORE plugin loads to prevent M.__mux caching.
      -- The mux spawns 2-7 synchronous wezterm cli subprocesses per edge
      -- keypress. We handle edge navigation with a single async call instead.
      vim.g.smart_splits_multiplexer_integration = false
    end,
    opts = {
      at_edge = function(ctx)
        -- Single async call, non-blocking (no :wait())
        vim.system({
          'wezterm', 'cli', 'activate-pane-direction',
          ({ left = 'Left', right = 'Right', up = 'Up', down = 'Down' })[ctx.direction],
        })
      end,
    },
    keys = {
      -- (unchanged keymaps)
    },
    config = function(_, opts)
      require("smart-splits").setup(opts)

      -- Manually set IS_NVIM user variable (normally done by mux.on_init,
      -- which we disabled). WezTerm reads this to distinguish nvim panes.
      local function set_is_nvim(val)
        vim.fn['smart_splits#write_wezterm_var'](
          vim.fn['smart_splits#format_wezterm_var'](val)
        )
      end
      set_is_nvim('true')
      vim.api.nvim_create_autocmd('VimResume', {
        callback = function() set_is_nvim('true') end,
      })
      vim.api.nvim_create_autocmd('VimLeavePre', {
        callback = function() set_is_nvim('false') end,
      })

      -- FocusFromEdge (unchanged)
      vim.api.nvim_create_user_command("FocusFromEdge", function(cmd)
        local wincmd = ({ left = "h", right = "l", up = "k", down = "j" })[cmd.args]
        if wincmd then vim.cmd("999wincmd " .. wincmd) end
      end, {
        nargs = 1,
        complete = function() return { "left", "right", "up", "down" } end,
      })
    end,
  },
}
```

**How this works:**

1. `init` sets `vim.g.smart_splits_multiplexer_integration = false` before the plugin
   loads. `set_default_multiplexer()` sees this, sets `config.multiplexer_integration =
   false`, and returns without auto-detecting. `startup()` calls `mux.get()` which
   returns nil — nothing is cached in `M.__mux`.

2. On every edge keypress, `mux.move_pane()` calls `M.get()` → checks
   `config.multiplexer_integration == false` → returns nil → `move_pane` returns false
   instantly. Zero subprocess calls.

3. The `at_edge` function fires ONE async `wezterm cli activate-pane-direction` without
   `:wait()`. Neovim is never blocked.

4. IS_NVIM is set manually via the same OSC 1337 escape sequence that `mux.on_init()`
   uses, plus VimResume/VimLeavePre autocmds for session resilience.

**Latency comparison:**

| Scenario | Before (sync mux) | After (async edge) |
|----------|--------------------|--------------------|
| Within splits | ~0ms | ~0ms (unchanged) |
| Edge, no WezTerm pane | ~60-120ms (2 sync calls) | ~0ms (nil check + async no-op) |
| Edge, WezTerm pane exists | ~150-300ms (5 sync calls) | ~0ms nvim-side (~30ms async) |

### Change 2: `ttimeoutlen = 10` (ESC responsiveness)

Unrelated to Ctrl+HJKL but worth fixing. `ttimeoutlen` inherits `timeoutlen = 300`,
making ESC wait 300ms for escape sequence disambiguation. Setting to 10ms makes ESC
feel instant. No impact on Ctrl+HJKL (single-byte control characters, not escape
sequences — `enable_csi_u_key_encoding = false` in WezTerm config).

### Change 3: `timeoutlen = 200` (leader sequences)

Reduces leader-key sequence timeout from 300ms to 200ms. Makes `<Space>ff` etc.
resolve 100ms faster. No impact on Ctrl+HJKL (no prefix ambiguity).

### Change 4 (optional): `better-escape` timeout to 200ms

Align `jk`/`jj` escape timeout with the new `timeoutlen` for consistency.

## Tradeoffs

| Change | Benefit | Risk |
|--------|---------|------|
| Disable mux + async `at_edge` | Eliminates 60-300ms blocking delay | Nvim→nvim cross-pane (rare: two nvim instances in adjacent WezTerm panes) loses `FocusFromEdge` — lands on last-active split instead of edge split. |
| Manual IS_NVIM | WezTerm detection works identically | Depends on smart-splits autoload functions existing. Low risk — they are part of the plugin. |
| `ttimeoutlen = 10` | ESC: 300ms → 10ms | Escape sequences split across reads could misparse (not realistic for local terminals). |
| `timeoutlen = 200` | Leader sequences: 100ms faster | Less time to type multi-key sequences. |
| `better-escape = 200` | Consistent timeouts | Less time to type `jk`/`jj` naturally. |

### Note on FocusFromEdge

The WezTerm-to-nvim path (navigating INTO an nvim pane from a non-nvim pane) still
sends `FocusFromEdge` — this is handled by the WezTerm callback, not by smart-splits,
and is unchanged. The only lost case is nvim→nvim cross-WezTerm-pane, which requires
two nvim instances in adjacent panes. If needed later, the `at_edge` function could
set a user variable to trigger WezTerm's `user-var-changed` event.

## Test Plan

1. Apply changes to `navigation.lua` and `init.lua`
2. `chezmoi apply --force`
3. Verify IS_NVIM is set:
   ```sh
   wezterm cli list --format json | python3 -c "
   import json,sys
   for p in json.load(sys.stdin):
     print(p.get('title',''), p.get('user_vars',{}).get('IS_NVIM','unset'))
   "
   ```
4. **Single nvim window** (no splits): Ctrl+HJKL — should feel instant
5. **Multiple nvim splits**: navigate between them — should feel instant
6. **Nvim at edge + adjacent WezTerm pane**: Ctrl+L switches pane without blocking
7. **Non-nvim pane**: Ctrl+L navigates to adjacent pane (unchanged behavior)
8. `<Space>ff`, `<Space>fg` — should work at 200ms timeout
9. ESC in insert mode — should feel instant
10. `jk`/`jj` in insert mode — should still trigger

## Implementation

### Phase 1: Fix the delay (navigation.lua)

- Add `init` function with `vim.g.smart_splits_multiplexer_integration = false`
- Replace `at_edge = "stop"` with async function
- Add manual IS_NVIM setup in `config` function (set on startup, VimResume, clear on
  VimLeavePre)

### Phase 2: Timeout hygiene (init.lua + editor.lua)

- `vim.opt.timeoutlen = 200` (was 300)
- `vim.opt.ttimeoutlen = 10` (new)
- Optionally: `better-escape` timeout to 200

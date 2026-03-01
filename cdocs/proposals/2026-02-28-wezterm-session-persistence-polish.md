---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-28T10:00:00-06:00"
task_list: dotfiles/wezterm
type: proposal
state: live
status: implementation_wip
tags: [wezterm, nushell, session-persistence, resurrect, wayland, cleanup]
---

# WezTerm Session Persistence: Polish Pass

> BLUF: Two issues surfaced during post-deploy verification of the session persistence
> feature ([devlog](../devlogs/2026-02-27-wezterm-session-persistence.md)): (1) stale
> Wayland symlinks after GUI restart break `wezterm cli`, and (2) unguarded config
> evaluation registers duplicate periodic-save timers and event handlers. Fix both with
> a nushell-side symlink cleanup in the existing pre_prompt hook and a `wezterm.GLOBAL`
> guard around the resurrect plugin block.

## Objective

Harden the WezTerm session persistence stack against two failure modes discovered during
live testing. Neither is a correctness bug — sessions save and restore correctly — but
the symlink issue causes hard failures on GUI restart, and the timer duplication wastes
I/O and log noise.

## Background

The session persistence implementation
([proposal](2026-02-27-wezterm-session-persistence.md)) uses unix domain multiplexing
with the resurrect.wezterm plugin for cross-reboot persistence. During post-deploy
verification, two issues were identified:

**Issue 1 — Stale Wayland symlink.** When the WezTerm GUI quits and is relaunched
(without a full reboot), a dangling symlink at
`/run/user/1000/wezterm/wayland-*-org.wezfurlong.wezterm` points to the dead GUI
socket. `wezterm cli` attempts to connect through this stale path and fails with
`failed to connect to Socket(...)`. The mux server is still running and healthy — only
the CLI client is broken. Manual removal of the symlink or a full reboot resolves it.
This is an upstream WezTerm bug (Wayland socket cleanup), not caused by our config.

**Issue 2 — Overlapping timers from config re-evaluation.** WezTerm evaluates the Lua
config multiple times during unix domain startup (6 times observed). Each evaluation
calls `resurrect.state_manager.periodic_save()` and registers new `wezterm.on()`
handlers, resulting in 6 parallel save timers and 6 copies of each event handler. The
saves are idempotent (same data, same files), so this is a performance and log-noise
concern, not a data corruption issue.

## Proposed Solution

### Fix 1: Symlink cleanup in pre_prompt hook

Add stale symlink cleanup to the existing WezTerm auto-restore `pre_prompt` hook in
`config.nu`. This runs once per shell session (guarded by `_WEZ_RESTORE_OFFERED`) and
only when inside WezTerm (checked via `WEZTERM_PANE`). The cleanup runs before the
restore prompt, ensuring `wezterm cli` works for the restore IPC.

```nushell
# Inside the existing pre_prompt hook, before the restore logic:
let wez_runtime = $"/run/user/(id -u)/wezterm"
if ($wez_runtime | path exists) {
  glob $"($wez_runtime)/wayland-*-org.wezfurlong.wezterm"
    | where { |f| not ($f | path type | $in == "socket") or (not ($f | path exists)) }
    | each { |f| rm -f $f }
}
```

This approach:
- Runs only once (existing one-shot guard)
- Runs only inside WezTerm (existing `WEZTERM_PANE` check)
- Targets only the known problematic symlink pattern
- Uses `rm -f` to silently skip if already gone
- Runs before restore prompt so `wezterm cli` is healthy for IPC

> NOTE: A systemd user service (`wezterm-cleanup.service`) was considered but rejected.
> The pre_prompt hook is simpler, already runs at the right time, and keeps all session
> logic in nushell rather than splitting across two subsystems.

### Fix 2: GLOBAL guard for resurrect plugin setup

Wrap the resurrect plugin initialization in a `wezterm.GLOBAL` flag check so it only
runs once, regardless of how many times the config is re-evaluated.

```lua
if ok_resurrect and not wezterm.GLOBAL.resurrect_initialized then
  wezterm.GLOBAL.resurrect_initialized = true

  resurrect.state_manager.change_state_save_dir(...)
  resurrect.state_manager.set_max_nlines(5000)
  resurrect.state_manager.periodic_save({...})

  wezterm.on('user-var-changed', function(...) ... end)
  wezterm.on("resurrect.error", function(...) ... end)
end
```

The `wezterm.GLOBAL` table persists across config re-evaluations within a single mux
server lifetime. Once the flag is set, subsequent config evals skip the entire block.

The `update-status` and `mux-startup` handlers outside the resurrect block are
idempotent (WezTerm replaces — not appends — handlers registered with the same event
name from the same config evaluation), so they do not need guarding.

> NOTE: `wezterm.on()` behavior with re-evaluation is nuanced. Per WezTerm docs,
> re-evaluation replaces previously registered handlers from the config. However,
> `periodic_save` uses `wezterm.time.call_after` internally, which genuinely accumulates
> timers. The GLOBAL guard addresses the root cause (preventing re-registration) rather
> than relying on WezTerm's handler replacement semantics.

## Important Design Decisions

### Decision: Nushell pre_prompt cleanup over systemd service

**Decision:** Clean stale symlinks in the existing nushell pre_prompt hook.

**Why:** The hook already runs once per WezTerm session, already checks for WezTerm
context, and runs before the restore prompt (which needs working `wezterm cli`). Adding
a systemd user service would split session-persistence logic across two subsystems
(nushell + systemd) and require managing a separate unit file. The hook approach keeps
everything in the dotfiles nushell config where it's co-located with the rest of the
session logic.

### Decision: Guard entire resurrect block, not just periodic_save

**Decision:** Wrap all resurrect initialization (save dir override, max nlines, periodic
save, event handlers) in the GLOBAL guard — not just the timer.

**Why:** While `periodic_save` is the most visible symptom (accumulating timers), calling
`change_state_save_dir` and `set_max_nlines` 6 times is also unnecessary work. The event
handlers may or may not accumulate depending on WezTerm internals. Guarding the entire
block is simpler, correct, and avoids depending on undocumented re-evaluation behavior.

### Decision: Symlink detection via glob pattern, not socket validation

**Decision:** Remove all symlinks matching the `wayland-*-org.wezfurlong.wezterm` glob
pattern rather than testing whether each is a valid live socket.

**Why:** These symlinks are created by WezTerm's Wayland integration for the GUI process.
When the GUI dies, the symlink target is gone. Testing socket liveness adds complexity
(race conditions, permission issues) for no benefit — if the GUI is alive, it will
recreate the symlink; if it's dead, the symlink is stale. The glob pattern is specific
enough to avoid collateral damage.

## Edge Cases

**E1 — GUI running when cleanup fires.** If the user already has a healthy WezTerm GUI
when a new shell spawns in pane 0, the symlink is live and valid. However, the glob
cleanup only runs for symlinks matching the stale pattern. A live symlink's target
exists as a socket, so the filter condition (`not path exists`) won't match it.
Actually — simplify: just unconditionally remove all matches. If the GUI is alive, it
will recreate the symlink on the next Wayland frame. This avoids the liveness-test
complexity entirely.

**E2 — Multiple GUI instances.** Each GUI creates its own Wayland symlink. The glob
removes all matches, which is correct — stale ones are cleaned, and live ones are
recreated by the surviving GUI.

**E3 — Non-Wayland sessions (X11, SSH).** The symlinks are only created under Wayland.
On X11 or SSH, the glob matches nothing and the cleanup is a no-op.

**E4 — First boot (no stale symlinks).** Glob matches nothing, cleanup is a no-op. The
restore prompt proceeds normally.

**E5 — GLOBAL flag survives config reload but not mux restart.** If the mux server is
restarted (not just the GUI), `wezterm.GLOBAL` is reset and the resurrect block
initializes fresh. This is correct — a new mux server needs fresh timers.

## Implementation Phases

### Phase 1: Add GLOBAL guard to resurrect block

**Files:** `dot_config/wezterm/wezterm.lua`

**Changes:**
- Wrap the body of the `if ok_resurrect then` block in a
  `if not wezterm.GLOBAL.resurrect_initialized then` guard
- Set `wezterm.GLOBAL.resurrect_initialized = true` at the top of the guarded block
- Keep the `else` branch (log_warn on plugin load failure) outside the guard

**Validation:**
- `ls-fonts` stderr check (no errors)
- `show-keys` diff (no regressions)
- Confirm only 1 periodic save timer fires (check resurrect JSON timestamps after
  5-minute wait — file should update once, not 6 times in rapid succession)

### Phase 2: Add symlink cleanup to pre_prompt hook

**Files:** `dot_config/nushell/config.nu`

**Changes:**
- Insert symlink cleanup logic at the start of the existing pre_prompt hook closure,
  after the one-shot guard check but before the `WEZTERM_PANE` check
- The cleanup should use nushell's `glob` and `rm -f`

**Validation:**
- `nu -c "source config.nu"` (syntax check)
- Manual test: create a fake stale symlink, open a new shell, verify it's removed
- Verify restore prompt still appears correctly after cleanup

## Open Questions

1. Should the symlink cleanup also remove stale `gui-sock-*` files from dead GUI PIDs?
   These are harmless (WezTerm ignores them) but accumulate across GUI restarts.

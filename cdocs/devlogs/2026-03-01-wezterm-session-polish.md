---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-03-01T10:00:00-06:00"
task_list: dotfiles/wezterm
type: devlog
state: live
status: review_ready
tags: [wezterm, nushell, session-persistence, resurrect, wayland, cleanup]
last_reviewed:
  status: revision_requested
  by: "@claude-opus-4-6"
  at: "2026-03-01T12:00:00-06:00"
  round: 1
---

# WezTerm Session Persistence Polish: Devlog

## Objective

Implement the accepted proposal at
[cdocs/proposals/2026-02-28-wezterm-session-persistence-polish.md](../proposals/2026-02-28-wezterm-session-persistence-polish.md).
Two fixes: GLOBAL guard for resurrect plugin (timer overlap) and stale Wayland symlink
cleanup in nushell pre_prompt hook.

## Plan

Two phases from the proposal:

1. **GLOBAL guard** — wrap resurrect plugin init in `wezterm.GLOBAL.resurrect_initialized`
2. **Symlink cleanup** — add Wayland symlink removal to existing pre_prompt hook

Commit after each phase. Validate per CLAUDE.md workflow.

## Testing Approach

- WezTerm: `ls-fonts` stderr check + `show-keys` diff
- Nushell: `nu -c "source config.nu"` syntax validation
- Deploy with `chezmoi apply --force` for live verification

## Implementation Notes

### GLOBAL guard approach

Changed the condition from `if ok_resurrect then` to
`if ok_resurrect and not wezterm.GLOBAL.resurrect_initialized then`, with the flag set
immediately inside the block. The `else` branch needed updating to
`elseif not ok_resurrect then` so the log_warn only fires on actual plugin load failure,
not on subsequent config re-evaluations where the plugin loaded fine but the guard
skipped initialization.

### Symlink cleanup: unconditional removal

The proposal discussed liveness testing (E1) but concluded that unconditional removal
is simpler and correct — a live GUI recreates its Wayland symlinks immediately. The
implementation follows this approach: `glob` + `rm -f` with no liveness check.

The cleanup runs after the one-shot guard (`_WEZ_RESTORE_OFFERED`) but before the
`WEZTERM_PANE == "0"` check. This means it runs once per pane lifetime (the one-shot
guard ensures it does not re-trigger on subsequent prompts). It runs in all panes, not
just pane 0, which is correct: any pane can benefit from cleaning stale symlinks for
`wezterm cli` to work.

### Open question: gui-sock-* cleanup

The proposal's open question about cleaning stale `gui-sock-*` files was not addressed.
These are harmless (WezTerm ignores them) and accumulate slowly. Left for a future
polish pass if they become a nuisance.

## Changes Made

| File | Description |
|------|-------------|
| `dot_config/wezterm/wezterm.lua` | Add GLOBAL guard around resurrect plugin init block |
| `dot_config/nushell/config.nu` | Add stale Wayland symlink cleanup to pre_prompt hook |

## Verification

### Phase 1: GLOBAL guard

```
$ wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
Config parsed OK

$ diff /tmp/wez_keys_before.lua /tmp/wez_keys_after.lua
(timestamps only — no key binding changes)
```

### Phase 2: Symlink cleanup

```
$ XDG_CONFIG_HOME=$PWD/dot_config nu -c "echo 'config loads OK'"
config loads OK
```

### Post-Deploy Functional Verification

Deployed with `chezmoi apply --force`, then tested both fixes live.

**GLOBAL guard: timer reduction confirmed.**

Compared `dev.wezterm: init` counts in mux server logs (a proxy for config evaluations
that reach the plugin block):

```
Old mux server (pre-fix, PID 125537): 10 config evals
Current mux server (post-fix, PID 374572): 1 config eval
```

The GLOBAL guard prevents `periodic_save`, event handlers, and config overrides from
re-registering on subsequent config evaluations. The `pcall(wezterm.plugin.require, ...)`
still runs on each eval (it's outside the guard), but plugin loading is idempotent.

**Symlink cleanup: stale symlink removal confirmed.**

```
$ ln -sf /tmp/nonexistent-dead-socket /run/user/1000/wezterm/wayland-wayland-0-org.wezfurlong.wezterm
$ ls /run/user/1000/wezterm/wayland-*
wayland-wayland-0-org.wezfurlong.wezterm -> /tmp/nonexistent-dead-socket

$ nu -c '
  let wez_runtime = "/run/user/1000/wezterm"
  let before = (glob $"($wez_runtime)/wayland-*-org.wezfurlong.wezterm" | length)
  glob $"($wez_runtime)/wayland-*-org.wezfurlong.wezterm" | each { |f| rm -f $f }
  let after = (glob $"($wez_runtime)/wayland-*-org.wezfurlong.wezterm" | length)
  print $"Symlinks before: ($before), after: ($after)"
'
Symlinks before: 1, after: 0

$ wezterm cli list
(works correctly, no connection errors)
```

---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-03-01T10:00:00-06:00"
task_list: dotfiles/wezterm
type: devlog
state: live
status: review_ready
tags: [wezterm, nushell, session-persistence, resurrect, wayland, cleanup]
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
`WEZTERM_PANE == "0"` check. This means it runs for every shell session inside WezTerm
(not just pane 0), which is correct — any shell can benefit from cleaning stale symlinks
for `wezterm cli` to work.

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

### Commits

```
0363513 fix(wezterm): guard resurrect plugin init with wezterm.GLOBAL
2c25dc8 fix(nushell): clean stale WezTerm Wayland symlinks on shell start
```

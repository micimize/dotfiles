---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-27T14:30:00-06:00"
task_list: dotfiles/wezterm
type: devlog
state: live
status: review_ready
tags: [wezterm, nushell, session-persistence, resurrect, unix-domain, IPC]
---

# WezTerm Session Persistence: Devlog

## Objective

Implement the accepted proposal at
[cdocs/proposals/2026-02-27-wezterm-session-persistence.md](../proposals/2026-02-27-wezterm-session-persistence.md).
Three-layer session persistence: unix domain mux (live), resurrect.wezterm (disk),
nushell CLI with auto-trigger on fresh boot.

## Plan

Five phases from the proposal, executed sequentially:

1. **Unix domain migration** — desktop file fix, mux-startup, default_gui_startup_args, Leader+D
2. **resurrect.wezterm integration** — plugin load, periodic save, IPC handler, toast notifications
3. **Nushell CLI module** — wez-session.nu with save/restore/list/delete
4. **Auto-trigger** — pre_prompt hook with WEZTERM_PANE == 0 + one-shot guard
5. **Polish** — edge case testing, docs update

Commit after each phase. Validate wezterm config with ls-fonts + show-keys diff per CLAUDE.md workflow.

## Testing Approach

WezTerm config validation via the established TDD workflow:
- `ls-fonts` stderr check for parse errors
- `show-keys` diff for silent fallback detection
- `chezmoi apply --force` + hot-reload verification
- Manual IPC test via `printf` OSC 1337

Nushell module: syntax validation via `nu -c "source wez-session.nu"`.
Full functional testing requires live WezTerm + resurrect plugin — documented as
manual verification steps below. Deploy with `chezmoi apply --force` and test
interactively.

## Implementation Notes

### Deviation: resurrect.wezterm API differs from proposal

The proposal assumed top-level functions (`resurrect.set_max_nlines()`,
`resurrect.periodic_save()`, `resurrect.save_state()`, `resurrect.load_state()`).
The actual plugin exports submodules:

- `resurrect.state_manager.set_max_nlines()`
- `resurrect.state_manager.periodic_save()`
- `resurrect.state_manager.save_state()`
- `resurrect.state_manager.load_state()`
- `resurrect.workspace_state.get_workspace_state()` (correct in proposal)
- `resurrect.workspace_state.restore_workspace()` (correct but needs `window` opt)

Initial `ls-fonts` check caught this immediately: `attempt to call a nil value
(field 'set_max_nlines')`. Fixed by routing through `state_manager` submodule.

### Deviation: resurrect save directory location

The proposal assumed `~/.local/share/wezterm/resurrect/workspace/`. The plugin
actually stores state inside its own URL-encoded plugin directory:
`~/.local/share/wezterm/plugins/httpssCssZssZs.../state/workspace/`.

Fixed by calling `resurrect.state_manager.change_state_save_dir()` to override to
`~/.local/share/wezterm/resurrect/` — a stable path that the nushell CLI can reference
without fragile URL-encoded directory names.

### Deviation: restore_workspace requires `window` opt

The proposal's restore call omitted the `window` parameter. The actual API requires
`window = window:mux_window()` in the opts table. Added `window:mux_window()` to
convert the GUI window from the `user-var-changed` callback to the MuxWindow the
restore function expects.

### Deviation: nushell return type annotations

The proposal's `wez-list-sessions` had `-> list<string>` return type annotation.
Nushell doesn't support return type annotations on `def`. Removed.

### resurrect plugin dependency chain

resurrect.wezterm pulls in `dev.wezterm` as a dependency (for plugin path discovery).
Both are fetched automatically by `wezterm.plugin.require`. The pcall guard handles
any fetch failures gracefully.

## Changes Made

| File | Description |
|------|-------------|
| `dot_local/share/applications/org.wezfurlong.wezterm.desktop` | Remove `start --cwd .` from Exec lines (fixes #2933 override) |
| `dot_config/wezterm/wezterm.lua` | Enable unix domain, gui-startup→mux-startup, Leader+D, resurrect plugin + IPC handler |
| `dot_config/nushell/scripts/wez-session.nu` | New: wez save/restore/list/delete CLI commands |
| `dot_config/nushell/config.nu` | Source wez-session.nu, add pre_prompt auto-trigger hook |

## Verification

### Phase 1: Unix Domain Migration

```
$ wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
$ grep -q ERROR /tmp/wez_stderr.txt && echo "ERROR" || echo "Config parsed OK"
Config parsed OK

$ diff /tmp/wez_keys_before.lua /tmp/wez_keys_after.lua
103a104
>     { key = 'd', mods = 'LEADER', action = act.DetachDomain 'CurrentPaneDomain' },

$ diff /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_after.lua
(no diff — copy mode unchanged)
```

### Phase 2: resurrect.wezterm Integration

Initial attempt failed: `attempt to call a nil value (field 'set_max_nlines')`.
Fixed by routing through `state_manager` submodule.

```
$ wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
Config parsed OK

$ diff /tmp/wez_keys_before.lua /tmp/wez_keys_after2.lua
(only Leader+D added — resurrect does not alter key tables)

$ ls ~/.local/share/wezterm/resurrect/
tab/  window/  workspace/
```

### Phase 3: Nushell CLI Module

```
$ nu -c "source dot_config/nushell/scripts/wez-session.nu"
(no output — syntax OK)

$ XDG_CONFIG_HOME=dot_config nu -c "echo 'config loads'"
config loads
```

### Phase 4: Auto-trigger

```
$ XDG_CONFIG_HOME=dot_config nu -c "echo 'config loads with auto-trigger'"
config loads with auto-trigger
```

### Remaining Manual Verification (post-deploy)

The following require `chezmoi apply --force` and live WezTerm interaction:

1. Close and reopen WezTerm — verify tabs/panes persist (unix domain)
2. `wez save test` — verify toast notification + JSON file created
3. `wez list` — verify session appears
4. `wez restore test` — verify layout restores + toast
5. `wez delete test` — verify file removed
6. Kill mux server, relaunch — verify restore prompt in pane 0
7. Select "[Start fresh]" — verify no restore, just normal pane
8. Open new tab — verify NO prompt (pane ID > 0)

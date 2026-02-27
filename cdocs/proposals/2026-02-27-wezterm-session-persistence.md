---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-27T12:00:00-06:00"
task_list: dotfiles/wezterm
type: proposal
state: live
status: implementation_wip
tags: [wezterm, nushell, session-persistence, resurrect, unix-domain, IPC]
last_reviewed:
  status: accepted
  by: "@claude-opus-4-6"
  at: "2026-02-27T13:00:00-06:00"
  round: 2
---

# WezTerm Session Persistence: Unix Domain + Resurrect + Nushell CLI

> BLUF: Combine WezTerm's built-in unix domain multiplexer (live persistence across
> GUI close/reopen) with the [resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm)
> plugin (cross-reboot disk serialization) and a nushell CLI module (`wez save/restore/list/delete`)
> that communicates with WezTerm via OSC 1337 user variable IPC. Auto-trigger restore on
> fresh sessions via a `pre_prompt` hook that checks `$env.WEZTERM_PANE == "0"` with a
> one-shot guard — pane 0 only exists as the first pane of a fresh mux server. No
> keybindings for session management; a `Leader+D` DetachDomain binding provides
> tmux-like explicit detach. WezTerm shows toast notifications on save/restore
> completion. Prior analysis in
> [cdocs/reports/2026-02-22-wezterm-session-restore.md](../reports/2026-02-22-wezterm-session-restore.md).

## Objective

Provide two-layer session persistence for WezTerm:

1. **Live persistence** (unix domain): tabs, panes, splits, scrollback, and running
   processes survive GUI close/reopen without disk I/O. Lost only on logout/reboot.
2. **Cross-reboot persistence** (resurrect.wezterm): workspace layouts and working
   directories serialized to JSON on disk. Restored automatically on fresh boot when
   saved sessions exist, or manually via `wez restore`.

All user interaction happens through nushell commands, not WezTerm keybindings.

## Background

### Current State

The wezterm config (`dot_config/wezterm/wezterm.lua`) already declares a unix domain
but never connects to it:

```lua
config.unix_domains = {
  { name = "unix" },
}
-- Uncomment to auto-connect to mux on startup
-- config.default_gui_startup_args = { "connect", "unix" }
```

The desktop file (`dot_local/share/applications/org.wezfurlong.wezterm.desktop`) passes
`start --cwd .`, which overrides `default_gui_startup_args` entirely (WezTerm issue
[#2933](https://github.com/wezterm/wezterm/issues/2933)). The `gui-startup` event
handler creates a "main" workspace but will not fire in `connect` mode.

Nushell is the default shell, with a modular config under `dot_config/nushell/scripts/`.
No session management module exists. The `login.nu` file has a commented-out tmux
auto-attach pattern, showing prior awareness of login-time session initialization.

### Why Two Layers

Unix domain alone does not survive reboot. Resurrect alone does not preserve running
processes or scrollback between GUI restarts. Together they provide complementary
coverage:

| Scenario | Unix Domain | Resurrect |
|----------|-------------|-----------|
| Close GUI, reopen | Fully preserved (processes, scrollback, everything) | N/A |
| Logout/reboot | Lost | Restores layout, cwd, optionally scrollback |
| GUI crash | Fully preserved (mux server independent) | N/A |
| Mux server crash | Lost | Restores from last periodic save |

The documented "incompatibility" between resurrect and unix domains only applies when
restoring INTO a populated mux. On a fresh boot, the mux server starts empty, and
resurrect restores into that empty state without conflict.

### IPC: Shell to WezTerm

WezTerm has no `wezterm cli emit` command (issue
[#6879](https://github.com/wezterm/wezterm/issues/6879)). The sanctioned workaround is
OSC 1337 SetUserVar escape sequences, which WezTerm intercepts and fires as
`user-var-changed` Lua events:

```bash
printf "\033]1337;SetUserVar=%s=%s\007" KEY "$(echo -n 'value' | base64)"
```

This pattern is already proven in the codebase: smart-splits uses the `IS_NVIM` user
variable for cross-tool pane detection.

## Proposed Solution

### Architecture

```
Layer 1: Unix Domain Mux (live persistence)
  wezterm.lua: default_gui_startup_args = { "connect", "unix" }
  Desktop file: bare `wezterm` (no `start --cwd .`)
  Event: gui-startup → mux-startup migration

Layer 2: resurrect.wezterm (disk persistence)
  wezterm.lua: plugin load, periodic_save, user-var-changed IPC handler
  Storage: ~/.local/share/wezterm/resurrect/workspace/*.json

Layer 3: Nushell CLI + Auto-trigger
  wez-session.nu: wez save/restore/list/delete commands
  config.nu: pre_prompt hook with WEZTERM_PANE == 0 + one-shot guard
```

### Layer 1: Unix Domain Migration

**1a. Desktop file fix** — `dot_local/share/applications/org.wezfurlong.wezterm.desktop`:

```diff
-Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start --cwd .
+Exec=/home/linuxbrew/.linuxbrew/bin/wezterm
```

Also update the `new-window` action:

```diff
 [Desktop Action new-window]
 Name=New Window
-Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start
+Exec=/home/linuxbrew/.linuxbrew/bin/wezterm
```

The `new-tab` action (`wezterm cli spawn`) is correct as-is.

**1b. Enable auto-connect** — uncomment in wezterm.lua:

```lua
config.default_gui_startup_args = { "connect", "unix" }
```

**1c. Migrate gui-startup to mux-startup** — remove the existing `gui-startup` handler
and its `GLOBAL.gui_startup_registered` guard entirely. Replace with:

```lua
-- mux-startup fires once when the mux server first starts.
-- Does NOT fire on GUI reconnect — only on initial server spawn.
wezterm.on("mux-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)
```

The `gui-startup` handler is dead code in connect mode (never fires). Remove it rather
than leave it alongside `mux-startup` — dead code in the config is a maintenance hazard.

**1d. DetachDomain keybinding**

```lua
{ key = "d", mods = "LEADER", action = act.DetachDomain 'CurrentPaneDomain' },
```

Tmux-like explicit detach (Leader+D). Closing the window also detaches cleanly in
connect mode, but the explicit binding provides a familiar affordance.

### Layer 2: resurrect.wezterm Integration

> NOTE: The code snippets below were corrected during implementation.
> The plugin exports submodules (`state_manager`, `workspace_state`, etc.), not
> top-level functions. The save directory defaults to the URL-encoded plugin path;
> we override to `~/.local/share/wezterm/resurrect/` for stable shell-side access.
> See devlog for details.

**2a. Plugin load** — follows the existing lace plugin pcall-guard pattern:

```lua
local ok_resurrect, resurrect = pcall(
  wezterm.plugin.require,
  "https://github.com/MLFlexer/resurrect.wezterm"
)

if ok_resurrect then
  resurrect.state_manager.change_state_save_dir(
    wezterm.home_dir .. "/.local/share/wezterm/resurrect/"
  )
  resurrect.state_manager.set_max_nlines(5000)

  resurrect.state_manager.periodic_save({
    interval_seconds = 300,
    save_workspaces = true,
    save_windows = true,
    save_tabs = true,
  })
end
```

**2b. IPC handler** — receives commands from nushell via OSC 1337 user variables.

Each IPC value includes a nonce suffix (e.g., `save|main|a3f8`) to ensure
`user-var-changed` fires even for repeated identical commands. WezTerm only fires the
event when the value actually changes — without a nonce, running `wez save` twice
would silently drop the second invocation.

The handler also shows toast notifications via `window:toast_notification()` so the
user gets visual feedback on save/restore completion.

```lua
if ok_resurrect then
  -- Parse IPC command: "action|arg|nonce" → action, arg
  local function parse_ipc(value)
    local parts = {}
    for part in value:gmatch("[^|]+") do
      table.insert(parts, part)
    end
    return parts[1] or "", parts[2] or ""
  end

  wezterm.on('user-var-changed', function(window, pane, name, value)
    if name ~= "WEZ_SESSION_CMD" then return end
    local action, arg = parse_ipc(value)

    if action == "save" then
      local state = resurrect.workspace_state.get_workspace_state()
      if arg ~= "" then
        resurrect.state_manager.save_state(state, arg)
      else
        resurrect.state_manager.save_state(state)
      end
      local label = arg ~= "" and arg or window:active_workspace()
      window:toast_notification("wezterm", "Session saved: " .. label, nil, 3000)

    elseif action == "restore" then
      local state = resurrect.state_manager.load_state(arg, "workspace")
      if state and state.workspace then
        resurrect.workspace_state.restore_workspace(state, {
          window = window:mux_window(),
          relative = true,
          restore_text = true,
          close_open_tabs = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        })
        window:toast_notification("wezterm", "Session restored: " .. arg, nil, 3000)
      else
        window:toast_notification("wezterm", "No saved session: " .. arg, nil, 3000)
      end
    end
  end)

  wezterm.on("resurrect.error", function(err)
    wezterm.log_error("resurrect error: " .. tostring(err))
  end)
end
```

WezTerm decodes the base64 from the OSC 1337 sequence before firing the event, so
`value` is the original command string. The `parse_ipc` helper splits on `|` and
discards the nonce (third field).

### Layer 3: Nushell CLI + Auto-trigger

**3a. New module: `dot_config/nushell/scripts/wez-session.nu`**

```nushell
# WezTerm session persistence commands
# Uses OSC 1337 SetUserVar to communicate with WezTerm's resurrect plugin.
# IPC protocol: "action|arg|nonce" — nonce ensures user-var-changed fires
# even for repeated identical commands. WezTerm Lua strips the nonce.
# Helper functions (wez-ipc, wez-list-sessions) are non-exported; they are
# accessible in config.nu because we use `source` (not `use`). If migrating
# to `use`, these must be exported or the auto-trigger refactored.

const WEZ_SESSION_DIR = "~/.local/share/wezterm/resurrect/workspace"

# Send a command to WezTerm via OSC 1337 user variable IPC
def wez-ipc [action: string, arg?: string] {
  if ($env.TERM_PROGRAM? | default "") != "WezTerm" {
    error make { msg: "wez commands only work inside WezTerm" }
  }
  let nonce = (random chars -l 8)
  let payload = ([$action, ($arg | default ""), $nonce] | str join "|")
  let encoded = ($payload | encode base64)
  print -n $"\u{1b}]1337;SetUserVar=WEZ_SESSION_CMD=($encoded)\u{07}"
}

# List saved session names from disk (no IPC needed)
def wez-list-sessions [] {
  let dir = ($WEZ_SESSION_DIR | path expand)
  if not ($dir | path exists) { return [] }
  ls $dir
    | where name =~ '\.json$'
    | get name
    | each { |f| $f | path parse | get stem }
}

# Save the current workspace session
export def "wez save" [
  name?: string  # Session name (defaults to current workspace name)
] {
  wez-ipc "save" $name
}

# Restore a saved session (interactive picker if no name given)
export def "wez restore" [
  name?: string  # Session name to restore
] {
  let target = if ($name | is-not-empty) {
    $name
  } else {
    let sessions = (wez-list-sessions)
    if ($sessions | is-empty) {
      print "No saved sessions found."
      return
    }
    let choice = ($sessions | input list "Select session to restore:")
    if ($choice | is-empty) {
      print "Cancelled."
      return
    }
    $choice
  }
  wez-ipc "restore" $target
}

# List saved sessions
export def "wez list" [] {
  let sessions = (wez-list-sessions)
  if ($sessions | is-empty) {
    print "No saved sessions."
    return
  }
  let dir = ($WEZ_SESSION_DIR | path expand)
  ls $dir
    | where name =~ '\.json$'
    | select name modified
    | update name { path parse | get stem }
    | rename session modified
    | sort-by modified -r
}

# Delete a saved session
export def "wez delete" [
  name: string  # Session name to delete
] {
  let file = ([$WEZ_SESSION_DIR, $"($name).json"] | path join | path expand)
  if ($file | path exists) {
    rm $file
    print $"Deleted session: ($name)"
  } else {
    print $"Session not found: ($name)"
  }
}
```

**3b. Source from config.nu** — add after existing script sources:

```nushell
source ($nu.default-config-dir | path join "scripts/wez-session.nu")
```

**3c. Auto-trigger on fresh session** — add a `pre_prompt` hook in `config.nu`:

The auto-trigger uses a `pre_prompt` hook rather than inline `config.nu` code because
nushell does not guarantee interactive I/O (like `input list`) during config evaluation.
The `pre_prompt` hook fires after init but before the first prompt, when the TTY is
fully ready.

A one-shot guard (`$env._WEZ_RESTORE_OFFERED`) prevents re-triggering on subsequent
prompts, shell re-exec (`exec nu`), or manual config re-source.

```nushell
# ── WezTerm session restore on fresh boot ──
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt? | default [])
$env.config.hooks.pre_prompt ++= [{||
  # One-shot: only offer once per shell lifetime
  if ($env._WEZ_RESTORE_OFFERED? | default false) { return }
  $env._WEZ_RESTORE_OFFERED = true

  # Only in fresh WezTerm pane 0 (first pane of a fresh mux server)
  if ($env.WEZTERM_PANE? | default "") != "0" { return }

  let sessions = (wez-list-sessions)
  if ($sessions | is-empty) { return }

  let choices = ($sessions | append "[Start fresh]")
  let selection = ($choices | input list "Restore a saved WezTerm session?")
  if ($selection | is-not-empty) and ($selection != "[Start fresh]") {
    wez-ipc "restore" $selection
  }
}]
```

### Fresh Session Detection: `WEZTERM_PANE == 0` + One-Shot Guard

WezTerm assigns monotonically increasing pane IDs starting from 0 on a fresh mux
server. `$env.WEZTERM_PANE` is set in each pane's environment. Combined with a
`_WEZ_RESTORE_OFFERED` one-shot env flag, this provides a reliable trigger:

- **Fresh boot, new mux server:** pane 0 created → trigger fires once → flag set
- **New tab/split:** pane ID > 0 → no trigger
- **GUI close + reopen (unix domain):** reconnects to existing mux → no new pane → no trigger
- **After restore (`close_open_tabs`):** pane 0 closed, restored panes get IDs > 0
- **Next boot:** fresh mux again → pane 0 again → flag reset (new process) → trigger fires
- **Shell re-exec (`exec nu`):** inherits WEZTERM_PANE=0 but flag is NOT inherited
  (new nushell process) → trigger fires again

> NOTE: The `exec nu` re-trigger is an acceptable trade-off. The `_WEZ_RESTORE_OFFERED`
> flag prevents re-triggering on every prompt (the `pre_prompt` hook fires repeatedly).
> It does NOT persist across `exec nu` because nushell processes do not export runtime
> `$env` changes to child processes via the OS environment. If `exec nu` re-triggering
> proves annoying, a marker file (`~/.cache/wez-restore-offered`) gated on mux server
> PID could provide a persistent one-shot, but the added complexity is not justified for
> a personal config.

## Important Design Decisions

### D1: CLI for session management, Leader+D for domain lifecycle

**Decision:** All save/restore via nushell commands; no keybindings for session
management. `Leader+D` is added for DetachDomain — a domain lifecycle operation (like
tmux `prefix+d`), not session management.

**Why:** Session management is infrequent, not a hot-path operation. The nushell CLI
provides richer feedback (toast notifications, interactive lists, error messages) and
is discoverable via tab completion. WezTerm's leader key namespace stays uncluttered
for navigation and workspace actions. DetachDomain is a different category — it's a
quick "disconnect without killing" action that benefits from a keybinding.

### D2: Single user var with nonce-suffixed commands

**Decision:** One user variable (`WEZ_SESSION_CMD`) with pipe-delimited values:
`action|arg|nonce` (e.g., `save|main|a3f8b2c1`, `restore|feature|9e2d1a7f`).

**Why:** Simpler than multiple vars. Extensible without adding new var names. The nonce
(8 random chars) ensures `user-var-changed` fires even for repeated identical commands
— WezTerm only fires the event when the value actually changes, so `save||` twice
would silently drop the second invocation without a unique nonce. The Lua handler
parses on `|` and discards the nonce.

### D3: Direct filesystem for list/delete

**Decision:** `wez list` and `wez delete` read/write the resurrect save directory
directly, bypassing IPC.

**Why:** Listing files and deleting JSON do not require WezTerm state. Direct access
is faster and works even if WezTerm's Lua runtime has issues. The save directory path
(`~/.local/share/wezterm/resurrect/workspace/`) is stable and documented.

### D4: nushell `input list` over WezTerm InputSelector

**Decision:** Interactive picker uses nushell's `input list`, not resurrect's
`fuzzy_load()` modal.

**Why:** Consistent with CLI-first design. `input list` integrates with nushell's
keybindings and can be piped/scripted. The WezTerm modal cannot be triggered from the
shell without a keybinding.

### D5: Periodic save, not save-on-close

**Decision:** `periodic_save()` at 5-minute intervals.

**Why:** WezTerm has no reliable "about to close" event that fires before mux state
teardown. Periodic save is the proven approach (tmux-continuum pattern). Manual
`wez save` supplements for explicit checkpoints.

### D6: Unix domain + resurrect as complementary layers

**Decision:** Use both, not one or the other.

**Why:** The documented "incompatibility" only applies when restoring into a populated
mux. On fresh boot, the mux is empty — resurrect restores into it without conflict.
During normal operation, the unix domain handles live persistence (processes, scrollback)
while resurrect periodically snapshots to disk for reboot recovery.

> NOTE: This claim is plausible but not yet verified against resurrect's serialized
> JSON. If resurrect embeds domain-specific metadata (e.g., pane domain names like
> `unix` or lace SSH domains), cross-boot restore could partially fail when those
> domains do not exist yet. Phase 2 testing must inspect saved JSON to confirm resurrect
> stores only layout geometry and working directories, not domain affinity.

## Edge Cases / Challenging Scenarios

### E1: Auto-save capturing empty state / overwriting good sessions

After boot, the mux has a single empty pane. If periodic save fires before the user
works (or before restore completes), it saves a trivially empty workspace, potentially
overwriting a meaningful previously-saved session.

Additionally, if the user declines the restore offer and starts working, the next
periodic save (5 minutes later) overwrites the saved session with whatever the user
has built in those 5 minutes — the declined session is not preserved.

**Mitigation:** 5-minute interval means the first save is 5 minutes post-boot. If
auto-restore fires promptly, the restored state replaces the empty state before the
first periodic save. A min-panes guard in the periodic save callback (skip save if
only one pane with an empty working directory) could provide additional safety.

### E2: User declines restore offer

Selecting "[Start fresh]" or dismissing `input list` leaves pane 0 as the working
pane. Next boot offers again (saved sessions still exist on disk). If the user never
wants the offer, they can `wez delete` all sessions.

### E3: resurrect plugin load failure

The pcall guard ensures config evaluation succeeds. The nushell CLI commands still
execute (OSC 1337 is sent), but WezTerm silently ignores them since no
`user-var-changed` handler is registered. `wez list` and `wez delete` still work
(filesystem access).

### E4: IS_NVIM user var lost on mux reattach

Known issue ([#5832](https://github.com/wezterm/wezterm/issues/5832)). When the GUI
reconnects to the mux, user variables are lost. Smart-splits `IS_NVIM` detection
breaks until a `FocusGained` autocmd re-sets the var. Orthogonal to session persistence
but an interaction to monitor. PR #7610 may fix this upstream.

### E5: `input list` timing (resolved)

Nushell does not guarantee interactive I/O during `config.nu` evaluation. The auto-trigger
uses a `pre_prompt` hook instead, which fires after init when the TTY is fully ready.
See section 3c.

### E6: Pane 0 closing mid-prompt during restore

When the user selects a session, the OSC 1337 fires, WezTerm's `user-var-changed`
handler triggers `restore_workspace` with `close_open_tabs = true`, which closes
pane 0 (killing the nushell process mid-command). The restore runs in WezTerm Lua (not
the shell), so it completes regardless. Brief visual flash as the initial pane
disappears and the restored layout appears.

### E7: OSC 1337 in non-WezTerm terminals

The `wez-ipc` helper guards on `$env.TERM_PROGRAM == "WezTerm"` and raises an error
if run outside WezTerm. The auto-trigger also guards on `$env.WEZTERM_PANE?`.

### E8: Multiple workspaces

`wez save` (no args) saves the current workspace. Periodic save with
`save_workspaces = true` saves all workspaces automatically. The auto-trigger lists
all saved workspace files, allowing the user to pick which to restore.

## Test Plan

### Phase 1: Unix Domain

1. Run `ls-fonts` parse check with modified config
2. `chezmoi apply --force` and verify WezTerm hot-reloads
3. Close and reopen WezTerm — verify tabs/panes persist
4. `wezterm cli list` shows existing panes after reopen
5. Smart-splits navigation after reconnect (IS_NVIM behavior)

### Phase 2: resurrect.wezterm

1. `ls-fonts` stderr check (plugin load errors surface here)
2. `show-keys` diff (resurrect should not alter key tables)
3. Wait 5 minutes, verify JSON files in `~/.local/share/wezterm/resurrect/workspace/`
4. Test IPC via manual OSC 1337: `printf "\033]1337;SetUserVar=WEZ_SESSION_CMD=$(echo -n 'save||test123' | base64)\007"`
5. Inspect saved JSON to verify resurrect does not embed domain-specific references
   that would break cross-boot restore (validate D6 claim)

### Phase 3: Nushell CLI

1. `wez list` — shows sessions from periodic saves
2. `wez save test` — verify JSON file created
3. `wez restore test` — verify layout restores
4. `wez delete test` — verify JSON file removed
5. `wez restore` (no args) — verify interactive picker

### Phase 4: Auto-trigger

1. Save a session with `wez save`
2. Kill the mux server: `kill $(cat $XDG_RUNTIME_DIR/wezterm/pid)`
3. Relaunch WezTerm — verify restore prompt appears in pane 0
4. Select a session — verify layout restores and pane 0 disappears
5. Close and reopen GUI (without killing mux) — verify NO prompt
6. Open new tab — verify NO prompt (pane ID > 0)
7. In pane 0, run `exec nu` — verify the one-shot guard prevents re-trigger
   on second prompt (first prompt after exec will re-trigger since
   `_WEZ_RESTORE_OFFERED` is not inherited)
8. Run `wez save` twice in rapid succession — verify both saves execute
   (nonce ensures `user-var-changed` fires both times)

## Implementation Phases

### Phase 1: Unix Domain Migration

**Files:**
- `dot_local/share/applications/org.wezfurlong.wezterm.desktop` — remove `start --cwd .`
- `dot_config/wezterm/wezterm.lua` — uncomment `default_gui_startup_args`, remove
  `gui-startup` handler and its `GLOBAL` guard, add `mux-startup` handler, add
  `Leader+D` DetachDomain keybinding

**Constraints:** Do not modify existing keybindings. Do not change the lace plugin
section or smart-splits integration. Apply desktop file + config changes atomically
(single commit + `chezmoi apply`) to avoid partial-update inconsistency.

**Rollback:** Re-comment `default_gui_startup_args`, restore desktop file Exec line.

### Phase 2: resurrect.wezterm Integration

**Files:**
- `dot_config/wezterm/wezterm.lua` — add resurrect plugin load (pcall guard),
  periodic_save, user-var-changed IPC handler, error event handler

**Constraints:** Follow the existing lace plugin pattern (pcall + conditional config).
Place the resurrect section after lace but before copy mode customization.

**Rollback:** Remove resurrect plugin block. pcall guard ensures no config breakage.

### Phase 3: Nushell CLI Module

**Files:**
- `dot_config/nushell/scripts/wez-session.nu` — create
- `dot_config/nushell/config.nu` — add `source` line

**Constraints:** Do not modify existing nushell modules (hooks.nu, utils.nu, etc.).

### Phase 4: Auto-trigger on Fresh Session

**Files:**
- `dot_config/nushell/config.nu` — add `pre_prompt` hook with one-shot guard

**Constraints:** Must run after `wez-session.nu` is sourced (so `wez-list-sessions` and
`wez-ipc` are in scope via `source`). The `pre_prompt` hook fires after init when the
TTY is ready, avoiding the `input list` timing issue.

### Phase 5: Polish

- Tab completion for `wez` subcommands (nushell custom completions)
- Test edge cases E1-E8
- Update `CLAUDE.md` if session persistence changes the WezTerm validation workflow

## Resolved Questions

1. ~~**`input list` during `config.nu`**~~ — Resolved: use `pre_prompt` hook. Nushell
   does not guarantee interactive I/O during config evaluation.

2. ~~**Pane 0 closing mid-prompt UX**~~ — Resolved: acceptable. Brief visual flash as
   pane 0 is replaced by the restored layout. Restore runs in WezTerm Lua, unaffected
   by the nushell process dying.

3. ~~**DetachDomain keybinding**~~ — Resolved: yes, add Leader+D.

4. ~~**Save feedback**~~ — Resolved: WezTerm toast notification via
   `window:toast_notification()`. No reverse-IPC channel needed.

## Open Questions

1. **Min-panes guard on periodic save?** Prevents saving trivially empty workspaces
   after boot but requires wrapping `periodic_save` in a custom timer callback or
   hooking into resurrect's save events. Low priority — the 5-minute interval provides
   adequate mitigation for now.

2. **`exec nu` re-trigger in pane 0** — the one-shot `_WEZ_RESTORE_OFFERED` flag does
   not persist across `exec nu`. Acceptable for now; a marker file gated on mux PID
   could suppress if it proves annoying.

## Sources

- [Existing analysis: WezTerm Session Restore](../reports/2026-02-22-wezterm-session-restore.md)
- [resurrect.wezterm plugin](https://github.com/MLFlexer/resurrect.wezterm)
- [WezTerm Multiplexing docs](https://wezterm.org/multiplexing.html)
- [WezTerm user-var-changed event](https://wezterm.org/config/lua/window-events/user-var-changed.html)
- [OSC 1337 SetUserVar](https://wezterm.org/recipes/passing-data.html)
- [WezTerm issue #6879 — no cli emit](https://github.com/wezterm/wezterm/issues/6879)
- [WezTerm issue #2933 — desktop file overrides](https://github.com/wezterm/wezterm/issues/2933)
- [WezTerm issue #5832 — user vars lost on reattach](https://github.com/wezterm/wezterm/issues/5832)
- [wezterm-sessions plugin](https://github.com/abidibo/wezterm-sessions) (evaluated, not selected)
- [wezterm-session-manager](https://github.com/danielcopper/wezterm-session-manager) (evaluated, not selected)

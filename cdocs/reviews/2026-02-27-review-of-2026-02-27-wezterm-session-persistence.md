---
review_of: cdocs/proposals/2026-02-27-wezterm-session-persistence.md
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-27T12:00:00-06:00"
task_list: dotfiles/wezterm
type: review
state: live
status: done
tags: [fresh_agent, architecture, nushell, wezterm, session-persistence, IPC, edge_cases, unix-domain, resurrect]
---

# Review: WezTerm Session Persistence -- Unix Domain + Resurrect + Nushell CLI

## Summary Assessment

This proposal designs a two-layer session persistence system for WezTerm combining unix
domain multiplexing (live persistence) with the resurrect.wezterm plugin (disk
persistence), orchestrated by a nushell CLI module communicating via OSC 1337 IPC. The
overall architecture is well-reasoned and the proposal is exceptionally thorough in
cataloging edge cases. However, several technical claims deserve closer scrutiny: the
`WEZTERM_PANE == 0` freshness detection has a significant false-positive failure mode
that the proposal does not address, the nushell code has a parse-time versus runtime
correctness issue with `const` path declarations, the `input list` during `config.nu`
evaluation is almost certainly broken (the proposal acknowledges this but treats it as a
maybe), and the "complementary layers" claim about resurrect + unix domain compatibility
understates the timing risks. Verdict: **Revise** -- four blocking issues must be
addressed before implementation.

## Section-by-Section Findings

### BLUF

The BLUF is well-structured and leads with the right information. It correctly identifies
the three layers, the IPC mechanism, and the freshness detection approach. The reference
to prior analysis is appropriate.

One concern: the BLUF states "No leader-prefixed keybindings" as a design principle, but
the proposal includes an optional `Leader+D` DetachDomain binding in Layer 1. This is a
minor inconsistency in framing, not a technical issue.

**Category: non-blocking.** Clarify that "no keybindings for session management" is the
principle; the optional DetachDomain binding is a domain-lifecycle operation, not session
management.

### Objective

Clean and correctly scoped. The two-layer distinction (live vs. cross-reboot) is the
right framing.

**Category: no issues.**

### Background -- Current State

Verified against the actual codebase. The claims are accurate:

- `dot_config/wezterm/wezterm.lua` lines 151-156 confirm the unix domain is declared but
  the auto-connect is commented out.
- `dot_local/share/applications/org.wezfurlong.wezterm.desktop` line 9 confirms
  `Exec=wezterm start --cwd .`.
- The gui-startup handler exists at lines 501-509 with the `GLOBAL.gui_startup_registered`
  guard.
- `login.nu` lines 7-9 confirm the commented-out tmux auto-attach pattern.

**Category: no issues.**

### Background -- Why Two Layers

The compatibility table is clear and the coverage analysis is correct. However, the
claim that the "documented incompatibility between resurrect and unix domains only
applies when restoring INTO a populated mux" needs more scrutiny. See the D6 finding
below.

**Category: see D6 finding.**

### Background -- IPC: Shell to WezTerm

The OSC 1337 SetUserVar mechanism is correctly described. The reference to smart-splits
`IS_NVIM` as an existing pattern in the codebase is accurate -- `wezterm.lua` line 222
confirms `pane:get_user_vars().IS_NVIM == "true"`.

One important detail omitted: the `user-var-changed` event fires on the pane that emitted
the OSC sequence. If the user has multiple panes open and types `wez save` in pane 3, the
event fires with pane 3 as the context. The IPC handler uses
`window:active_workspace()` to determine the save name, not the pane that sent the
command. This should work correctly because `active_workspace()` is a window-level
property, but the distinction matters for the restore case -- `restore_workspace` operates
on the window containing the pane that fired the event, which may not be what the user
expects if they have multiple workspaces open.

**Category: non-blocking.** Document that `wez save/restore` operates on the workspace of
the window containing the active pane, not necessarily the "current" workspace in multi-
workspace setups.

### Layer 1: Unix Domain Migration

The four sub-steps (1a-1d) are well-scoped and verified against the actual files.

**1a (desktop file fix):** The diff is correct. Verified the current desktop file matches
the "before" state. The `new-tab` action using `wezterm cli spawn` is correctly identified
as not needing changes.

**1b (auto-connect):** Straightforward uncomment. Correct.

**1c (mux-startup migration):** The replacement handler is correct. The note about
dropping the `GLOBAL.gui_startup_registered` guard is accurate -- `mux-startup` fires
only on the mux server process. However, the proposal should explicitly state that the
old `gui-startup` handler must be *removed*, not just supplemented with `mux-startup`.
If both handlers remain, `gui-startup` is dead code (never fires in connect mode) but
its presence is confusing.

**1d (DetachDomain):** Correctly noted as optional. See BLUF finding above.

**Category: non-blocking.** Explicitly state that the `gui-startup` handler and its
`GLOBAL` guard should be removed, not just left as dead code.

### Layer 2: resurrect.wezterm Integration

**2a (plugin load):** The pcall guard pattern matches the existing lace plugin pattern at
`wezterm.lua` line 361. The `set_max_nlines(5000)` is reasonable for scrollback
preservation.

**2b (IPC handler):** The handler logic is structurally sound. The command parsing
(`save`, `save:name`, `restore:name`) is clean and extensible. However, there are two
concerns:

1. **No "delete" IPC command.** The nushell `wez delete` command bypasses IPC and deletes
   files directly. This is documented in D3 and is a valid design choice. However, the
   IPC handler should also handle a `delete:name` command for completeness, or the decision
   to exclude it should be more prominent.

2. **No feedback channel.** The `wez save` command prints "Session save triggered"
   immediately but the actual save is asynchronous (fire-and-forget OSC 1337). If the save
   fails (e.g., resurrect raises an error), the user sees success but the operation failed.
   This is acknowledged in Open Question 4 but should be elevated -- the `resurrect.error`
   event handler logs to WezTerm's log, not to the shell. The user must `tail
   $XDG_RUNTIME_DIR/wezterm/log` to discover failures.

**Category: non-blocking.** The fire-and-forget nature is acceptable for a personal config
but should be documented more prominently in the nushell command's help text (e.g.,
"Save is asynchronous; check wezterm logs if it appears to fail").

### Layer 3: Nushell CLI + Auto-trigger

**3a (wez-session.nu module):**

Several nushell-specific correctness concerns:

1. **`const` with runtime path expansion.** The declaration
   `const WEZ_SESSION_DIR = "~/.local/share/wezterm/resurrect/workspace"` uses `const`,
   which is evaluated at parse time. The tilde `~` in a `const` string is just a literal
   character -- it is NOT expanded at parse time. The `path expand` calls later in the code
   will expand it, so this works at runtime. However, the `path join` call in `wez delete`
   uses `$WEZ_SESSION_DIR` directly without `path expand`:
   `[$WEZ_SESSION_DIR, $"($name).json"] | path join | path expand`. This should work
   because `path expand` is called at the end, but it is fragile. The `wez-list-sessions`
   function expands first, then uses `ls`. The `wez delete` function joins first, then
   expands. Both work but the inconsistency is a maintenance hazard.

2. **`encode base64` syntax.** In nushell, the correct command is `encode base64` (added
   in 0.86). The proposal uses `$cmd | encode base64`. This is correct for modern nushell
   versions. However, `encode base64` may add a trailing newline to the output depending
   on the version. The base64 value is passed inside the OSC 1337 sequence, and WezTerm
   decodes it. A trailing newline in the base64 string itself should not be a problem
   (WezTerm decodes the base64 payload, not the raw string), but this should be verified
   during testing.

3. **`wez-ipc` is not exported.** The `wez-ipc` helper and `wez-list-sessions` are
   defined with `def` (not `export def`), making them module-private. The auto-trigger
   block in `config.nu` calls `wez-list-sessions` and `wez-ipc` directly, but these
   functions are NOT accessible outside the module. Nushell's `source` command does bring
   un-exported defs into scope (unlike `use`), so this actually works. But the proposal
   should be explicit about this reliance on `source` semantics -- if the import were ever
   changed to `use wez-session.nu *`, the auto-trigger would break.

**Category: non-blocking** (items 1-3). The code will work as written with `source`, but
document the `source` vs `use` dependency.

**3b (config.nu source line):** Correct placement after existing sources.

**3c (auto-trigger) -- THIS IS A BLOCKING ISSUE:**

The auto-trigger block calls `input list` during `config.nu` evaluation. The proposal
acknowledges this risk in E5 ("If nushell gates interactive commands on TTY readiness
during init, this could fail") but treats it as a maybe-fix-later.

Based on the nushell config structure, `config.nu` is evaluated during shell startup,
before the REPL loop begins. Nushell does NOT guarantee interactive I/O during config
evaluation. The `input list` command requires a TTY and an active REPL rendering context.
Calling it during `config.nu` evaluation is highly likely to either:

- Fail silently (command returns empty, treated as "cancelled")
- Fail with an error (blocking shell startup)
- Hang waiting for input that cannot be rendered

The proposal's own mitigation ("migrate to a `pre_prompt` hook") is the correct approach
and should be the PRIMARY design, not a fallback. A `pre_prompt` hook with a one-shot
guard (set a flag after first run to prevent re-triggering on every prompt) is the
standard nushell pattern for login-time interactive operations.

```nushell
# In hooks.nu or config.nu:
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt? | default [])
$env.config.hooks.pre_prompt ++= [{||
  if ($env._WEZ_RESTORE_OFFERED? | default false) { return }
  $env._WEZ_RESTORE_OFFERED = true
  if ($env.WEZTERM_PANE? | default "") != "0" { return }
  let sessions = (wez-list-sessions)
  if ($sessions | is-empty) { return }
  let choices = ($sessions | append "[Start fresh]")
  let selection = ($choices | input list "Restore a saved WezTerm session?")
  if ($selection | is-not-empty) and ($selection != "[Start fresh]") {
    wez-ipc $"restore:($selection)"
  }
}]
```

**Category: blocking.** The `input list` during `config.nu` evaluation will almost
certainly fail. The `pre_prompt` hook approach must be the primary design.

### Fresh Session Detection: `WEZTERM_PANE == 0`

This section claims `WEZTERM_PANE == 0` is a reliable functional test for fresh mux
server state. The analysis of the happy path is correct:

- Fresh boot: pane 0 created, trigger fires. Correct.
- New tab/split: pane ID > 0, no trigger. Correct.
- GUI close + reopen: reconnects to existing mux, no new pane, no trigger. Correct.

However, **there is a significant false-positive scenario not addressed:**

**Manual mux server kill + relaunch.** If the user kills the mux server manually
(`kill $(cat $XDG_RUNTIME_DIR/wezterm/pid)`) during a session, then relaunches WezTerm,
a new mux server starts with pane 0. The auto-trigger fires and offers restore. This is
actually the DESIRED behavior (it is how the test plan's Phase 4 step 2 works).

**The real problem: `WEZTERM_PANE == 0` is set by WezTerm in the pane's environment
when the pane is created, but nushell may inherit `WEZTERM_PANE` from a parent process
or a re-executed shell.** Specifically:

- If the user runs `exec nu` inside an existing pane (re-exec the shell), the new nushell
  process inherits `$env.WEZTERM_PANE` from the old process. If the old pane was pane 0,
  the auto-trigger fires again on shell re-exec.
- If the user sources `config.nu` manually (`:source config.nu` for debugging), the
  auto-trigger fires again.

These are minor edge cases for a personal config but contradict the claim of "No marker
files, no boot IDs, no state tracking." A one-shot guard (like the `_WEZ_RESTORE_OFFERED`
env var in the `pre_prompt` hook above) addresses both issues.

Additionally, **pane IDs are assigned per mux server lifetime, starting from 0.** But
what if the mux server was started by a previous `wezterm connect unix` command that did
not use `default_gui_startup_args` (e.g., a manual `wezterm connect unix` from another
terminal)? The pane 0 would already exist, and the subsequent desktop-launched WezTerm
would reconnect to the existing mux without creating a new pane. The auto-trigger would
NOT fire. This is actually correct behavior -- but the proposal should note that the
detection relies on being the process that CREATED pane 0, not just connecting to a mux
that has pane 0.

**Category: blocking.** The `WEZTERM_PANE == 0` detection needs a one-shot guard to
prevent re-triggering on shell re-exec. The `pre_prompt` hook with `_WEZ_RESTORE_OFFERED`
env flag solves both the `input list` timing issue and the re-trigger issue.

### Design Decisions (D1-D6)

**D1 (CLI-only):** Sound reasoning. Session management is infrequent, CLI is more
discoverable.

**D2 (single user var):** Good design. The note about "setting the same var to the same
value might not fire the event" is an important subtlety -- WezTerm's `user-var-changed`
fires on CHANGE, so setting `WEZ_SESSION_CMD=save` twice in a row may not fire the second
time. The proposal should either use a unique value each time (e.g., `save:$timestamp`)
or document this limitation.

**Category: blocking.** If the user runs `wez save` twice in a row (same workspace name),
the second invocation may silently fail because WezTerm does not fire `user-var-changed`
when the value does not change. The fix is simple: append a timestamp or nonce to the
command value (e.g., `save:1709042400` or use `random uuid`).

**D3 (filesystem for list/delete):** Sound. Direct file access for read-only operations
is faster and more reliable.

**D4 (nushell input list):** Sound reasoning for CLI-first design.

**D5 (periodic save):** The 5-minute interval is reasonable. The tmux-continuum analogy is
apt. The lack of a "save on close" event is a real limitation of WezTerm.

**D6 (unix domain + resurrect complementary):** This is the claim that deserves the most
scrutiny. The proposal states the incompatibility "only applies when restoring INTO a
populated mux." Let me trace the restore flow:

1. Fresh boot. Mux server starts (auto-spawned by `connect`).
2. `mux-startup` fires, creates "main" workspace with one pane (pane 0).
3. Nushell starts in pane 0, auto-trigger fires, user selects a session.
4. `restore_workspace` is called with `close_open_tabs = true`.
5. Step 4 closes pane 0 (killing the nushell process mid-command).
6. resurrect spawns new panes in the workspace.

The question is: what domain do the restored panes spawn in? `resurrect.workspace_state.restore_workspace` calls `wezterm.mux.spawn_window()` internally. When the default domain is the unix domain (because we used `connect unix`), these spawns go to the mux server. This is the "works on empty mux" claim.

But consider: what if the periodic save captured state while connected to a unix domain?
The saved state may include domain-specific metadata that resurrect tries to restore. If
resurrect saves pane domain information and tries to re-attach to domains that no longer
exist (e.g., lace SSH domains from a previous session), the restore could partially fail.

The proposal should verify what resurrect actually serializes and whether it handles
domain mismatch gracefully. If resurrect stores only working directories and layout
geometry (not domain affinity), the complementary claim holds. If it stores domain names,
there is a latent failure mode.

**Category: non-blocking.** The complementary claim is plausible but unverified. Add a
test step to Phase 2: "Inspect the saved JSON to verify what metadata resurrect captures.
Confirm that domain-specific pane references do not break restore on a fresh mux."

### Edge Cases (E1-E8)

**E1 (auto-save capturing empty state):** The 5-minute interval mitigation is reasonable
but fragile. If the user declines restore and starts working, the first periodic save at
5 minutes will overwrite the previously saved session with whatever the user has built in
5 minutes. This may or may not be what they want. The proposal should note that declining
restore does NOT protect the saved session from being overwritten by periodic save.

**E2 (user declines restore):** The note about `wez delete` as the escape hatch is
adequate. But see E1 -- the saved session will be overwritten by periodic save regardless.

**E3 (resurrect load failure):** Correctly analyzed. The pcall guard is the right pattern.

**E4 (IS_NVIM lost on reattach):** Correctly identified as orthogonal but worth
monitoring. The reference to PR #7610 is appropriate.

**E5 (input list during shell init):** As argued above, this is almost certainly broken.
See the blocking finding in the Layer 3 section.

**E6 (pane 0 closing mid-prompt):** This is well-analyzed. The key insight that
`restore_workspace` runs in WezTerm Lua (not the shell) so it completes regardless of
the shell dying is correct. The "brief visual flash" is acceptable.

**E7 (non-WezTerm terminals):** The `TERM_PROGRAM` guard is correct.

**E8 (multiple workspaces):** The interaction between `save_workspaces = true` (saves
all) and `wez save` (saves current) is potentially confusing. If periodic save saves all
workspaces and `wez restore` offers individual workspace files, the user might not
understand the relationship. But this is a UX concern for polish, not a correctness issue.

**Category: non-blocking.** Note in E1 that declining restore does not protect the saved
session from periodic overwrite. Consider whether periodic save should have a "session
age" check -- skip save if the workspace was created less than N minutes ago.

### Test Plan

The four-phase test plan is well-structured and covers the critical paths. Phase 4 (auto-
trigger) correctly tests both the positive case (mux kill + relaunch) and the negative
cases (GUI reconnect, new tab).

Missing test cases:

- **Shell re-exec test:** Run `exec nu` in pane 0 and verify the auto-trigger does NOT
  fire a second time (requires the one-shot guard).
- **Double-save test:** Run `wez save` twice in rapid succession and verify both saves
  actually execute (requires the nonce fix for D2).
- **Domain metadata test:** Inspect saved JSON to verify resurrect does not embed domain
  names that would break cross-boot restore (per D6 finding).

**Category: non-blocking.** Add the three test cases above.

### Implementation Phases

The five-phase order is correct. Phase 1 (unix domain) must come first because it
changes the mux lifecycle. Phase 2 (resurrect) depends on having a working mux server.
Phase 3 (nushell CLI) depends on resurrect being configured. Phase 4 (auto-trigger)
depends on the CLI module.

One concern: Phase 1 changes the desktop file and enables connect mode simultaneously.
If the desktop file change is deployed but the config change is not (or vice versa due
to partial `chezmoi apply`), WezTerm behavior could be unexpected. The implementation
should apply both changes atomically in a single commit + `chezmoi apply`.

**Category: non-blocking.** Note that Phase 1 changes must be applied atomically.

### Open Questions

All four open questions are relevant. My assessments:

1. **Min-panes guard:** Yes, worth implementing. A simple check in the periodic save
   callback (`if #mux.all_windows()[1]:tabs() <= 1 then return end`) prevents saving
   trivially empty workspaces without adding significant complexity.

2. **`input list` during config.nu:** As argued above, this is almost certainly broken.
   Use `pre_prompt` hook from the start.

3. **Pane 0 closing UX:** The brief flash is acceptable. Simplifying `mux-startup` to
   not create a visible pane is complex (the mux server needs at least one pane to
   function) and not worth the effort.

4. **Fire-and-forget IPC:** Acceptable for a personal config. A reverse channel (status
   file or user var set back from Lua) is overengineering for the current use case.

## Novel Concerns

### Timing Race Between mux-startup and Auto-trigger

The proposal assumes this sequence: mux-startup creates pane 0, nushell starts, config.nu
evaluates (or pre_prompt fires), auto-trigger checks `WEZTERM_PANE == 0`, offers restore.
But `restore_workspace` with `close_open_tabs = true` kills pane 0 and its nushell
process. The restore creates new panes, which start new nushell processes, which evaluate
config.nu/pre_prompt again. These new panes have `WEZTERM_PANE > 0`, so the auto-trigger
does not fire again.

This is correct, but there is a subtle timing issue: if `restore_workspace` takes
significant time (complex layout, many panes), the user briefly sees pane 0 die and then
panes appear one by one. This is cosmetic, not functional.

### WezTerm Plugin Hot-Reload Interaction

WezTerm plugins loaded via `wezterm.plugin.require()` are cached and may be updated on
hot-reload. If WezTerm hot-reloads the config while a restore is in progress (e.g., the
user edited `wezterm.lua` via chezmoi during restore), the resurrect plugin state could
be inconsistent. This is extremely unlikely in practice but worth noting.

## Verdict

**Revise.** The proposal demonstrates thorough analysis and the architecture is sound.
Four issues must be resolved before implementation:

1. The `input list` during `config.nu` must be replaced with a `pre_prompt` hook approach.
2. The `WEZTERM_PANE == 0` detection needs a one-shot guard to prevent re-triggering.
3. The `user-var-changed` duplicate-value problem (D2) must be addressed with a nonce.
4. The `pre_prompt` hook design resolves issues 1 and 2 simultaneously.

These are straightforward fixes that do not change the fundamental architecture.

## Action Items

1. [blocking] Replace the `config.nu` auto-trigger block with a `pre_prompt` hook that
   includes a one-shot `_WEZ_RESTORE_OFFERED` env flag. This resolves both the `input list`
   timing issue (E5) and the shell re-exec false-positive for `WEZTERM_PANE == 0`.

2. [blocking] Add a nonce to the `wez-ipc` command value to ensure `user-var-changed`
   fires even when the same command is sent twice. For example:
   `wez-ipc $"save:(date now | format date '%s')"` or append `| random uuid | first 8`.
   Update the IPC handler's pattern matching to strip the nonce before processing.

3. [blocking] Update the IPC handler to handle nonce-suffixed commands. The simplest
   approach: use a delimiter (e.g., `save:name:nonce`) and ignore the nonce field in the
   Lua handler, or use a separate nonce field in the value (e.g., `save|name|nonce` with
   pipe delimiter).

4. [non-blocking] Remove the `gui-startup` handler and its `GLOBAL.gui_startup_registered`
   guard from the implementation plan, not just supplement with `mux-startup`. Dead code
   in the config is a maintenance hazard.

5. [non-blocking] Document that `wez save/restore` operates on the workspace of the
   window containing the command pane. In multi-workspace setups, the behavior depends on
   which pane the user types the command in.

6. [non-blocking] Add a test step to Phase 2 to inspect resurrect's saved JSON and verify
   it does not embed domain-specific references that would break cross-boot restore.

7. [non-blocking] Note in E1 that declining the restore offer does not protect the saved
   session from being overwritten by the next periodic save cycle.

8. [non-blocking] Add three test cases: shell re-exec in pane 0 (no re-trigger), double
   `wez save` (both execute), and domain metadata inspection.

9. [non-blocking] Consider implementing a min-panes guard on periodic save to avoid
   overwriting good sessions with trivially empty workspace state.

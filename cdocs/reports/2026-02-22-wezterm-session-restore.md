---
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-22T12:00:00-06:00"
task_list: dotfiles/wezterm
type: analysis
state: live
status: draft
tags: [wezterm, session-persistence, multiplexing, unix-domain, workspace, analysis]
---

# WezTerm Session Restore: Approaches for Persisting Tabs, Panes, and Workspaces

> BLUF: WezTerm can persist session state (tabs, panes, splits, working directories)
> across GUI restarts using its built-in unix domain multiplexer. Three changes are
> required: (1) uncomment `default_gui_startup_args = { "connect", "unix" }`,
> (2) fix the desktop file to invoke bare `wezterm` instead of `wezterm start --cwd .`,
> and (3) migrate the `gui-startup` handler to `mux-startup`. The mux server survives
> GUI close and persists until logout/reboot. A `DetachDomain` keybinding provides a
> clean "close without killing" affordance. A systemd user service is viable but
> unnecessary for the GUI-restart use case. For cross-reboot persistence, evaluate
> `resurrect.wezterm` as a standalone (non-unix-domain) solution.

## Why "Close All + Restart" Lost Everything

The current config defines `unix_domains` but never connects to them. Without
`default_gui_startup_args = { "connect", "unix" }` uncommented, `wezterm start` (the
default subcommand) runs an **embedded mux** inside the GUI process itself. All tabs,
panes, scrollback, and workspace state live in that GUI process's memory.

When every GUI window closes, the process exits and all state is destroyed. There is no
separate mux server to hold it.

### Observed Process State (2026-02-22)

Inspecting the running system confirmed this diagnosis:

- The GUI launched as `wezterm-gui start --cwd .` (via the desktop file), not
  `wezterm connect unix`.
- The `wezterm-mux-server` processes present (PIDs 2345355, 2884251) belong to lace
  devcontainer SSH domains, not a unix domain.
- No unix domain socket file (`sock`) exists in `$XDG_RUNTIME_DIR/wezterm/`. Only
  `gui-sock-*` files for the GUI process's internal communication.
- The desktop file at `~/.local/share/applications/org.wezfurlong.wezterm.desktop`
  specifies `Exec=wezterm start --cwd .`, which overrides `default_gui_startup_args`
  entirely (Issue #2933).

**Root cause chain:**

1. Desktop file passes `start --cwd .` -- overrides `default_gui_startup_args`.
2. Even if the desktop file were fixed, the config line is still commented out.
3. Without `connect unix`, no separate mux server is spawned.
4. Without a mux server, closing the GUI kills all state.

## The Mux Server Lifecycle

### How Auto-Start Works

When `wezterm connect unix` (or `default_gui_startup_args = { "connect", "unix" }`)
runs, WezTerm checks for a running `wezterm-mux-server` at the unix domain socket. If
none is found, it automatically spawns one as a daemon, then connects the GUI as a client.
This auto-start can be disabled with `no_serve_automatically = true` on the domain, but
the default is to auto-start.

### What Keeps the Mux Server Alive

The mux server is a separate process (`wezterm-mux-server`) that daemonizes itself. It
writes a PID file to `$XDG_RUNTIME_DIR/wezterm/pid` and listens on a unix socket. It does
**not** exit when all GUI clients disconnect (Issue #631 fixed this -- the original design
did exit on last-client-close, but that was changed to persist).

The mux server dies when:

- The user logs out (session scope)
- The system reboots
- It is explicitly killed (`kill $(cat $XDG_RUNTIME_DIR/wezterm/pid)`)
- It crashes

### What Does NOT Kill the Mux Server

- Closing all GUI windows (the server persists independently)
- Detaching via `DetachDomain` (by design, just disconnects the GUI)
- `QuitApplication` (closes the GUI client, server persists)

### `wezterm start` vs `wezterm connect unix`

| Behavior                        | `wezterm start`    | `wezterm connect unix` |
|---------------------------------|--------------------|------------------------|
| Mux location                    | Embedded in GUI    | Separate daemon        |
| Survives GUI close              | No                 | Yes                    |
| `gui-startup` fires             | Yes                | No                     |
| `mux-startup` fires             | Yes (embedded)     | Yes (on first spawn)   |
| `gui-attached` fires            | No                 | Yes                    |
| Desktop file `start --cwd .`    | Works              | Overrides config       |

## Clean Affordance for Closing Without Losing State

### Option 1: Just Close the Window (Default Behavior)

With `connect unix` mode enabled, simply closing the GUI window (via window manager close,
Alt+F4, or clicking the close button) detaches from the mux domain non-destructively. The
mux server keeps all state. Issue #2644 implemented "detach domain on window close" so
closing a window no longer activates hidden workspaces or prompts confusingly.

This is the simplest approach: **just close the window**. It works like closing a tmux
client -- the session persists in the background.

### Option 2: Explicit Detach Keybinding

For a tmux-like explicit detach (Ctrl-B d), add a `DetachDomain` keybinding:

```lua
-- Leader+D: Detach from mux (like tmux prefix+d)
{ key = "d", mods = "LEADER", action = act.DetachDomain 'CurrentPaneDomain' },
```

`DetachDomain` disconnects the GUI from the mux domain, removes all its windows/tabs/panes
from the GUI, and exits the client. The mux server and all its state remain untouched.
Relaunching WezTerm reconnects to the same server.

Variants:

- `act.DetachDomain 'CurrentPaneDomain'` -- detaches whatever domain the active pane
  belongs to.
- `act.DetachDomain { DomainName = 'unix' }` -- detaches the named domain explicitly.

### Option 3: QuitApplication Action

`act.QuitApplication` exits the GUI application. With connect-mode active, this closes
the client but does not kill the mux server. The effect is similar to closing all windows.

### Close Confirmation UX

With unix domains, closing a pane triggers a confirmation dialog even when only a shell is
running, because the pane is a remote mux client (not a local process). The
`skip_close_confirmation_for_processes_named` setting only applies to local panes.

Workarounds:

- Use `mux-is-process-stateful` callback returning `false` for idle shells
- Accept the prompt (safest -- prevents accidental session destruction)
- Set `window_close_confirmation = "NeverPrompt"` (risky: may kill server-side panes)

## Startup Flow

### Correct Sequence

1. User launches WezTerm (via desktop file, CLI, or app launcher).
2. WezTerm reads config, sees `default_gui_startup_args = { "connect", "unix" }`.
3. Equivalent to running `wezterm connect unix`.
4. WezTerm checks for existing mux server at the unix domain socket.
5. **If no server:** auto-spawns `wezterm-mux-server --daemonize`. The `mux-startup` event
   fires on the server. The handler creates the "main" workspace.
6. **If server already running:** connects to it. No `mux-startup` (already fired).
7. GUI attaches. The `gui-attached` event fires (every time, not just first connect).
8. All existing tabs, panes, scrollback, and workspaces appear in the GUI.

### The Desktop File Problem

The current desktop file:

```ini
Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start --cwd .
```

This passes `start --cwd .` as explicit subcommand arguments, which **override**
`default_gui_startup_args` entirely. The config setting only takes effect when WezTerm is
invoked with no subcommand (bare `wezterm`).

Fix the desktop file to invoke bare `wezterm`:

```ini
Exec=/home/linuxbrew/.linuxbrew/bin/wezterm
```

This lets `default_gui_startup_args` take effect. The `--cwd .` loss is acceptable because
in connect mode, existing panes retain their working directories from the mux server. On
first connect, `mux-startup` spawns the "main" workspace with `cwd = wezterm.home_dir`.

Alternatively, use `Exec=wezterm connect unix` to bypass the config setting entirely and
connect directly. This is more explicit but harder to toggle.

### gui-startup to mux-startup Migration

The current config has:

```lua
wezterm.on("gui-startup", function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)
```

This handler will NOT fire in `connect` mode (`gui-startup` only fires for
`wezterm start`). Migrate to `mux-startup`:

```lua
-- mux-startup fires once when the mux server first starts.
-- It does NOT fire on reconnect -- only on initial server spawn.
-- If any panes are created here, they suppress the default program.
wezterm.on("mux-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)
```

The `GLOBAL.gui_startup_registered` guard from the current config can be dropped for
`mux-startup` because the event only fires on the mux server process, which only starts
once. However, keeping a guard is harmless for defensive coding.

Optionally, add a `gui-attached` handler for per-reconnect setup:

```lua
wezterm.on("gui-attached", function(domain)
  -- Runs every time the GUI connects to the mux server.
  -- Use for GUI-specific setup: maximize windows, set status bar, etc.
  local workspace = wezterm.mux.get_active_workspace()
  for _, window in ipairs(wezterm.mux.all_windows()) do
    if window:get_workspace() == workspace then
      window:gui_window():maximize()
    end
  end
end)
```

## systemd User Service for wezterm-mux-server

### Viability

A systemd user service can manage the `wezterm-mux-server` lifecycle. This approach is
viable but adds complexity for limited benefit over the built-in auto-start mechanism.

### Service File

```ini
[Unit]
Description=WezTerm Mux Server
Documentation=https://wezterm.org/multiplexing.html

[Service]
Type=forking
ExecStart=/home/linuxbrew/.linuxbrew/bin/wezterm-mux-server --daemonize
PIDFile=%t/wezterm/pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Key details:

- `Type=forking` because `--daemonize` forks into the background.
- `PIDFile=%t/wezterm/pid` tells systemd where the daemon writes its PID
  (`%t` expands to `$XDG_RUNTIME_DIR`).
- The `daemon_options` config controls the PID file, stdout, and stderr locations.
  Defaults are `$XDG_RUNTIME_DIR/wezterm/{pid,stdout,stderr}`.

### What It Buys You

- **Automatic restart on crash.** `Restart=on-failure` respawns the server if it dies
  unexpectedly, preserving the socket for GUI clients to reconnect.
- **Guaranteed server-before-client.** The mux server is running before any GUI starts,
  eliminating the race condition where the auto-start mechanism occasionally fails.
- **Survives logout** (with `loginctl enable-linger`). Without linger, systemd user
  services die on logout along with the user session.

### What It Does NOT Buy You

- **Does not survive reboot.** All processes die on reboot. The mux server holds state in
  memory, not on disk.
- **Does not replace auto-start.** `wezterm connect unix` already auto-starts the server.
  The systemd service is redundant for the common case.
- **Does not improve state persistence.** Whether the server was started by systemd or
  auto-start, it holds the same in-memory state.

### Practical Assessment

The built-in auto-start (WezTerm spawns `wezterm-mux-server` on first `connect`) is
simpler and equally effective for the GUI-restart use case. A systemd service adds value
only if:

- The mux server crashes often enough to need `Restart=on-failure`.
- The user needs the server running at login before any GUI launches (rare).
- The user needs session survival across logout (requires `loginctl enable-linger`).

**Verdict:** Not recommended for now. Revisit if stability issues arise with the
auto-start mechanism. The service file above is ready to deploy if needed.

## Current Config State

The existing `wezterm.lua` already has the foundation in place:

```lua
config.unix_domains = {
  { name = "unix" },
}

-- Uncomment to auto-connect to mux on startup
-- config.default_gui_startup_args = { "connect", "unix" }
```

There is also a `gui-startup` event handler that spawns a "main" workspace. This handler
will NOT fire when using `connect` mode (see "Startup Flow" above), which is an important
behavioral change to account for.

## Approach 1: Unix Domain Multiplexer (Built-in)

### How It Works

When `default_gui_startup_args = { "connect", "unix" }` is set, launching `wezterm`
(with no explicit subcommand) behaves as `wezterm connect unix`. WezTerm auto-starts a
`wezterm-mux-server` daemon if one is not already running, then attaches the GUI as a
client to that server. Closing the GUI window detaches the client without killing the
server or its panes. Re-launching WezTerm reconnects to the same server, restoring all
state.

### What Is Preserved

| State                          | Preserved? | Notes                                         |
|--------------------------------|------------|-----------------------------------------------|
| Tab layout (count, order)      | Yes        | Server-side state                             |
| Pane splits (geometry)         | Yes        | May need resize on reattach (Issue #5117)     |
| Working directories            | Yes        | Per-pane cwd maintained                       |
| Scrollback buffer              | Yes        | Full scrollback survives detach/reattach      |
| Running processes              | Yes        | Shell and child processes keep running         |
| Workspace names                | Yes        | MuxWindow workspace labels survive            |
| Tab titles                     | Yes        | Custom and auto-set titles persist            |
| User variables (IS_NVIM etc.)  | No*        | Lost on detach/reattach (Issue #5832, PR #7610) |
| Pane dimensions                | Partial    | May overshoot on reattach (Issue #5117)       |

*PR #7610 adds user-var syncing on reconnect, but requires matching client/server versions.

### What Is NOT Preserved (Limitations)

- **Reboot/logout kills the mux server.** The `wezterm-mux-server` runs as a user
  process. When the user's session ends (logout, reboot, crash), the server dies and all
  state is lost. There is no built-in crash recovery or state serialization to disk.
- **User variables are lost on reattach** (until PR #7610 lands). This breaks
  smart-splits.nvim's `IS_NVIM` detection after reconnect. Workaround: a `FocusGained`
  autocmd in Neovim that re-sets the user var.
- **Pane resize on reattach.** If the GUI window size differs between sessions, pane
  dimensions may be incorrect until a manual resize or config reload.
- **No cross-reboot persistence.** Unlike tmux (which also dies on reboot without
  tmux-resurrect), the mux server does not serialize state to disk.

### Event Model Changes

Switching to `connect` mode changes which Lua events fire:

| Event          | `wezterm start` (current) | `wezterm connect unix` (proposed) |
|----------------|---------------------------|-----------------------------------|
| `gui-startup`  | Fires                     | Does NOT fire                     |
| `gui-attached` | Does not fire             | Fires                             |
| `mux-startup`  | Fires (embedded mux)      | Fires on mux server first start   |

### Configuration Changes Required

Three changes are needed:

```lua
-- 1. Uncomment the auto-connect line
config.default_gui_startup_args = { "connect", "unix" }

-- 2. Migrate gui-startup to mux-startup
--    (fires once when the mux server first starts, not on every GUI attach)
wezterm.on("mux-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({
    workspace = "main",
    cwd = wezterm.home_dir,
  })
end)

-- 3. Add detach keybinding (optional but recommended)
{ key = "d", mods = "LEADER", action = act.DetachDomain 'CurrentPaneDomain' },
```

### Desktop File Fix (Required)

The desktop file must stop passing `start --cwd .`:

```diff
-Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start --cwd .
+Exec=/home/linuxbrew/.linuxbrew/bin/wezterm
```

Without this fix, `default_gui_startup_args` is ignored entirely because CLI arguments
override the config setting (Issue #2933).

## Approach 2: resurrect.wezterm Plugin (Cross-Reboot Persistence)

### How It Works

[resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) serializes window/tab/pane
state to JSON files on disk. It can save manually via keybinding or automatically on a
configurable interval (default: 15 minutes). On restore, it reconstructs the layout by
spawning new windows/tabs/panes with the saved working directories.

Inspired by tmux-resurrect and tmux-continuum.

### What Is Preserved

| State                    | Preserved? | Notes                                     |
|--------------------------|------------|-------------------------------------------|
| Tab layout               | Yes        | Serialized to JSON                        |
| Pane splits              | Yes        | Relative or absolute sizing               |
| Working directories      | Yes        | Per-pane cwd                              |
| Scrollback buffer        | Yes        | Configurable line limit (default varies)  |
| Running processes        | No         | New shells spawned; processes not revived  |
| Workspace names          | Yes        | Per-workspace save/restore                |
| Remote domain connections| Yes        | SSH, SSHMUX, WSL, Docker re-attached      |
| Encryption               | Optional   | age, rage, or GnuPG                       |

### Key Limitation: Unix Domain Incompatibility

The plugin documentation notes that resurrect.wezterm **does not play well with unix mux
sessions**. The conflict arises because:

1. resurrect spawns new panes using `wezterm.mux.spawn_window()`, which creates panes in
   the local domain by default
2. When the default domain is a unix mux, the spawned panes connect to the mux server,
   creating duplicates or conflicts with existing server-side state
3. The plugin has no awareness of the mux server's existing layout

This means you must choose: unix domain for live persistence OR resurrect for disk
persistence. They cannot be used together for the same session without careful
orchestration.

### Configuration Example

```lua
local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

-- Enable periodic auto-save
resurrect.periodic_save({
  interval_seconds = 300,  -- every 5 minutes
  save_tabs = true,
  save_windows = true,
  save_workspaces = true,
})

-- Keybindings
table.insert(config.keys, {
  key = "S", mods = "LEADER|SHIFT",
  action = wezterm.action_callback(function(win, pane)
    resurrect.save_state(resurrect.workspace_state.get_workspace_state())
  end),
})

table.insert(config.keys, {
  key = "L", mods = "LEADER|SHIFT",
  action = wezterm.action_callback(function(win, pane)
    resurrect.fuzzy_load(win, pane, function(id, label)
      -- restore logic
    end)
  end),
})
```

## Approach 3: wezterm-session-manager (Simpler Alternative)

[wezterm-session-manager](https://github.com/danielcopper/wezterm-session-manager) is a
lighter Lua module (~140 stars) that saves workspace/tab/pane layouts to files. It provides
`save_state`, `load_state`, and `restore_state` functions bound to keybindings.

### Compared to resurrect.wezterm

| Feature                  | resurrect.wezterm   | wezterm-session-manager |
|--------------------------|---------------------|-------------------------|
| Auto-save                | Yes (periodic)      | No (manual only)        |
| Scrollback capture       | Yes                 | No                      |
| Encryption               | Yes                 | No                      |
| Fuzzy finder restore     | Yes                 | No                      |
| Complex layout support   | Good                | Basic (may fail)        |
| Community adoption       | Higher              | Lower                   |
| Code complexity          | Higher (plugin)     | Lower (single file)     |

## Comparison with tmux Session Persistence

| Capability                    | WezTerm Unix Domain  | tmux (native)       | tmux + resurrect/continuum |
|-------------------------------|----------------------|---------------------|----------------------------|
| Survives GUI close            | Yes                  | Yes (detach)        | Yes                        |
| Survives logout               | No*                  | No*                 | No*                        |
| Survives reboot               | No                   | No                  | Yes (saves to disk)        |
| Auto-restore on start         | Yes (reconnect)      | No (manual attach)  | Yes (continuum)            |
| Scrollback preserved          | Yes                  | Yes                 | Yes (resurrect)            |
| Running processes preserved   | Yes (while alive)    | Yes (while alive)   | Partial (resurrect)        |
| Layout serialized to disk     | No                   | No                  | Yes                        |
| Plugin ecosystem              | resurrect, session-mgr | resurrect, continuum | Mature, well-tested      |

*With `loginctl enable-linger` or systemd user services, tmux/wezterm servers can survive
logout but not reboot.

The key difference: tmux-resurrect + tmux-continuum is battle-tested over many years with a
large user base. WezTerm's resurrect plugin is newer and less proven, particularly around
edge cases with mux domains.

## Recommendation

### For the immediate use case (persist across GUI restarts)

Make three changes:

1. **Fix the desktop file** to invoke bare `wezterm` (remove `start --cwd .`).
2. **Uncomment `default_gui_startup_args`** in wezterm.lua.
3. **Migrate `gui-startup` to `mux-startup`** and add a `DetachDomain` keybinding.

This gives tmux-like session persistence with zero additional dependencies. The mux server
auto-starts on first connect, stays alive when the GUI closes, and all tabs, panes, splits,
working directories, scrollback, and workspace names survive reconnection.

### For cross-reboot persistence (future enhancement)

Evaluate `resurrect.wezterm` as a standalone solution (without unix domain). This trades
live process preservation for disk-serialized layout recovery. The tradeoff is acceptable if
the primary goal is "open my terminal and get back to where I was" rather than "keep long-
running processes alive."

### Not recommended

- Running `wezterm-mux-server` as a systemd service (unnecessary complexity for now)
- Using resurrect.wezterm AND unix domains simultaneously (known compatibility issues)
- `wezterm-session-manager` (resurrect.wezterm is strictly superior)

### Migration Steps

1. Fix the desktop file (`~/.local/share/applications/org.wezfurlong.wezterm.desktop`)
   to remove `start --cwd .` from the Exec line
2. Migrate `gui-startup` handler to `mux-startup`
3. Add `gui-attached` handler if GUI-specific setup is needed on reconnect
4. Add `DetachDomain` keybinding (Leader+D recommended)
5. Uncomment `default_gui_startup_args = { "connect", "unix" }`
6. Validate with the standard WezTerm TDD workflow (ls-fonts, show-keys diff)
7. Test close/reopen cycle to confirm state persists
8. Test smart-splits `IS_NVIM` behavior after reconnect (may need `FocusGained` workaround)
9. Verify desktop file launches correctly with `connect` mode

## Known Issues to Monitor

- **Issue #5832 / PR #7610:** User vars lost on mux reattach. Directly impacts
  smart-splits.nvim. Monitor for merge.
- **Issue #5117:** Pane resize mismatch on reattach. Visual annoyance, not data loss.
- **Issue #4199:** Close confirmation always prompts with unix domains. UX friction.
- **Issue #2933:** `default_gui_startup_args` ignored by desktop files that pass explicit
  subcommands. **Confirmed active on this system** -- the desktop file passes
  `start --cwd .`.
- **Issue #631:** Mux server exiting on last client close. Fixed in nightly; server now
  persists after all clients disconnect.
- **Issue #2644:** Detach-on-window-close. Fixed; closing a mux client window now detaches
  the domain non-destructively instead of activating hidden workspaces.
- **Issue #848:** Close confirmation wording for mux clients. Fixed; windows containing
  mux panes now close without the misleading "kill" prompt.
- **Issue #3237 / PR #5013:** Native layout save/restore. If merged, would make plugins
  unnecessary. No timeline.

## Sources

### WezTerm Documentation
- [Multiplexing](https://wezterm.org/multiplexing.html)
- [default_gui_startup_args](https://wezterm.org/config/lua/config/default_gui_startup_args.html)
- [gui-startup event](https://wezterm.org/config/lua/gui-events/gui-startup.html)
- [gui-attached event](https://wezterm.org/config/lua/gui-events/gui-attached.html)
- [mux-startup event](https://wezterm.org/config/lua/mux-events/mux-startup.html)
- [DetachDomain key assignment](https://wezterm.org/config/lua/keyassignment/DetachDomain.html)
- [MuxDomain:detach()](https://wezterm.org/config/lua/MuxDomain/detach.html)
- [daemon_options](https://wezterm.org/config/lua/config/daemon_options.html)
- [Workspaces recipe](https://wezterm.org/recipes/workspaces.html)

### GitHub Issues and Discussions
- [#631 -- Closing last window should not terminate mux server](https://github.com/wezterm/wezterm/issues/631)
- [#712 -- Can it detach?](https://github.com/wezterm/wezterm/discussions/712)
- [#848 -- Detach vs kill on mux client close](https://github.com/wezterm/wezterm/issues/848)
- [#1322 -- Tmux-like multiplexing sessions](https://github.com/wezterm/wezterm/discussions/1322)
- [#2644 -- Detach and exit on window close](https://github.com/wezterm/wezterm/issues/2644)
- [#2923 -- Beginner multiplexing guide](https://github.com/wezterm/wezterm/discussions/2923)
- [#2933 -- default_gui_startup_args and desktop files](https://github.com/wezterm/wezterm/issues/2933)
- [#3237 -- Provide a way to save the current layout](https://github.com/wezterm/wezterm/issues/3237)
- [#3633 -- Mux behavior with multiple windows](https://github.com/wezterm/wezterm/issues/3633)
- [#4199 -- Close confirmation with unix domains](https://github.com/wezterm/wezterm/issues/4199)
- [#5117 -- Pane resize on reattach](https://github.com/wezterm/wezterm/issues/5117)
- [#5832 -- User vars lost on mux reattach](https://github.com/wezterm/wezterm/issues/5832)
- [#6356 -- Domain persistence confusion](https://github.com/wezterm/wezterm/discussions/6356)
- [#6600 -- Starting with a default mux session](https://github.com/wezterm/wezterm/discussions/6600)
- [PR #5013 -- Resurrection: native layout save/restore](https://github.com/wezterm/wezterm/pull/5013)
- [PR #7610 -- Sync user vars on mux reconnect](https://github.com/wezterm/wezterm/issues/5832)

### Plugins
- [MLFlexer/resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm)
- [danielcopper/wezterm-session-manager](https://github.com/danielcopper/wezterm-session-manager)
- [MLFlexer/smart_workspace_switcher.wezterm](https://github.com/MLFlexer/smart_workspace_switcher.wezterm)

### Community Blog Posts
- [Fredrik Averpil -- Session management in Wezterm without tmux](https://fredrikaverpil.github.io/blog/2024/10/20/session-management-in-wezterm-without-tmux/)
- [mwop.net -- How I use Wezterm](https://mwop.net/blog/2024-07-04-how-i-use-wezterm.html)
- [mwop.net -- Using resurrect.wezterm](https://mwop.net/blog/2024-10-21-wezterm-resurrect.html)

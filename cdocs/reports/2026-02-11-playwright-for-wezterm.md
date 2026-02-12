---
title: "Playwright for WezTerm: Programmatic Config Verification for CLI-Based AI Agents"
date: 2026-02-11
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T13:15:00-05:00
type: report
state: live
status: accepted
tags: [wezterm, testing, validation, cli, ai-agent, config, automation]
---

# Playwright for WezTerm: Programmatic Config Verification for CLI-Based AI Agents

## BLUF

WezTerm provides a surprisingly rich CLI surface for programmatic config validation. An
AI agent running in a terminal can achieve **high-confidence config verification** without
any visual inspection by combining four layers: (1) `luac -p` for instant Lua syntax
checking, (2) `wezterm ls-fonts` stderr parsing for config evaluation errors, (3)
`wezterm show-keys --lua` diffing for silent binding drops, and (4) `wezterm cli` commands
for live integration tests against a running mux. The main gap is `action_callback`
functions, which are only validated at keypress time and cannot be exercised programmatically
through any existing CLI tool.

---

## Testing Stack: Recommended Layers

| Layer | Tool | What It Catches | Speed | Requires GUI? |
|-------|------|-----------------|-------|---------------|
| 1 | `luac -p` | Lua syntax errors | <10ms | No |
| 2 | `wezterm ls-fonts` stderr | Runtime Lua errors, invalid enum variants, nil references | ~1.5s | No |
| 3 | `show-keys --lua` diff | Silent config fallback to defaults, dropped bindings | ~1.5s | No |
| 4 | `wezterm cli` integration | Pane operations, spawn/kill, split topology | ~100ms/op | Running mux (not GUI) |
| 5 | Mock Lua module | Logic testing in pure Lua | <10ms | No |

---

## Layer 1: Lua Syntax Checking with `luac -p`

### What It Does

`luac -p` parses the Lua file and reports syntax errors without executing it. This is the
fastest possible check (sub-10ms) and catches missing quotes, unterminated strings,
mismatched brackets, and similar structural problems.

### Commands

```sh
luac -p dot_config/wezterm/wezterm.lua
# Exit code: 0 = valid syntax, 1 = syntax error
# Errors go to stderr with line numbers
```

### What It Catches

- Unterminated strings: `config.color_scheme = "Solarized Dark (Gogh)`
- Mismatched parentheses/braces
- Invalid Lua keywords
- Missing `end` statements

### What It Misses

- Everything that requires the `wezterm` runtime: API calls, enum validation, nil references
- Invalid CopyMode variants, bad action names, plugin loading failures
- Any runtime logic errors

### Empirically Verified

```
$ luac -p /tmp/wez_syntax_error.lua
luac: /tmp/wez_syntax_error.lua:3: unfinished string near '"Solarized Dark (Gogh)'
$ echo $?
1

$ luac -p dot_config/wezterm/wezterm.lua
$ echo $?
0
```

### Requirements

- System `luac` binary (Lua 5.4 to match WezTerm's built-in Lua)
- No WezTerm instance needed
- Works from any non-interactive terminal

---

## Layer 2: `wezterm ls-fonts` as Config Parse Checker

### What It Does

`wezterm ls-fonts` loads and evaluates the full Lua config as a side effect of enumerating
fonts. Parse and runtime errors are reported to **stderr**. The exit code is **always 0**
regardless of success or failure, so stderr must be checked.

### Commands

```sh
# Point at a specific config file (flag MUST come before subcommand)
wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 1>/dev/null 2>/tmp/wez_stderr.txt

# Check for errors (grep for ERROR level log messages)
if grep -q "ERROR" /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR"
    cat /tmp/wez_stderr.txt
else
    echo "Config parsed OK"
fi
```

### What It Catches

- **Invalid CopyMode enum variants** at `act.Multiple` construction time:
  ```
  ERROR  wezterm_gui > `ScrollToBottom` is not a valid CopyModeAssignment variant.
  stack traceback:
      [C]: in field 'Multiple'
      [string "/tmp/wez_broken.lua"]:6: in main chunk
  ```
- **Nil reference errors**:
  ```
  ERROR  wezterm_gui > runtime error: [string "/tmp/wez_nil.lua"]:6: attempt to index
  a nil value (local 'x')
  ```
- **Lua syntax errors** (redundant with `luac -p` but serves as a second check):
  ```
  ERROR  wezterm_gui > syntax error: [string "/tmp/wez_syntax_error.lua"]:3: unfinished
  string near '"Solarized Dark (Gogh)'
  ```
- **Plugin loading failures** (when not wrapped in pcall):
  ```
  ERROR  wezterm_gui > remote authentication required but no callback set
  ```

### What It Misses

- **`action_callback` runtime errors**: Functions inside `wezterm.action_callback()` are
  not invoked at config load time. `ls-fonts` will report the config as clean even if a
  callback contains `local x = nil; x()`.
- **Silent config fallback**: In some edge cases, `ls-fonts` may not report errors that
  `show-keys` would reveal through binding differences.

### Empirically Verified

All three error types (syntax, runtime, enum) were tested with `--config-file` pointing
to test files. Exit code was always 0; errors appeared only on stderr.

### Requirements

- WezTerm binary installed (not necessarily running)
- No running GUI instance needed
- Takes approximately 1.5 seconds per invocation (loads fonts as side effect)
- Works from non-interactive terminal

### Important Caveat: INFO vs ERROR

Normal stderr output includes INFO-level log messages from plugins:
```
INFO   logging > lua: lace: registered 75 SSH domains for ports 22425-22499
```
Always grep specifically for `ERROR` level, not just any stderr output.

---

## Layer 3: `show-keys --lua` Diff for Silent Binding Drops

### What It Does

`wezterm show-keys --lua` outputs the complete key assignment table as valid Lua code. When
a config fails to load, `show-keys` **silently falls back to defaults** with no error output
on stderr. By diffing the output against a known-good baseline or against `--skip-config`
defaults, you can detect when bindings have been silently dropped.

### Commands

```sh
# Capture baseline (defaults with no config)
wezterm --skip-config show-keys --lua > /tmp/wez_defaults.lua 2>/dev/null

# Capture current config output
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua > /tmp/wez_current.lua 2>/dev/null

# Diff: if current matches defaults, the config failed to load
diff /tmp/wez_defaults.lua /tmp/wez_current.lua > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "WARNING: Config appears to have fallen back to defaults"
else
    echo "Config loaded with custom bindings"
fi
```

### Specific Key Table Diffing

```sh
# Compare copy_mode specifically (most common customization target)
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua --key-table copy_mode \
    > /tmp/wez_copy_mode.lua 2>/dev/null

# Sentinel check: if Escape shows 'Close' instead of our custom Multiple action,
# the config fell back to defaults
grep "Escape" /tmp/wez_copy_mode.lua
# Expected (good): act.Multiple{ { CopyMode = 'MoveToScrollbackBottom' }, { CopyMode = 'Close' } }
# Bad (defaults):  act.CopyMode 'Close'
```

### Asserting Specific Bindings Exist

Rather than full diff, assert that expected custom bindings are present:

```sh
OUTPUT=$(wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua 2>/dev/null)

# Verify custom keybindings exist
echo "$OUTPUT" | grep -q "key = 'h', mods = 'CTRL', action = act.ActivatePaneDirection 'Left'" \
    || echo "FAIL: Ctrl+H pane navigation missing"

echo "$OUTPUT" | grep -q "key = 'c', mods = 'ALT', action = act.ActivateCopyMode" \
    || echo "FAIL: Alt+C copy mode missing"

echo "$OUTPUT" | grep -q "EmitEvent 'lace.project-picker'" \
    || echo "FAIL: Lace plugin bindings not registered"
```

### Key Finding: `--key-table` Limitation

The `--key-table` flag only reliably works with `copy_mode`. Testing shows that
`--key-table search_mode` returns empty output despite `search_mode` appearing in the
full `--lua` output. The full `show-keys --lua` output (without `--key-table`) includes
all key tables and is the more reliable data source.

### Line Count Heuristic

A quick sanity check: the default output has **224 lines**; the custom config has **240
lines**. A line count matching defaults (224) is a strong signal of fallback.

```sh
LINES=$(wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua 2>/dev/null | wc -l)
if [ "$LINES" -le 224 ]; then
    echo "WARNING: show-keys line count ($LINES) matches defaults, possible fallback"
fi
```

### Empirically Verified

The broken config (invalid CopyMode variant) produces default copy_mode bindings:
- Escape: `act.CopyMode 'Close'` (default) vs `act.Multiple{...}` (custom)
- y: `act.Multiple{ CopyTo, Close }` (default) vs `act.Multiple{ CopyTo, MoveToScrollbackBottom, Close }` (custom)
- q: `act.CopyMode 'Close'` (default) vs `act.Multiple{ ClearSelectionMode, MoveToScrollbackBottom, Close }` (custom)

### Requirements

- WezTerm binary installed
- No running GUI instance needed
- Takes approximately 1.5 seconds per invocation
- Works from non-interactive terminal

---

## Layer 4: `wezterm cli` Integration Testing

### Overview

The `wezterm cli` subcommands allow programmatic interaction with a running WezTerm mux.
This enables end-to-end testing of pane operations, splits, navigation, and text output.

### Prerequisite: Running Mux

All `wezterm cli` commands require a running WezTerm multiplexer (either the GUI or a
background mux server). The mux socket is at `$XDG_RUNTIME_DIR/wezterm/sock`. Check
availability:

```sh
ls -la "$XDG_RUNTIME_DIR/wezterm/sock" 2>/dev/null || echo "No mux running"
```

### Available Commands

| Command | Description | Use in Testing |
|---------|-------------|----------------|
| `cli list --format json` | List all panes with metadata | Verify pane count, layout, zoom state |
| `cli spawn` | Create new pane/tab/window | Set up test fixtures |
| `cli split-pane` | Split existing pane | Test split operations |
| `cli kill-pane` | Kill a pane | Cleanup after tests |
| `cli get-text` | Read pane content | Verify command output |
| `cli send-text` | Send text to pane | Simulate user input |
| `cli activate-pane` | Focus a specific pane | Test navigation |
| `cli activate-pane-direction` | Navigate to adjacent pane | Test directional nav |
| `cli get-pane-direction` | Query adjacent pane ID | Verify pane topology |
| `cli zoom-pane` | Zoom/unzoom pane | Test zoom operations |
| `cli adjust-pane-size` | Resize pane | Test resize operations |
| `cli rename-workspace` | Rename workspace | Test workspace operations |

### Integration Test Pattern: Spawn-Assert-Cleanup

```sh
# Spawn a test pane
PANE_ID=$(wezterm cli spawn -- bash -c 'echo MARKER_TEXT; sleep 5')

# Wait for output (even 10ms is reliable in practice)
sleep 0.1

# Assert output
TEXT=$(wezterm cli get-text --pane-id "$PANE_ID" | head -1)
if [ "$TEXT" = "MARKER_TEXT" ]; then
    echo "PASS: spawn and get-text work"
else
    echo "FAIL: expected MARKER_TEXT, got '$TEXT'"
fi

# Cleanup
wezterm cli kill-pane --pane-id "$PANE_ID"
```

### Integration Test Pattern: Split Topology Verification

```sh
# Create a right split
RIGHT=$(wezterm cli split-pane --right -- bash -c 'sleep 5')
sleep 0.1

# Verify topology
ACTIVE=$(wezterm cli list --format json | python3 -c \
    "import json,sys; print([p['pane_id'] for p in json.load(sys.stdin) if p['is_active']][0])")

LEFT_OF_RIGHT=$(WEZTERM_PANE=$RIGHT wezterm cli get-pane-direction Left)
echo "Pane left of split: $LEFT_OF_RIGHT"

# Cleanup
wezterm cli kill-pane --pane-id "$RIGHT"
```

### Integration Test Pattern: Zoom State Verification

```sh
RIGHT=$(wezterm cli split-pane --right -- bash -c 'sleep 5')
sleep 0.1

# Zoom
wezterm cli zoom-pane --pane-id "$RIGHT" --zoom

# Verify zoom state
IS_ZOOMED=$(wezterm cli list --format json | python3 -c \
    "import json,sys; print([p['is_zoomed'] for p in json.load(sys.stdin) if p['pane_id']==$RIGHT][0])")
echo "Zoomed: $IS_ZOOMED"  # Should print True

# Cleanup
wezterm cli zoom-pane --pane-id "$RIGHT" --unzoom
wezterm cli kill-pane --pane-id "$RIGHT"
```

### Scrollback Access

```sh
# Read scrollback (negative line numbers go into history)
wezterm cli get-text --pane-id "$PANE_ID" --start-line -100 --end-line 0
```

### Timing Characteristics

Empirically tested spawn-to-get-text latency:

| Delay | Reliable? |
|-------|-----------|
| 10ms  | Yes       |
| 20ms  | Yes       |
| 50ms  | Yes       |
| 100ms | Yes       |
| 500ms | Yes       |

The mux communicates via Unix socket, making operations very fast. A 100ms sleep is
conservative and safe for all operations.

### `cli list --format json` Metadata

Each pane entry includes:

```json
{
  "window_id": 0,
  "tab_id": 0,
  "pane_id": 0,
  "workspace": "default",
  "size": { "rows": 37, "cols": 118, "pixel_width": 1180, "pixel_height": 962, "dpi": 96 },
  "title": "bash",
  "cwd": "file://aurora/home/mjr/code/personal/dotfiles",
  "cursor_x": 0,
  "cursor_y": 36,
  "cursor_shape": "SteadyBar",
  "cursor_visibility": "Hidden",
  "left_col": 0,
  "top_row": 0,
  "tab_title": "",
  "window_title": "title",
  "is_active": true,
  "is_zoomed": false,
  "tty_name": "/dev/pts/3"
}
```

Useful fields for assertions: `is_active`, `is_zoomed`, `workspace`, `cwd`, `cursor_shape`,
`size`, `tty_name`.

**Not included**: user variables. The `pane:get_user_vars()` API is only accessible from
Lua code running inside the WezTerm process, not from `cli list`.

### Critical Limitation: `send-text` Is Not `send-keys`

`wezterm cli send-text` sends text **to the shell/program running in the pane** via the PTY.
It does **not** trigger WezTerm's key binding layer. This means:

- Sending `\x08` (Ctrl+H character) goes to bash, not to WezTerm's `ActivatePaneDirection`
- There is no way to programmatically trigger a WezTerm key binding via the CLI
- Mouse bindings cannot be triggered at all from the CLI

This is the single biggest limitation for integration testing. The `wezterm cli` commands
can verify pane state and topology, but they cannot exercise the key binding path.

---

## Layer 5: Mock Lua Module for Logic Testing

### What It Does

A mock `wezterm` module loaded into standard Lua 5.4 allows testing config logic without
the WezTerm runtime. This catches Lua logic errors, verifies that `pcall` error handling
works, and validates the structure of the returned config table.

### Mock Module

```lua
-- wezterm_mock.lua
local M = {}

M.action = setmetatable({
  Multiple = function(actions) return {_type="action", name="Multiple", args=actions} end,
  CopyMode = function(arg) return {_type="action", name="CopyMode", args=arg} end,
  CopyTo = function(arg) return {_type="action", name="CopyTo", args=arg} end,
}, {
  __index = function(t, k) return function(...) return {_type="action", name=k, args={...}} end end
})

M.action_callback = function(fn) return {_type="action", name="callback", fn=fn} end
M.font = function(name, opts) return {font=name, opts=opts} end
M.config_builder = function() return {} end
M.home_dir = os.getenv("HOME") or "/home/user"
M.GLOBAL = setmetatable({}, {
  __index = function() return nil end,
  __newindex = function(t, k, v) rawset(t, k, v) end,
})
M.gui = nil  -- set to mock table if testing copy_mode code paths
M.on = function() end
M.log_warn = function(msg) io.stderr:write("WARN: " .. msg .. "\n") end
M.format = function(t) return t end
M.plugin = { require = function(url) error("mock: plugin not available") end }
M.mux = { spawn_window = function() return {}, {}, {} end }

return M
```

### Usage

```sh
lua -e "
package.preload['wezterm'] = function() return dofile('wezterm_mock.lua') end
local ok, result = pcall(dofile, 'dot_config/wezterm/wezterm.lua')
if ok then
    print('Config loaded: ' .. #result.keys .. ' key bindings')
    if result.key_tables then
        for name, tbl in pairs(result.key_tables) do
            print('  key_table ' .. name .. ': ' .. #tbl .. ' bindings')
        end
    end
else
    print('FAIL: ' .. tostring(result))
end
"
```

### What It Catches

- Lua logic errors in non-wezterm code paths (table manipulation, string operations)
- Missing return statements
- pcall/error handling correctness
- Key count assertions (e.g., "config should have at least 15 key bindings")

### What It Misses

- Anything that depends on the real `wezterm` API behavior (enum validation, action
  construction semantics, plugin loading)
- The `wezterm.gui` code path (copy_mode customization) unless the mock provides
  `gui.default_key_tables()`
- All WezTerm-specific runtime behavior

### Empirically Verified

The mock successfully loaded the real config file (`wezterm.lua`), producing:
```
WARN: Failed to load lace plugin: mock: plugin not available
Config loaded: 24 key bindings
```

With an enhanced mock providing `gui.default_key_tables()`, the copy_mode path also
executes:
```
key_tables IS set
  table: copy_mode (4 bindings)
  table: search_mode (2 bindings)
keys: 24 bindings
```

---

## Testing `action_callback` Functions

### The Problem

`wezterm.action_callback(function(window, pane) ... end)` defers all validation to
keypress time. The config loads successfully even if the callback body contains
`local x = nil; x()`. The `ls-fonts` check reports no errors. The `show-keys` output
shows the binding as `act.EmitEvent 'user-defined-N'` with no indication of the
callback contents.

### Partial Mitigations

1. **Lua syntax check of the callback body**: Not directly possible since the callback
   is embedded in the config file. However, `luac -p` on the whole file catches syntax
   errors inside callbacks.

2. **Static analysis with selene/luacheck**: Can catch undefined variables, unused
   variables, and type mismatches inside callbacks. Requires type definitions for the
   `window` and `pane` APIs.

3. **Mock execution**: Extract callback functions and invoke them with mock `window` and
   `pane` objects. This requires:
   - A mock `window` with `perform_action()`, `get_selection_text_for_pane()`,
     `active_key_table()`, `active_workspace()`, `set_left_status()`
   - A mock `pane` object
   - Careful construction to avoid side effects

4. **Runtime log monitoring**: After deploying the config and pressing the key, check
   the GUI log file (`$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-<PID>.txt`) for
   runtime errors. This requires human interaction or an external key simulation tool.

### No CLI Solution Exists

There is no `wezterm cli invoke-action` or `wezterm cli press-key` command. The debug
overlay (Ctrl+Shift+L) provides a Lua REPL but it is a GUI-only interactive feature with
no CLI access.

---

## Testing Plugin Loading

### Detection via `ls-fonts` stderr

When `wezterm.plugin.require()` is **not** wrapped in `pcall`, failures appear on stderr:

```
ERROR  wezterm_gui > remote authentication required but no callback set; class=Http (34)
```

When wrapped in `pcall` (as in the current config), the error is caught and the plugin
bindings are simply not registered.

### Detection via `show-keys`

Plugin-registered bindings (like `EmitEvent 'lace.project-picker'`) appear in `show-keys`
output when the plugin loads successfully, and are absent when it fails:

```sh
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua 2>/dev/null \
    | grep "lace.project-picker"
# Present = plugin loaded; absent = plugin failed
```

This is the most reliable way to verify plugin loading.

### Detection via `ls-fonts` INFO messages

Successful plugin loading emits INFO to stderr:

```
INFO   logging > lua: lace: registered 75 SSH domains for ports 22425-22499
```

This can be checked alongside the ERROR grep but is less authoritative than `show-keys`.

---

## Testing User Variable Detection Logic

### The Challenge

The config uses `pane:get_user_vars().IS_NVIM` to detect when Neovim is running. User
variables are set by programs via the escape sequence:

```
\033]1337;SetUserVar=IS_NVIM=<base64_value>\007
```

### What CLI Can Do

- **Set user variables**: Send the escape sequence via `wezterm cli send-text`:
  ```sh
  printf '\033]1337;SetUserVar=%s=%s\007' IS_NVIM "$(echo -n true | base64)" \
      | wezterm cli send-text --pane-id "$PANE_ID" --no-paste
  ```

- **Cannot read user variables**: `wezterm cli list --format json` does not include user
  variables in its output. There is no `wezterm cli get-user-vars` command.

### Testing Strategy

User variable detection logic must be tested through:
1. The mock Lua module (unit testing the conditional logic)
2. Deploying a test config that logs the user variable state to a file, then checking
   the file after setting the variable

This is a significant gap in WezTerm's CLI tooling.

---

## Log File Analysis

### Location

- Main mux log: `$XDG_RUNTIME_DIR/wezterm/log`
- Per-GUI-process logs: `$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-<PID>.txt`
- Per-CLI-process logs: `$XDG_RUNTIME_DIR/wezterm/wezterm-log-<PID>.txt`

Typical path: `/run/user/1000/wezterm/`

### Log Format

```
HH:MM:SS.mmm  LEVEL  module > message
```

Levels: `INFO`, `WARN`, `ERROR`

### Useful Patterns

```sh
# Config errors during hot-reload
grep "ERROR.*lua\|ERROR.*config" "$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-*.txt"

# Plugin loading issues
grep "WARN.*lua" "$XDG_RUNTIME_DIR/wezterm/log"

# Runtime callback errors (after key press)
grep "ERROR.*termwindow\|ERROR.*lua" "$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-*.txt"
```

### Hot-Reload Error Detection

Config errors during hot-reload appear in the GUI process log as:
```
ERROR  wezterm_gui::termwindow > Failed to apply config overrides to window: `ScrollToBottom`
is not a valid CopyModeAssignment variant.
```

### Post-Deploy Verification Script

```sh
# After chezmoi apply, wait for hot-reload and check for errors
chezmoi apply
sleep 2
LATEST_LOG=$(ls -t "$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-"*.txt | head -1)
if grep -q "ERROR.*lua\|ERROR.*config\|Failed to apply" "$LATEST_LOG"; then
    echo "ERRORS detected in WezTerm log after deploy:"
    grep "ERROR" "$LATEST_LOG"
else
    echo "No errors in WezTerm log"
fi
```

---

## What Cannot Be Tested Without a Running GUI

| Capability | Testable via CLI? | Why Not |
|------------|------------------|---------|
| Config parse/eval | Yes (`ls-fonts`) | -- |
| Key binding registration | Yes (`show-keys`) | -- |
| Plugin loading | Yes (`show-keys` + stderr) | -- |
| Pane operations | Yes (`wezterm cli`) | Requires running mux |
| `action_callback` logic | No | Only invoked at keypress time |
| Mouse bindings | No | No CLI to simulate mouse events |
| Visual rendering | No | Requires GPU and display |
| Font rendering/fallback | Partial (`ls-fonts --text`) | Can list fonts, not verify rendering |
| Tab bar appearance | No | Rendering only |
| Color scheme correctness | No | Rendering only |
| Window decorations | No | Rendering only |
| Key binding actual behavior | No | `send-text` goes to PTY, not key handler |
| User variable reading | No | Not exposed in `cli list` |
| Debug overlay REPL | No | GUI-only interactive feature |
| Scrollbar visibility | No | Rendering only |

---

## Standalone Lua Testing Limitations

### `wezterm` Module Is Unavailable Outside WezTerm

Standard Lua cannot `require("wezterm")` -- the module is built into the WezTerm binary's
embedded Lua interpreter. There is no standalone `wezterm.so` or `wezterm.lua` module.

### No `wezterm lua` or `wezterm eval` Subcommand

WezTerm does not provide a headless Lua evaluation mode. The `record` subcommand spawns
a terminal session and is not useful for config validation.

### WezTerm Lua is 5.4

The embedded Lua version matches system Lua 5.4, so `luac -p` syntax checking is version-
compatible. WezTerm also includes some Luau-like extensions but standard Lua 5.4 syntax
checking is sufficient for most configs.

---

## Recommended Validation Script

Combining all layers into a single validation script:

```bash
#!/usr/bin/env bash
# wezterm-validate.sh -- Validate WezTerm config without visual inspection
set -euo pipefail

CONFIG="${1:-dot_config/wezterm/wezterm.lua}"
ERRORS=0

echo "=== Layer 1: Lua Syntax Check ==="
if luac -p "$CONFIG" 2>/tmp/wez_luac.txt; then
    echo "PASS: Lua syntax valid"
else
    echo "FAIL: Lua syntax error"
    cat /tmp/wez_luac.txt
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== Layer 2: WezTerm Config Evaluation ==="
wezterm --config-file "$CONFIG" ls-fonts 1>/dev/null 2>/tmp/wez_lsfonts.txt
if grep -q "ERROR" /tmp/wez_lsfonts.txt; then
    echo "FAIL: Config evaluation errors"
    grep "ERROR" /tmp/wez_lsfonts.txt
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: Config evaluates without errors"
fi

echo ""
echo "=== Layer 3: Key Binding Verification ==="
wezterm --config-file "$CONFIG" show-keys --lua > /tmp/wez_keys.lua 2>/dev/null
wezterm --skip-config show-keys --lua > /tmp/wez_defaults.lua 2>/dev/null

if diff -q /tmp/wez_defaults.lua /tmp/wez_keys.lua > /dev/null 2>&1; then
    echo "FAIL: show-keys matches defaults (config likely fell back)"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: show-keys differs from defaults"
fi

# Check specific expected bindings
EXPECTED_BINDINGS=(
    "ActivatePaneDirection 'Left'"
    "ActivatePaneDirection 'Down'"
    "ActivatePaneDirection 'Up'"
    "ActivatePaneDirection 'Right'"
    "ActivateCopyMode"
    "SplitPane"
)
for binding in "${EXPECTED_BINDINGS[@]}"; do
    if grep -q "$binding" /tmp/wez_keys.lua; then
        echo "  PASS: Found binding: $binding"
    else
        echo "  FAIL: Missing binding: $binding"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "=== Layer 3b: Copy Mode Custom Bindings ==="
wezterm --config-file "$CONFIG" show-keys --lua --key-table copy_mode > /tmp/wez_cm.lua 2>/dev/null

# Check that Escape uses our custom Multiple action (not default 'Close')
if grep -q "Escape.*Multiple" /tmp/wez_cm.lua; then
    echo "PASS: Escape in copy_mode uses custom action"
else
    echo "FAIL: Escape in copy_mode appears to use defaults"
    ERRORS=$((ERRORS + 1))
fi

# Check that y uses our custom yank action
if grep -q "'y'.*MoveToScrollbackBottom" /tmp/wez_cm.lua; then
    echo "PASS: y in copy_mode includes MoveToScrollbackBottom"
else
    echo "FAIL: y in copy_mode missing MoveToScrollbackBottom"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== Layer 3c: Plugin Loading ==="
if grep -q "lace.project-picker" /tmp/wez_keys.lua; then
    echo "PASS: Lace plugin bindings registered"
else
    echo "WARN: Lace plugin bindings not found (plugin may not be installed)"
fi

echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
    echo "All checks passed"
    exit 0
else
    echo "$ERRORS check(s) failed"
    exit 1
fi
```

---

## Recommendations for AI Agent Workflow

### Before Making Changes

1. Run the full validation script and save output as baseline
2. Capture `show-keys --lua` output to `/tmp/wez_keys_before.lua`
3. Capture `show-keys --lua --key-table copy_mode` to `/tmp/wez_copy_mode_before.lua`

### After Making Changes (Pre-Deploy)

1. Run `luac -p` for instant syntax feedback (~10ms)
2. Run `wezterm --config-file <source> ls-fonts` stderr check (~1.5s)
3. Diff `show-keys` output against baseline (~1.5s)
4. Total validation time: ~3 seconds

### After Deploy (Post `chezmoi apply`)

1. Wait 2 seconds for hot-reload
2. Check GUI log for errors
3. Run `wezterm cli list` to verify mux is healthy
4. Optionally run integration tests (spawn/kill panes)

### What to Skip

- Do not attempt to test `action_callback` logic -- accept this as a manual verification step
- Do not attempt to verify visual rendering
- Do not try `send-text` to exercise key bindings -- it sends to the PTY, not to WezTerm

---

## Future Possibilities

1. **WezTerm `eval` subcommand**: A `wezterm eval 'lua code'` command that evaluates Lua
   in the WezTerm Lua runtime without starting a GUI would close the biggest gap. This
   would enable testing action_callbacks and accessing `wezterm.gui.default_key_tables()`.

2. **`wezterm cli get-user-vars`**: Exposing user variables in the CLI JSON output would
   enable testing user variable detection logic programmatically.

3. **`wezterm cli send-key`**: A command that sends key events through WezTerm's key
   binding layer (not the PTY) would enable true end-to-end keybinding testing.

4. **selene with wezterm type definitions**: The
   [wezterm-types](https://github.com/DrKJeff16/wezterm-types) project provides type
   annotations that could be adapted for selene-based static analysis.

5. **Pre-commit hook**: A git pre-commit hook running `luac -p` + `wezterm ls-fonts`
   stderr check would prevent the most catastrophic class of config errors from being
   committed.

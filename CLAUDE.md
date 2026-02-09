# Dotfiles Repository

This repository is managed by **chezmoi**. The source files here are templates/sources
that chezmoi deploys to the home directory. Do not edit deployed files directly.

## Making WezTerm Config Changes

### File Locations

- **Chezmoi source** (edit this): `dot_config/wezterm/wezterm.lua`
- **Deployed config** (readonly, chezmoi-managed): `~/.config/wezterm/wezterm.lua`

Both files must stay in sync. Edit the chezmoi source, then `chezmoi apply` to deploy.
WezTerm watches the deployed file and hot-reloads on change.

### Validation Workflow (TDD Approach)

WezTerm has **no dedicated config validation command**. Config errors crash the entire
config evaluation, causing wezterm to fall back to all defaults. Always follow this workflow:

#### 1. Capture baseline before changes

```sh
wezterm show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_before.lua
wezterm show-keys --lua > /tmp/wez_keys_before.lua
```

#### 2. Make changes to `dot_config/wezterm/wezterm.lua`

#### 3. Validate the config parses without errors

Use `ls-fonts` as a parse check -- it loads the full config as a side effect and
reports errors to **stderr**. The exit code is always 0 (even on failure), so you
must check stderr for errors:

```sh
wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
if grep -q ERROR /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR:"; cat /tmp/wez_stderr.txt
else
    echo "Config parsed OK"
fi
```

**Important:** Only `ls-fonts` reliably reports config errors to stderr. `show-keys`
silently falls back to defaults without any error output when the config fails to load.

#### 4. Verify bindings were not silently dropped

Even after `ls-fonts` reports no errors, you should diff key tables to confirm your
changes took effect. `show-keys` silently falls back to defaults when config eval fails
(no stderr output), so the diff catches failures that `ls-fonts` might miss:

```sh
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_after.lua
diff /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_after.lua
```

If the after output matches the defaults (e.g., Escape shows `'Close'` instead of a
custom action), the config failed to load and `show-keys` fell back silently.

#### 5. Deploy and check logs

```sh
chezmoi apply
# Tail the wezterm log for errors after hot-reload:
tail -20 "$XDG_RUNTIME_DIR/wezterm/log" | grep -i error
```

The wezterm log directory is `$XDG_RUNTIME_DIR/wezterm/` (typically `/run/user/1000/wezterm/`).
Per-process GUI logs are also there as `wezterm-gui-log-<PID>.txt`.

#### 6. Confirm wezterm is healthy

```sh
wezterm cli list  # Should return a table of open panes without error
```

### Common Pitfalls

- **`CopyMode` actions are a specific enum.** Not all `KeyAssignment` names work as
  `CopyMode` variants. For example, `{ CopyMode = 'ScrollToBottom' }` inside `act.Multiple`
  will throw an error at construction time: *"`ScrollToBottom` is not a valid
  CopyModeAssignment variant."* This error crashes the entire config evaluation, causing
  wezterm to fall back to defaults for ALL bindings -- not just the one bad binding.
  The error appears on stderr via `ls-fonts` but `show-keys` fails silently.
  The valid `CopyMode` string variants include:
  `Close`, `MoveLeft`, `MoveRight`, `MoveUp`, `MoveDown`, `MoveForwardWord`,
  `MoveBackwardWord`, `MoveToStartOfLine`, `MoveToStartOfLineContent`,
  `MoveToEndOfLineContent`, `MoveToStartOfNextLine`, `MoveToScrollbackTop`,
  `MoveToScrollbackBottom`, `MoveToViewportTop`, `MoveToViewportMiddle`,
  `MoveToViewportBottom`, `PageUp`, `PageDown`, `ClearSelectionMode`, `JumpAgain`,
  `JumpReverse`, `MoveForwardWordEnd`, `MoveToSelectionOtherEnd`,
  `MoveToSelectionOtherEndHoriz`, `ClearPattern`, `CycleMatchType`, `PriorMatch`,
  `NextMatch`, `PriorMatchPage`, `NextMatchPage`, `EditPattern`, `AcceptPattern`.
  Table variants include `SetSelectionMode`, `JumpForward`, `JumpBackward`, `MoveByPage`.
  Always verify against `wezterm show-keys --lua --key-table copy_mode` output.

- **Config errors at parse time break the ENTIRE wezterm instance**, not just the
  affected feature. A single syntax error or nil reference in any section of the config
  causes wezterm to fall back to all defaults for everything.

- **`act.Multiple` validates its contents at construction time, not at execution time.**
  An invalid action inside `act.Multiple { ... }` throws a Lua error during config
  evaluation. Since the error is unhandled, it crashes the entire config -- wezterm falls
  back to defaults for all keys, mouse bindings, and settings. The error is reported on
  stderr by `ls-fonts` but NOT by `show-keys`.

- **`wezterm.action_callback` defers validation to runtime.** Actions inside a callback
  function (using `window:perform_action(...)`) are only validated when the key is actually
  pressed, not at config load time. This means `show-keys` cannot catch errors inside
  callbacks -- it will show them as `EmitEvent 'user-defined-N'`. Manual testing of the
  actual key press is required for callback-based bindings.

- **Always check the actual default bindings via `show-keys`** rather than trusting
  documentation, LLM knowledge, or reports. The `show-keys --lua --key-table <name>` output
  is the ground truth for what WezTerm actually supports.

- **`wezterm ls-fonts` and `show-keys` always exit 0**, even when the config has errors.
  `ls-fonts` reports errors to stderr; `show-keys` does not. You must check stderr from
  `ls-fonts` (not the exit code) to detect config failures. Use `show-keys` diff for a
  second layer of defense since it reveals fallback-to-defaults even when `ls-fonts` misses.

> **NOTE -- Future Improvement:** An MCP server that wraps wezterm CLI for validation
> could make this even safer. It would run the parse check, diff key tables, and tail
> logs as a single atomic operation, giving agents reliable config validation without
> needing to remember this entire workflow.

> **NOTE -- Future Improvement:** A `/wezterm-validate` skill could automate the
> before/after check workflow, capturing baseline state, applying changes, running
> validation, and reporting diffs in one command.

> **NOTE -- Future Improvement:** A pre-commit git hook on `wezterm.lua` that runs
> `wezterm --config-file <path> ls-fonts 2>&1 | grep ERROR` could catch parse errors
> before they are ever committed. It would not catch silently dropped bindings, but it
> would prevent the most catastrophic class of failures (total config parse errors).

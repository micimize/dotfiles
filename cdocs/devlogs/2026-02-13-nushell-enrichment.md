---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T15:00:00-06:00
task_list: proposals/2026-02-13-nushell-enrichment
type: devlog
state: archived
status: result_accepted
tags: [devlog, nushell, enrichment]
---

# Nushell Enrichment Implementation Devlog

## Phase 1: Dead code removal and quick fixes

**Status:** Complete

### Changes

- Removed obsolete carapace alias expansion from `completions.nu` (nushell 0.108+ handles natively)
- Added `try-catch` around carapace JSON parsing for robustness
- Replaced `sys host | get hostname` with `^hostname | str trim` in `env.nu`
- Merged duplicate Ctrl-R keybindings into single entry with `mode: [vi_insert vi_normal]`
- Fixed `colors-256` to pipe through `print` so ANSI escapes render
- Removed redundant `~/.full_history` pre_execution hook from `hooks.nu`

### Validation

- Config parses cleanly
- `^hostname | str trim` returns "aurora"

## Phase 2: Zoxide integration

**Status:** Complete

### Key discovery: vendor autoload timing

The proposal called for generating init scripts into vendor autoload (`$nu.data-dir/vendor/autoload/`).
Testing revealed that vendor autoload does NOT reliably pick up files created during env.nu.
The nushell startup order is: env.nu -> config.nu -> vendor autoload (after both).
However, the directory listing for vendor autoload appears to be pre-determined, so files
created by env.nu are not loaded in the same session.

### Key discovery: env.nu scoping

`def` commands defined in env.nu are NOT callable within the same file. The proposed
`init-tool-cache` helper function approach doesn't work. Inlined the logic instead.

### Key discovery: testing approach

`nu -c` does NOT load user config files in nushell 0.110. The `XDG_CONFIG_HOME` approach
from the instructions was not effective. Must use `--env-config` and `--config` flags
for testing. Also, `$nu.default-config-dir` always resolves to `~/.config/nushell/`
regardless of `--env-config` path, so generated files end up in the deployed location.

### Approach taken

1. env.nu generates init scripts to `$nu.default-config-dir/scripts/generated/` with
   freshness caching (only regenerates when tool binary is newer than cached output)
2. config.nu sources them using `const + source null` pattern for bootstrap safety
3. Added `scripts/generated/` to `.gitignore` (machine-specific files)

### Changes

- `env.nu`: Added inline freshness-cached init generation for starship and zoxide
- `config.nu`: Added `const`-guarded source lines for generated starship and zoxide init
- `completions.nu`: Restructured to multiple completer pattern (zoxide + carapace)
- `.gitignore`: Added `dot_config/nushell/scripts/generated/`

### Validation

- `z` and `zi` commands available after init
- Starship session key properly set
- Config parses cleanly

## Phase 3: Direnv integration

**Status:** Complete

### Changes

- `hooks.nu`: Added `env_change.PWD` hook calling `direnv export json`
- PATH list re-conversion guard to handle direnv stringifying PATH
- `env.nu`: Added `DIRENV_LOG_FORMAT=""` to silence verbose output
- `config.nu`: Reordered source lines (generated scripts before hooks.nu)

### Validation

- 2 PWD hooks confirmed (zoxide + direnv)
- DIRENV_LOG_FORMAT set to empty string

## Phase 4: Hooks enrichment

**Status:** Complete

### Changes

- `hooks.nu`: Added `display_output` hook for adaptive table rendering
  (expanded depth 1 when terminal >= 100 columns, collapsed otherwise)
- `hooks.nu`: Added `command_not_found` hook for Fedora `dnf provides` suggestions

### Validation

- Both hooks registered as closures

## Phase 5: Utility modernization

**Status:** Complete

### Changes

- `utils.nu`: Modernized `extract` with xz/zst/lz4 support and regex-based tar detection
- `utils.nu`: Simplified `docker-clean` to `docker system prune -f`
- `utils.nu`: Added `ssh-del-host` wrapping `ssh-keygen -R`
- `aliases.nu`: Renamed `duf` to `dfh` to avoid shadowing the duf disk utility

### Issue encountered

Nushell does not support multi-line `or` expressions in `if` conditions.
Restructured tar detection to use `=~` regex matching instead.

### Validation

- All new commands available (ssh-del-host, extract, docker-clean, dfh)
- `duf` no longer aliased
- Extract regex correctly identifies all tar.* variants

## Phase 6: Config polish

**Status:** Complete

### Changes

- `config.nu`: Added explicit `show_hints = true` (new in 0.110)
- `login.nu`: Moved LANG locale default from env.nu (session-wide property)
- `env.nu`: Removed LANG assignment

### Validation

- `show_hints` is true
- LANG inherited from environment (set explicitly in login shells)
- Startup time: ~38-55ms (near 50ms target)

## Summary

All 6 phases implemented and committed. Key deviations from proposal:

1. **Vendor autoload replaced with source-based approach** due to nushell runtime constraints
2. **`init-tool-cache` helper inlined** because env.nu def commands aren't callable
3. **Multi-line `or` replaced with regex** in extract function
4. **`nu -c` testing approach replaced** with explicit `--env-config`/`--config` flags

Files modified:
- `dot_config/nushell/env.nu`
- `dot_config/nushell/config.nu`
- `dot_config/nushell/login.nu`
- `dot_config/nushell/scripts/completions.nu`
- `dot_config/nushell/scripts/hooks.nu`
- `dot_config/nushell/scripts/keybindings.nu`
- `dot_config/nushell/scripts/utils.nu`
- `dot_config/nushell/scripts/aliases.nu`
- `.gitignore`

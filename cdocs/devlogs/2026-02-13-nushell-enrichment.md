---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T15:00:00-06:00
task_list: proposals/2026-02-13-nushell-enrichment
type: devlog
state: live
status: wip
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

`XDG_CONFIG_HOME` does NOT control which env.nu nushell loads. The `$nu.env-path` reports
the XDG-based path but nushell doesn't use it. Must use `--env-config` and `--config`
flags for testing. Also, `$nu.default-config-dir` always resolves to `~/.config/nushell/`
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

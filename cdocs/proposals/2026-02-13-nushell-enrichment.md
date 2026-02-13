---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T14:00:00-06:00
type: proposal
state: archived
status: implemented
tags: [proposal, nushell, enrichment, migration, qol, zoxide, direnv, carapace]
---

# Nushell Enrichment and Modernization

> BLUF: Overhaul the nushell config to remove dead code, integrate two already-installed
> tools (zoxide, direnv), remove a redundant hand-rolled history hook, add missing hooks
> (display_output, command_not_found), and modernize utilities. Zoxide and direnv are
> already installed via linuxbrew. The config has never been battle-tested, so this is a
> greenfield opportunity to get everything right before daily-driving it. Six phases, each
> independently committable, ordered from zero-risk deletions to progressively more
> opinionated additions. Informed by the
> [completion audit](../reports/2026-02-13-nushell-tab-completion-audit.md),
> [best practices research](../reports/2026-02-13-nushell-best-practices-research.md), and
> [config review](../reviews/2026-02-13-nushell-config-review.md).
>
> Atuin was evaluated and rejected -- nushell's built-in SQLite history already stores
> timestamps, hostname, CWD, exit codes, duration, and session IDs, making the hand-rolled
> `~/.full_history` hook redundant without needing a third-party tool. The community
> solarized theme migration is tabled for a future pass.

## Objective

Transform the nushell config from "functional but untested" to "polished daily-driver"
by integrating available tools, removing dead code, adopting community-maintained
components, and adding QoL hooks. Since this config hasn't been used in anger yet,
we can make breaking changes freely.

## Background

### Current state

The nushell config is well-organized across 10 files under `dot_config/nushell/`.
It was originally ported from a bash/ble.sh setup and includes vi-mode keybindings,
a hand-rolled solarized theme, carapace completions, starship prompt, and several
hand-rolled utilities. Nushell 0.110.0 is installed; startup is ~19ms.

### Tools already installed but not integrated

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| zoxide | latest | `/home/linuxbrew/.linuxbrew/bin/zoxide` | Frecency-based directory jumping |
| direnv | latest | `/home/linuxbrew/.linuxbrew/bin/direnv` | Per-directory environment variables |

> NOTE: Atuin (`/home/linuxbrew/.linuxbrew/bin/atuin`) was evaluated and rejected.
> Nushell's built-in SQLite history already stores all the metadata that the hand-rolled
> `~/.full_history` hook provides (timestamp, hostname, CWD) plus exit codes, duration,
> and session IDs. Atuin's differentiator is cross-machine sync, which requires trusting
> their hosted service or self-hosting a server -- unnecessary complexity for the current
> setup. The hand-rolled hook is simply redundant and can be removed.

### Key references

- [Config review](../reviews/2026-02-13-nushell-config-review.md) -- 4 major, 5 minor, 5 nit findings
- [Best practices research](../reports/2026-02-13-nushell-best-practices-research.md) -- community patterns, plugins, anti-patterns
- [Nushell 0.108 release](https://www.nushell.sh/blog/2025-10-15-nushell_v0_108_0.html) -- built-in alias expansion for completers
- [Nushell external completers cookbook](https://www.nushell.sh/cookbook/external_completers.html) -- multiple completer pattern
- [Nushell direnv cookbook](https://www.nushell.sh/cookbook/direnv.html) -- env_change hook integration
- [nu_scripts themes](https://github.com/nushell/nu_scripts/tree/main/themes/nu-themes) -- community solarized-dark

## Proposed Solution

Six phases, each a single committable unit. Phases 1-2 are pure cleanup/simplification.
Phases 3-4 add integrations. Phases 5-6 are ergonomic polish.

### Overview

| Phase | Scope | Risk | Files touched |
|-------|-------|------|---------------|
| 1 | Dead code removal & quick fixes | None | completions.nu, env.nu, utils.nu, keybindings.nu, hooks.nu |
| 2 | Zoxide integration | Low | env.nu, completions.nu |
| 3 | Direnv integration | Low | hooks.nu |
| 4 | Hooks enrichment | Low | hooks.nu, config.nu |
| 5 | Utility modernization | Low | utils.nu, aliases.nu |
| 6 | Config polish | None | config.nu, env.nu, login.nu |

## Important Design Decisions

### Decision: Remove hand-rolled history hook (use built-in SQLite)

**Decision:** Delete the `pre_execution` hook that writes to `~/.full_history`. Do not
replace it with Atuin or any other third-party tool.

**Why:** Nushell's built-in SQLite history (`history.file_format = "sqlite"`) already
stores everything the hand-rolled hook captures -- and more:

| Field | SQLite built-in | `~/.full_history` hook |
|-------|:-:|:-:|
| Command text | yes | yes |
| Timestamp | yes | yes |
| Hostname | yes | yes |
| CWD | yes | yes |
| Exit code | yes | no |
| Duration | yes | no |
| Session ID | yes | no |
| Structured queries | yes | no |

The hook is pure redundancy. `history --long | where cwd =~ "project"` replaces
grepping a flat file. Atuin was considered but rejected: its only differentiator
over built-in SQLite is cross-machine sync, which requires trusting a third-party
service (or self-hosting). Not worth the dependency.

### Decision: Use multiple completer pattern for zoxide + carapace

**Decision:** Route `z`/`zi` completions to a zoxide-specific completer, everything else
to carapace.

**Why:** Carapace doesn't know about zoxide's frecency database. The zoxide completer
queries `zoxide query -l` for directory candidates ranked by usage. The multiple
completer pattern from the nushell cookbook handles this cleanly:

```nushell
let external_completer = {|spans: list<string>|
  match $spans.0 {
    z | zi => ($zoxide_completer | do $in $spans)
    _ => ($carapace_completer | do $in $spans)
  }
}
```

### Decision: Table the community solarized theme for now

**Decision:** Keep the hand-rolled solarized theme as-is. Revisit in a future pass.

**Why:** The existing theme works correctly and has intentional local overrides. Migrating
to the community version requires careful visual comparison and override layering. This is
lower priority than the functional improvements in this proposal.

### Decision: Cache tool init scripts with freshness check

**Decision:** Only regenerate starship/zoxide/atuin init files when the tool binary is
newer than the cached output.

**Why:** Currently, `starship init nu | save -f ...` runs on every shell startup,
including subshells and tmux splits. At ~5-15ms per tool, two tools (starship + zoxide)
would add 10-30ms to startup. A freshness check based on file modification time avoids
unnecessary regeneration while ensuring updates are picked up after tool upgrades.

```nushell
def --env init-tool-cache [name: string, cmd: closure] {
  let cache = ($nu.data-dir | path join $"vendor/autoload/($name).nu")
  let bin = (which $name | first | get path)
  let needs_regen = if ($cache | path exists) {
    (ls $bin | first | get modified) > (ls $cache | first | get modified)
  } else { true }
  if $needs_regen {
    mkdir ($nu.data-dir | path join "vendor/autoload")
    do $cmd | save -f $cache
  }
}
```

### Decision: Replace `docker-clean` with `docker system prune`

**Decision:** Simplify to a single `docker system prune -f` call.

**Why:** The current implementation has a silent failure bug when no stopped containers
exist (empty list passed to `docker rm`), and misses network/build-cache cleanup that
`system prune` handles. Since we use Podman on Fedora Atomic, this also works with
`podman system prune`.

### Decision: Keep `ssh-del` by line number, add `ssh-del-host`

**Decision:** Keep both approaches.

**Why:** SSH error messages report line numbers (`Offending key in known_hosts:42`), so
line-number deletion is the natural response to the most common trigger. But hostname-based
deletion via `ssh-keygen -R` is the canonical tool and handles hashed known_hosts files.
Both have value.

## Stories

### Daily terminal workflow

A user opens WezTerm, which spawns nushell. They `z project` to jump to a frequently-used
directory (zoxide). Direnv loads the project's `.envrc`, setting `DATABASE_URL` and
`AWS_PROFILE`. They run some commands, press `Ctrl-R` to search history via nushell's
built-in SQLite-backed search. Tab completion via carapace works for `git`, `docker`,
`cargo`, etc. The solarized theme renders tables cleanly. When they split the pane,
the new shell starts in ~20ms because tool init scripts are cached.

### Archive extraction

A user downloads a `.tar.zst` package (common on Fedora). They run `extract pkg.tar.zst`
and it works without having to remember the `tar --zstd` flag.

### Querying history

A user wants to find what they ran in a project last week:
`history --long | where cwd =~ "project" and start_timestamp > (date now) - 7day`.
No third-party tool needed -- nushell's SQLite history is first-class structured data.

## Edge Cases / Challenging Scenarios

### Zoxide + /var/home path normalization

The `fix-atomic-home.nu` workaround normalizes `/var/home/` to `/home/` in CWD.
Zoxide must see the normalized path to avoid split entries in its database. The fix-cwd
runs in env.nu before tool init, so zoxide's `PWD` hook should see the correct path.
Verify during implementation that `zoxide query -l` shows `/home/mjr/...` paths, not
`/var/home/mjr/...`.

### Direnv + large .envrc files

Direnv runs on every `PWD` change. If a project's `.envrc` is expensive (e.g., evals
`nix develop`), there will be noticeable delay on `cd`. This is inherent to direnv, not
our config. Mitigation: direnv caches its output and only re-evaluates when `.envrc`
changes.

### Carapace completer error handling

The simplified completer (after removing alias expansion) should handle carapace errors
gracefully. If carapace returns invalid JSON for a command, `from json` will error. Wrap
in `try-catch` to return `null` (fall back to file completion) on failure.

## Test Plan

Each phase has specific verification steps documented in the implementation phases below.
The general validation approach:

1. **Parse check:** `nu -c 'print "ok"'` with `XDG_CONFIG_HOME` pointing at chezmoi source
2. **Startup time:** `nu -c '$nu.startup-time'` -- should stay under 50ms
3. **Completion check:** Open new shell, type `git <Tab>`, verify candidates appear
4. **Tool-specific:** Each integration has its own smoke test (documented per-phase)

## Implementation Phases

### Phase 1: Dead code removal and quick fixes

Remove the obsolete carapace alias expansion workaround, replace `sys host` with
`^hostname`, merge duplicate Ctrl-R keybindings, fix `colors-256` output, and remove
the redundant `~/.full_history` hook.

**Changes:**

- `completions.nu`: Remove the `scope aliases` lookup (lines 9-17). Simplify to direct
  carapace invocation. Add `try-catch` around `from json` for robustness. The alias
  expansion was needed before nushell 0.108; the shell now handles this natively.
- `env.nu:45`: Replace `sys host | get hostname` with `^hostname | str trim`.
- `keybindings.nu:17-35`: Merge the two Ctrl-R entries into one with
  `mode: [vi_insert vi_normal]`.
- `utils.nu:81-89`: Add `| print` to `colors-256` so ANSI escapes render instead of
  getting quoted.
- `hooks.nu`: Remove the `pre_execution` hook writing to `~/.full_history`. Nushell's
  built-in SQLite history already stores timestamps, hostname, CWD, exit codes, duration,
  and session IDs. Use `history --long` for structured queries.

**Verification:**
- `nu -c 'print "ok"'` parses clean
- Tab completion still works (`git <Tab>`)
- `^hostname | str trim` returns the correct hostname
- `colors-256` renders colored blocks in terminal
- `history --long | first 3` returns structured data with cwd, hostname, exit_status

**Constraints:** Do not change any behavior that the user might notice beyond the history
hook removal. These are internal simplifications.

---

### Phase 2: Zoxide integration

Add frecency-based directory jumping via zoxide.

**Changes:**

- `env.nu`: Add zoxide init with freshness caching to vendor autoload. Place after
  the `fix-cwd` call so zoxide sees normalized paths.
- `completions.nu`: Restructure to use the multiple completer pattern. Route `z`/`zi`
  to a zoxide-specific completer, everything else to carapace.

**New commands available:** `z <partial-path>`, `zi` (interactive selection).

**Verification:**
- `z` command is available in new shell
- `z` + Tab shows directory candidates from zoxide database
- `z` jumps to correct directory
- `zoxide query -l` shows `/home/mjr/...` paths (not `/var/home/...`)

---

### Phase 3: Direnv integration

Add per-directory environment management via direnv.

**Changes:**

- `hooks.nu`: Add `env_change.PWD` hook that calls `direnv export json | from json |
  load-env`. Include PATH list re-conversion guard (direnv may stringify PATH).
- `env.nu`: Add `$env.DIRENV_LOG_FORMAT = ""` to silence direnv's verbose output
  (optional -- can be removed if the user wants to see direnv messages).

**Verification:**
- Create a test `.envrc` with `export TEST_VAR=hello`
- `direnv allow .` then `cd` into the directory
- Verify `$env.TEST_VAR` is set
- `cd ..` and verify `$env.TEST_VAR` is unset
- Verify `$env.PATH` remains a list (not a colon-separated string)

---

### Phase 4: Hooks enrichment

Add `display_output` and `command_not_found` hooks.

**Changes:**

- `hooks.nu`: Add `display_output` hook for adaptive table rendering:
  ```nushell
  $env.config.hooks.display_output = {||
    if (term size).columns >= 100 { table -ed 1 } else { table }
  }
  ```
- `hooks.nu`: Add `command_not_found` hook for Fedora package suggestions:
  ```nushell
  $env.config.hooks.command_not_found = {|cmd|
    try { ^dnf provides $"*/bin/($cmd)" | print }
  }
  ```

**Verification:**
- Narrow the terminal below 100 columns, run `ls` -- should get collapsed table
- Widen above 100, run `ls` -- should get expanded table
- Type a nonexistent command -- should see dnf package suggestion (or graceful silence
  if dnf is slow/unavailable)

---

### Phase 5: Utility modernization

Fix `extract`, `docker-clean`, `duf` alias, and add `ssh-del-host`.

**Changes:**

- `utils.nu`: Add `xz`, `zst`, and `lz4` branches to `extract`. Consider simplifying
  all tar variants to `^tar xf $file` (modern tar auto-detects compression).
- `utils.nu`: Replace `docker-clean` body with `^docker system prune -f`.
- `utils.nu`: Add `ssh-del-host` command wrapping `ssh-keygen -R`.
- `aliases.nu`: Rename `duf` alias to `dfh` to avoid shadowing the `duf` disk utility.

**Verification:**
- `extract test.tar.zst` works (create test archive with `tar --zstd -cf test.tar.zst <file>`)
- `docker-clean` runs without error even when no containers exist
- `ssh-del-host some-host` calls `ssh-keygen -R`
- `dfh` shows `df -h` output
- `duf` is no longer aliased (available for the real `duf` if installed)

---

### Phase 6: Config polish

Explicit config options, startup caching, and minor reorganization.

**Changes:**

- `config.nu`: Explicitly set `$env.config.show_hints = true` (or `false` if a cleaner
  editing line is preferred). New in 0.110, worth being explicit about.
- `env.nu`: Move `$env.LANG` default to `login.nu` where session-wide locale belongs.
- `env.nu`: Apply freshness-check caching pattern to starship and zoxide init so they
  only regenerate when the tool binary is updated, not on every shell startup.

**Verification:**
- `$env.config.show_hints` is explicitly set
- `$env.LANG` is set correctly (check in both login and non-login shells)
- Startup time still under 50ms after all changes
- Tool init files only regenerate when binaries are newer than cached output

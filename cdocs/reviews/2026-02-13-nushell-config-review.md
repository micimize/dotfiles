---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T12:00:00-06:00
reviews: dot_config/nushell/
type: review
state: archived
status: result_accepted
tags: [review, nushell, config, qol]
verdict: conditional_accept
---

# Nushell Configuration Review

> BLUF: The configuration is well-structured, modular, and shows good nushell fluency. The
> main opportunities are: (1) replacing a hand-rolled solarized theme with the community's
> maintained version, (2) removing a now-unnecessary alias expansion workaround in the
> external completer, (3) adding zoxide/direnv integrations, (4) replacing `sys host` with
> a cheaper hostname call, and (5) replacing the manual `docker-clean` with `docker system
> prune`. Several smaller ergonomic improvements are also identified. Nothing is broken;
> the config is solid for daily driving.

## Scope

**Files reviewed:** All 10 nushell source files under `dot_config/nushell/` (env.nu,
config.nu, login.nu, and 7 scripts in `scripts/`).

**Target version:** Nushell 0.110.0 (released 2026-01-17).

**Overall assessment:** Clean, modular config split across well-named files. Good use of
`++=` append pattern for keybindings and hooks. Carapace integration is solid. The main
finding categories are: hand-rolled replacements that now have community equivalents,
missing tool integrations that the nushell ecosystem supports well, and one workaround
that upstream has since obviated.

## Findings

### [major] Solarized dark theme is hand-rolled; community version exists

**File:** `dot_config/nushell/scripts/colors.nu:1-67`
**Category:** hand-rolled-replacement

The entire 67-line solarized dark theme is manually defined with hex color values for every
shape, type, and UI element. The official [nu_scripts](https://github.com/nushell/nu_scripts)
repository maintains a `themes/nu-themes/solarized-dark.nu` theme file that is kept in sync
with nushell releases. The community version includes features the hand-rolled version lacks:
dynamic date coloring (recent vs. old entries get different colors), terminal color
integration via ANSI sequences, and an `activate` export for one-line setup.

Using the community version means upstream maintainers handle breakage when nushell's theme
schema changes across versions.

```nushell
# Current (67 lines in colors.nu)
let solarized_dark = { separator: dark_gray, ... }
$env.config.color_config = $solarized_dark

# Recommended: use nu_scripts theme
# Install via nupm or vendor the file, then:
use themes/nu-themes/solarized-dark.nu
solarized-dark activate
```

**Caveat:** The hand-rolled version may intentionally differ from upstream (e.g., the
`shape_external_resolved` styling). If so, consider forking the community version and
applying overrides rather than maintaining the entire theme from scratch.

---

### [major] Missing zoxide integration

**File:** `dot_config/nushell/env.nu` (absent)
**Category:** missing-integration

There is no directory jumping tool configured. [Zoxide](https://github.com/ajeetdsouza/zoxide)
has native nushell support (v0.89.0+) and is the community standard for smart `cd`. It
tracks directory frecency and provides `z` and `zi` commands. The init generates a vendor
autoload file, following the same pattern already used for starship.

```nushell
# Add to env.nu (after starship init block)
if (which zoxide | is-not-empty) {
  zoxide init nushell | save -f ($nu.data-dir | path join "vendor/autoload/zoxide.nu")
}
```

For completions, the [external completers cookbook](https://www.nushell.sh/cookbook/external_completers.html)
recommends routing `z` and `zi` to a zoxide-specific completer in the multiple completers
pattern:

```nushell
let zoxide_completer = {|spans|
  $spans | skip 1 | zoxide query -l ...$in | lines | where {|x| $x != $env.PWD}
}
```

---

### [major] Missing direnv integration

**File:** `dot_config/nushell/scripts/hooks.nu` (absent)
**Category:** missing-integration

No per-directory environment management is configured. [Direnv](https://direnv.net/) has
official nushell support (requires 0.104+) and the [nushell cookbook](https://www.nushell.sh/cookbook/direnv.html)
documents the integration. The nu_scripts repo provides an always-up-to-date hook at
`nu-hooks/nu-hooks/direnv/config.nu`. Using `env_change` hooks (rather than `pre_prompt`)
is the recommended approach for efficiency -- the hook only fires on directory change, not
every prompt render.

---

### [major] Carapace completer alias expansion is now unnecessary

**File:** `dot_config/nushell/scripts/completions.nu:9-17`
**Category:** deprecated-pattern

The completer wraps carapace with manual alias expansion via `scope aliases`. As of
nushell 0.108.0, the shell natively expands aliases before passing spans to external
completers. The manual `scope aliases` lookup on every completion invocation is now
redundant overhead.

```nushell
# Current (completions.nu:9-17) -- manual alias expansion
let expanded_alias = (scope aliases | where name == $spans.0 | get -o 0.expansion)
let spans = if $expanded_alias != null {
  $spans | skip 1 | prepend ($expanded_alias | split row " " | take 1)
} else {
  $spans
}
do $carapace_completer $spans

# Recommended (0.108+ built-in expansion) -- direct passthrough
let external_completer = if (which carapace | is-not-empty) {
  {|spans: list<string>|
    carapace $spans.0 nushell ...$spans | from json
  }
} else {
  {|spans: list<string>| null }
}
```

If zoxide is added, consider the multiple completer pattern to route `z`/`zi` to zoxide
and everything else to carapace.

Source: [Nushell 0.108.0 release blog](https://www.nushell.sh/blog/2025-10-15-nushell_v0_108_0.html)

---

### [minor] `sys host` in env.nu is expensive for just a hostname

**File:** `dot_config/nushell/env.nu:45`
**Category:** performance

`sys host` collects comprehensive system information (hostname, OS version, uptime, kernel
version, etc.) and returns a record. The config only uses `get hostname`. Calling the
external `hostname` command is significantly cheaper:

```nushell
# Current
$env._HOSTNAME = (sys host | get hostname)

# Recommended -- cheaper subprocess
$env._HOSTNAME = (^hostname | str trim)
```

This runs once at startup so the absolute cost is small, but `sys host` can take tens of
milliseconds collecting data that gets thrown away. On systems where startup latency
matters (e.g., tmux splits spawning new shells), this adds up.

---

### [minor] `docker-clean` reimplements `docker system prune`

**File:** `dot_config/nushell/scripts/utils.nu:55-61`
**Category:** hand-rolled-replacement

The `docker-clean` function manually queries and removes stopped containers and dangling
images using two separate commands. Docker (and Podman) provide `system prune` which does
this and more (also cleans networks, build cache) in a single atomic operation.

```nushell
# Current
def docker-clean [] {
  ^docker rm -v (^docker ps -a -q -f status=exited | lines) err> /dev/null
  ^docker rmi (^docker images -f "dangling=true" -q | lines) err> /dev/null
}

# Recommended
def docker-clean [] {
  ^docker system prune -f
}
```

The current version also silently fails when there are no stopped containers (empty list
passed to `docker rm`). `docker system prune` handles the empty case gracefully.

---

### [minor] `duf` alias shadows the `duf` disk utility

**File:** `dot_config/nushell/scripts/aliases.nu:25`
**Category:** ergonomics

The alias `duf = ^df -h` will shadow the real [duf](https://github.com/muesli/duf) command
if it is installed. `duf` is a popular modern replacement for `df` with colored output,
device grouping, and JSON output support. If `duf` is installed (or might be in the future),
this alias creates a confusing name collision.

```nushell
# Current
alias duf = ^df -h

# Recommended: rename to avoid clash, or use duf directly
alias dfh = ^df -h
# ...and install duf as the modern replacement
```

---

### [minor] `extract` function missing common formats

**File:** `dot_config/nushell/scripts/utils.nu:14-38`
**Category:** ergonomics

The `extract` function handles tar.gz, tar.bz2, zip, rar, 7z, and Z, but is missing
several common formats: `.xz` / `.tar.xz` (increasingly common for source tarballs),
`.zst` / `.tar.zst` (used by Arch Linux, Fedora packages), and `.lz4`. The extension
detection also has a subtle bug: it uses `path parse | get extension` which returns only
the last extension, so `.tar.gz` files show `extension: "gz"`. The code then re-checks
`str ends-with ".tar.gz"` as a workaround, but this pattern breaks for `.tar.xz` since
the `"xz"` branch would need the same workaround.

```nushell
# Add to the match block:
"xz" => {
  if ($file | str ends-with ".tar.xz") or ($file | str ends-with ".txz") {
    ^tar xJf $file
  } else {
    ^unxz $file
  }
}
"zst" => {
  if ($file | str ends-with ".tar.zst") {
    ^tar --zstd -xf $file
  } else {
    ^unzstd $file
  }
}
```

Alternatively, `tar` on modern systems auto-detects compression, so all tar variants
can collapse to `^tar xf $file`.

---

### [minor] `ssh-del` by line number is fragile; `ssh-keygen -R` exists

**File:** `dot_config/nushell/scripts/utils.nu:2-6`
**Category:** hand-rolled-replacement

The `ssh-del` function removes a line by number from `known_hosts`. This requires the user
to first find the line number (e.g., from an SSH error message), then pass it manually.
OpenSSH provides `ssh-keygen -R <hostname>` which removes entries by hostname, handles
hashed known_hosts files, and is the standard tool for this task.

```nushell
# Current
def ssh-del [line: int] {
  let hosts = (open ~/.ssh/known_hosts | lines)
  $hosts | drop nth ($line - 1) | save -f ~/.ssh/known_hosts
  print $"Deleted line ($line) from known_hosts"
}

# Recommended: keep ssh-del for line-number removal (SSH error messages report line numbers),
# but also add a hostname-based variant
def ssh-del-host [host: string] {
  ^ssh-keygen -R $host
}
```

The line-number approach is actually useful because SSH error messages include the line
number (e.g., "Offending key in /home/user/.ssh/known_hosts:42"). Both approaches have
value; consider keeping both.

---

### [minor] Consider Atuin for enhanced shell history

**File:** `dot_config/nushell/scripts/hooks.nu:1-8`
**Category:** missing-integration

The pre_execution hook appends every command to `~/.full_history` with timestamp, hostname,
and PWD. [Atuin](https://atuin.sh/) provides this same functionality with additional
features: encrypted sync across machines, full-text search with a TUI, context-aware
filtering (by directory, hostname, session), and exit code tracking. Atuin has had native
nushell support since v14.

The hand-rolled history hook is simple and dependency-free, which is a valid choice. But if
cross-machine history sync or searchable structured history is desired, Atuin replaces both
the hook and the SQLite history entirely.

```nushell
# If Atuin is adopted, the pre_execution hook can be removed entirely.
# Atuin init for nushell (in env.nu):
if (which atuin | is-not-empty) {
  atuin init nu | save -f ($nu.data-dir | path join "vendor/autoload/atuin.nu")
}
```

**Note:** Atuin's nushell integration had deprecation warnings as of nushell 0.106
(`get --ignore-errors` renamed to `--optional`). Verify compatibility with 0.110 before
adopting.

---

### [nit] `LANG` default belongs in login.nu, not env.nu

**File:** `dot_config/nushell/env.nu:12`
**Category:** ergonomics

The line `$env.LANG = ($env.LANG? | default "en_US.UTF-8")` sets the locale in env.nu.
The nushell community recommends setting locale variables in `login.nu` since they are
session-wide environment settings that should be inherited by child processes, and login.nu
is the nushell equivalent of `.profile` / `.bash_profile`. The env.nu file runs on every
shell instance (including subshells), where re-setting LANG is redundant.

That said, the `| default` pattern is defensive and harmless, so this is a style nit rather
than a functional issue.

---

### [nit] Starship init runs on every shell startup

**File:** `dot_config/nushell/env.nu:57-60`
**Category:** performance

The starship init block runs `starship init nu | save -f ...` on every new shell session,
including subshells, tmux splits, and `nu -c` invocations. The generated file is
deterministic for a given starship version, so it only needs regeneration when starship
is updated.

```nushell
# Current -- runs every startup
if (which starship | is-not-empty) {
  mkdir ($nu.data-dir | path join "vendor/autoload")
  starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
}

# Recommended -- only regenerate if starship binary is newer than cached file
let starship_cache = ($nu.data-dir | path join "vendor/autoload/starship.nu")
if (which starship | is-not-empty) {
  let needs_regen = if ($starship_cache | path exists) {
    (which starship | first | get path | path expand | metadata | get modified)
      > ($starship_cache | metadata | get modified)
  } else {
    true
  }
  if $needs_regen {
    mkdir ($nu.data-dir | path join "vendor/autoload")
    starship init nu | save -f $starship_cache
  }
}
```

In practice, `starship init nu` is fast (~5-15ms), so this is a micro-optimization. The
main benefit is avoiding unnecessary disk writes on every shell launch.

---

### [nit] Keybindings: Ctrl-R duplicated across two entries

**File:** `dot_config/nushell/scripts/keybindings.nu:17-35`
**Category:** ergonomics

Ctrl-R is defined as two separate keybinding entries: one for `vi_normal` and one for
`vi_insert`. These can be combined into a single entry with `mode: [vi_insert vi_normal]`,
matching the pattern already used for Ctrl-C on line 8.

```nushell
# Current -- two separate entries
{ name: history_search, modifier: control, keycode: char_r,
  mode: [vi_normal], event: { send: SearchHistory } }
{ name: history_search_insert, modifier: control, keycode: char_r,
  mode: [vi_insert], event: { send: SearchHistory } }

# Recommended -- single entry
{
  name: history_search
  modifier: control
  keycode: char_r
  mode: [vi_insert vi_normal]
  event: { send: SearchHistory }
}
```

---

### [nit] Missing `$env.config.show_hints` option (new in 0.110)

**File:** `dot_config/nushell/config.nu`
**Category:** ergonomics

Nushell 0.110.0 added `$env.config.show_hints` to control inline completion/history hints.
The config does not set this, so the default (true) applies. This is fine if hints are
wanted, but worth noting as a new tunable that may be desirable to set explicitly for
vi-mode users who prefer a cleaner editing line.

---

### [nit] `colors-256` output could use `print` instead of return

**File:** `dot_config/nushell/scripts/utils.nu:81-90`
**Category:** ergonomics

The `colors-256` function builds a string and returns it, which means nushell wraps the
output in quotes when displayed. Using `print` instead would render the ANSI escape
sequences directly to the terminal.

```nushell
# Current
def colors-256 [] {
  0..255 | each { |i| ... } | str join ""
}

# Recommended
def colors-256 [] {
  0..255 | each { |i| ... } | str join "" | print
}
```

---

### [nit] `fix-atomic-home.nu` workaround may interact with zoxide

**File:** `dot_config/nushell/scripts/fix-atomic-home.nu:16-19`
**Category:** ergonomics

The `/var/home/` to `/home/` CWD normalization is well-documented and correctly scoped.
If zoxide is added, its database will accumulate entries under both `/var/home/mjr/...`
and `/home/mjr/...` paths depending on which path nushell sees before/after the fix runs.
Consider running the fix before zoxide init, and adding a note about this interaction.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| Major | 4 |
| Minor | 5 |
| Nit | 5 |

## Verdict

**Conditional Accept.** The configuration is clean, well-organized, and functional. There
are no critical issues -- everything works correctly as-is. The four major findings are all
additive improvements rather than corrections:

**Priority ordering for changes:**

1. **Remove carapace alias expansion workaround** (completions.nu) -- Easiest win. Delete
   code, get the same behavior from nushell 0.108+ built-in. Zero risk.

2. **Add zoxide integration** (env.nu) -- High daily-use impact. Follows the same
   vendor/autoload pattern already established for starship.

3. **Replace hand-rolled solarized theme** (colors.nu) -- Reduces maintenance burden.
   The community theme in nu_scripts tracks nushell schema changes automatically.

4. **Add direnv integration** (hooks.nu) -- High value if per-project environment
   management is needed. Standard hook pattern from the nushell cookbook.

5. **Replace `docker-clean` with `docker system prune`** (utils.nu) -- Quick fix. Also
   resolves the silent failure on empty container lists.

6. **Add xz/zst support to `extract`** (utils.nu) -- Minor gap-fill.

7. **Everything else** -- Nits that can be addressed opportunistically.

The Atuin integration is listed as minor because the hand-rolled history hook is functional
and dependency-free. Atuin is worth evaluating if cross-machine history sync becomes a
priority.

## Research Sources

- [Nushell 0.108.0 release notes](https://www.nushell.sh/blog/2025-10-15-nushell_v0_108_0.html) -- built-in alias expansion for external completers
- [Nushell 0.110.0 release notes](https://www.nushell.sh/blog/2026-01-17-nushell_v0_110_0.html) -- show_hints, explore config, error_style
- [Nushell External Completers Cookbook](https://www.nushell.sh/cookbook/external_completers.html) -- multiple completer pattern, carapace setup
- [Nushell Direnv Cookbook](https://www.nushell.sh/cookbook/direnv.html) -- env_change hook integration
- [nu_scripts themes](https://github.com/nushell/nu_scripts/tree/main/themes/nu-themes) -- community-maintained solarized-dark.nu
- [Zoxide nushell integration](https://github.com/ajeetdsouza/zoxide) -- native nushell support v0.89.0+
- [Atuin nushell support](https://blog.atuin.sh/release-v14/) -- v14 release with nushell integration
- [Atuin nushell deprecation issue](https://github.com/atuinsh/atuin/issues/2852) -- 0.106+ compatibility concerns
- [duf disk utility](https://github.com/muesli/duf) -- modern df replacement, name collision risk
- [docker system prune docs](https://docs.docker.com/engine/manage-resources/pruning/) -- atomic cleanup replacement

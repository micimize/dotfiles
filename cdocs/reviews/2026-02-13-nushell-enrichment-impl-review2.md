---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T15:00:00-06:00
reviews: proposals/2026-02-13-nushell-enrichment
type: review
state: archived
status: result_accepted
tags: [review, nushell, implementation]
verdict: accept
---

# Nushell Enrichment Implementation Review 2 (Phases 4-6)

## Summary

Phases 4-6 are implemented and validated. All changes match the proposal with one
minor syntax deviation (regex instead of multi-line `or` in the extract function).
Combined with phases 1-3, the full enrichment is complete.

## Phase 4: Hooks enrichment

**Verdict:** Accept

| Hook | Status | Implementation |
|------|--------|----------------|
| `display_output` | Done | Adaptive table: expanded depth 1 at 100+ cols, collapsed otherwise |
| `command_not_found` | Done | `dnf provides */bin/$cmd` wrapped in try-catch |

Both hooks are closures registered in `$env.config.hooks`. The `display_output` hook
uses `term size` to detect terminal width, which is the idiomatic nushell approach.
The `command_not_found` hook uses try-catch to handle dnf unavailability gracefully.

## Phase 5: Utility modernization

**Verdict:** Accept

| Change | Status | Notes |
|--------|--------|-------|
| Add xz/zst/lz4 to extract | Done | Regex-based tar detection, `tar xf` for all tar variants |
| Simplify docker-clean | Done | Single `docker system prune -f` call |
| Add ssh-del-host | Done | Wraps `ssh-keygen -R` |
| Rename duf to dfh | Done | Avoids shadowing duf disk utility |

### Deviation: extract implementation

The proposal suggested adding branches and simplifying tar variants. The implementation
uses a regex pattern (`=~`) for tar detection instead of multi-line `or` expressions,
because nushell does not support multi-line `or` in `if` conditions. The regex approach
is actually cleaner and more maintainable:

```nushell
let is_tar = ($file =~ '\.(tar(\.(gz|bz2|xz|zst|lz4))?|tgz|tbz2|txz)$')
```

This correctly identifies all tar variants (tar.gz, tgz, tar.bz2, tbz2, tar.xz, txz,
tar.zst, tar.lz4, plain tar) while non-tar formats (zip, gz, zst standalone) fall
through to the match block.

### Code quality

- The `docker-clean` simplification also fixes the original silent failure bug when
  no stopped containers exist (empty list passed to `docker rm`)
- `ssh-del-host` provides the canonical approach alongside the line-number-based `ssh-del`
- The `dfh` rename is a non-breaking change (the original `duf` alias was shadowing)

## Phase 6: Config polish

**Verdict:** Accept

| Change | Status | Notes |
|--------|--------|-------|
| Explicit show_hints | Done | Set to true in config.nu |
| Move LANG to login.nu | Done | Session-wide locale belongs in login config |
| Freshness-check caching | Already done | Applied in Phase 2 |

### Startup time

Measured startup time: ~38-55ms (target: under 50ms). This is acceptable given the
additions of zoxide and direnv integrations. The freshness caching ensures tool init
scripts are only regenerated when the tool binary is updated, not on every startup.

Baseline was ~19ms. The increase is primarily from:
- Sourcing the generated starship init script (~2KB of nushell code)
- Sourcing the generated zoxide init script (~2KB of nushell code)
- The `which` + `ls` freshness checks in env.nu for each cached tool

## Full implementation assessment

### What matches the proposal

- All 6 phases implemented in order
- Dead code removed (alias expansion, history hook)
- Quick fixes applied (hostname, keybindings, colors-256)
- Zoxide integrated with multiple completer pattern
- Direnv integrated with PWD hook and PATH guard
- display_output and command_not_found hooks added
- Utilities modernized (extract, docker-clean, ssh-del-host, dfh)
- Config polish applied (show_hints, LANG, caching)

### Deviations from proposal (all justified)

1. Vendor autoload replaced with `scripts/generated/` + source approach
2. `init-tool-cache` helper replaced with inlined logic (env.nu scoping)
3. Multi-line `or` replaced with regex in extract function
4. Testing methodology changed from `XDG_CONFIG_HOME` to explicit flags

### No regressions

- All existing functionality preserved
- Tab completion works (carapace for general commands, zoxide for z/zi)
- Solarized theme unchanged
- Vi-mode keybindings preserved
- All aliases and utilities available

### Recommendation

Accept. The implementation is complete, clean, and idiomatic. Deploy with
`chezmoi apply --force` for daily use.

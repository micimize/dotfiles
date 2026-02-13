---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-13T12:00:00-06:00
type: report
state: archived
status: result_accepted
tags: [analysis, nushell, completions, carapace]
---

# Nushell Tab Completion Audit

> BLUF: The nushell completion infrastructure is mostly wired up -- carapace 1.6.2 is installed, external completer closures are configured, and fuzzy matching is enabled -- but the Tab keybinding uses a simplified event pattern that prevents cycling through candidates. A missing `max_results` cap, an unused carapace init file, and the absence of `CARAPACE_LENIENT` are secondary gaps. Fixing the Tab keybinding pattern is the highest-impact change.

## Context / Background

Nushell 0.110.0 is the active shell on this system. The config uses vi mode (`edit_mode = "vi"`) with a modular file structure under `dot_config/nushell/`:

| File | Role |
|------|------|
| `env.nu` | PATH, env vars, carapace/starship init |
| `config.nu` | Core settings, sources all scripts |
| `scripts/completions.nu` | External completer (carapace) |
| `scripts/keybindings.nu` | Vi-mode key bindings |

Tab completion was reported as non-functional. This audit examines every layer of the completion stack.

## Key Findings

### What works

- **Carapace 1.6.2** is installed at `/home/linuxbrew/.linuxbrew/bin/carapace` and in PATH
- **Core completion settings** are all configured correctly in `config.nu`:
  - `algorithm = "fuzzy"`, `case_sensitive = false`, `quick = true`, `partial = true`, `use_ls_colors = true`
- **External completer** in `scripts/completions.nu` correctly invokes carapace with alias resolution
- **`CARAPACE_BRIDGES`** is set to `"zsh,fish,bash,inshellisense"` for broad fallback coverage
- **Tab and Shift-Tab** keybindings exist for `vi_insert` mode

### What's broken or missing

1. **Tab keybinding uses a simplified event pattern** (HIGH IMPACT)

   Current (`scripts/keybindings.nu:36-46`):
   ```nushell
   event: {
     send: menu
     name: completion_menu
   }
   ```

   This opens the menu but does NOT cycle through candidates on subsequent Tab presses. The recommended nushell pattern uses `until` to chain open -> cycle -> inline-complete:

   ```nushell
   event: {
     until: [
       { send: menu name: completion_menu }
       { send: menunext }
       { edit: complete }
     ]
   }
   ```

   The `until` event tries each action in order until one succeeds: first it attempts to open the menu; if it's already open, it advances to the next item; if nothing else applies, it does inline completion. Without this, the user sees the menu appear but can't navigate it with Tab.

2. **No `max_results` on external completions** (MEDIUM)

   `scripts/completions.nu` sets `enable: true` and `completer:` but omits `max_results`. For commands with large candidate sets (e.g., `git checkout` on repos with many branches), this can cause latency or freezing.

3. **Carapace init file generated but never sourced** (LOW)

   `env.nu:54` generates `~/.cache/carapace/init.nu` but nothing ever sources it. The direct-invocation approach in `scripts/completions.nu` works independently, so this is dead code -- not a bug, but wasted work on every shell startup.

4. **Missing `CARAPACE_LENIENT`** (LOW)

   Without `$env.CARAPACE_LENIENT = 1`, carapace can error on unrecognized flags for some commands, producing no completions instead of best-effort results.

5. **Tab only bound in `vi_insert` mode** (LOW)

   The Tab keybinding specifies `mode: [vi_insert]`. If the user hits Tab while in `vi_normal` mode (e.g., after pressing Escape), nothing happens. This is probably intentional (vi convention), but worth noting.

## Detailed Analysis

### Layer 1: Built-in Completion Engine

The `$env.config.completions` block in `config.nu:23-28` is complete and well-configured. Fuzzy matching with case insensitivity provides the most flexible experience. No issues here.

### Layer 2: External Completer (Carapace)

The closure in `scripts/completions.nu` follows the recommended pattern from nushell's cookbook:
- Checks if carapace is installed (graceful degradation)
- Resolves aliases before passing spans to carapace (works around a known nushell bug with alias completion)
- Calls `carapace $spans.0 nushell ...$spans | from json`

The only gap is the missing `max_results` field.

### Layer 3: Keybindings

The `++=` append in `scripts/keybindings.nu` correctly extends rather than replaces nushell's default bindings. However, because nushell processes keybindings in last-match-wins order, the appended Tab binding overrides any default Tab binding for `vi_insert` mode. The simplified event pattern (`send: menu`) then becomes the effective Tab behavior.

### Layer 4: Menu Configuration

No custom `$env.config.menus` configuration exists. This means nushell's built-in defaults are used, which include a `completion_menu` with columnar layout. The defaults are reasonable, but customizing `style` could improve visibility with the solarized color scheme.

### Layer 5: Carapace Init File

The `carapace _carapace nushell` output typically contains:
- The external completer closure (redundant -- already in `scripts/completions.nu`)
- Pre-registered custom completers for specific commands
- Environment variable setup

Since `scripts/completions.nu` handles the completer independently, the init file can be removed from `env.nu` to save ~50ms of shell startup time, or sourced to pick up any carapace-specific custom completers.

## Recommendations

### Must-fix

1. **Update the Tab keybinding to use the `until` pattern.** This is almost certainly the root cause of "no tab complete." Replace the current `completion_menu` binding in `scripts/keybindings.nu`:

   ```nushell
   {
     name: completion_menu
     modifier: none
     keycode: tab
     mode: [vi_insert]
     event: {
       until: [
         { send: menu name: completion_menu }
         { send: menunext }
         { edit: complete }
       ]
     }
   }
   ```

### Should-fix

2. **Add `max_results: 100`** to `$env.config.completions.external` in `scripts/completions.nu`.

3. **Add `$env.CARAPACE_LENIENT = 1`** to `env.nu` alongside the existing carapace block.

### Nice-to-have

4. **Remove or source the carapace init file.** Either delete lines 53-54 from `env.nu` (the `mkdir` + `save` for `~/.cache/carapace/init.nu`) since it's unused, or add `source ~/.cache/carapace/init.nu` to `config.nu` after the completions script and remove the redundant direct-invocation completer.

5. **Consider adding `vi_normal` mode** to the Tab binding if you want completion access without entering insert mode first.

---
review_of: cdocs/proposals/2026-02-12-wezterm-desktop-integration.md
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-12T18:00:00-06:00
last_updated:
  by: "@claude-opus-4-6"
  at: 2026-02-12T21:30:00-06:00
task_list: dotfiles/wezterm
type: review
state: live
status: done
tags: [rereview_agent, implementation_progress, desktop_integration, chezmoi, kde, freedesktop]
---

# Review: WezTerm Desktop Integration -- Implementation Progress (Round 2)

## Summary Assessment

This is a round 2 review assessing Phases 1-3 implementation progress against the revised
proposal. All blocking findings from round 1 have been incorporated into the proposal.
The implementation of Phases 1-3 is faithful to the spec: the `.desktop` file content is
an exact match, the symlink path and target are correct, and the icon asset is in place.
One concern emerged during implementation: the `wezterm_lavender.svg` file appears as an
untracked file at the repo root in git status, suggesting the Phase 1 cleanup step (removing
the original) was not completed or that a copy was re-introduced. Additionally, the
`gtk-update-icon-cache` failure during Phase 2 is non-critical but worth documenting.
Verdict: **Accept** with minor observations for Phase 4 readiness.

## Round 1 Resolution Status

All 8 action items from the round 1 review have been addressed in the revised proposal:

1. **[blocking] run_once_ naming** -- Resolved. Proposal now specifies
   `run_once_after_10-set-wezterm-default-terminal.sh`, matching the repo convention.
2. **[blocking] Absolute Homebrew paths** -- Resolved. Both `TryExec` and `Exec` now use
   `/home/linuxbrew/.linuxbrew/bin/wezterm`. The desktop actions also use absolute paths.
3. **[non-blocking] Symlink level count** -- Resolved. Prose now correctly states "6 levels."
4. **[non-blocking] set -e and command -v guard** -- Resolved. Script includes both.
5. **[non-blocking] --cwd . removal** -- Resolved. `Exec` line omits `--cwd` entirely.
6. **[non-blocking] Dolphin F4 distinction** -- Resolved. A NOTE clarifies that F4 uses
   KParts and will continue to use Konsole.
7. **[non-blocking] python3-gobject test** -- Resolved. Test plan now uses `readlink` and
   `file -L` instead of the Python GObject introspection approach.
8. **[non-blocking] Cache automation** -- Resolved. The `run_once_` script includes both
   `update-desktop-database` and `gtk-update-icon-cache` with `|| true` guards.

## Phase-by-Phase Implementation Findings

### Phase 1: Icon Asset Relocation

**[non-blocking]** The SVG file exists at `dot_config/wezterm/assets/wezterm_lavender.svg`
and is a valid SVG (87KB, 1273x1273 viewBox). This matches the proposal spec.

**[non-blocking]** Git status shows `?? wezterm_lavender.svg` as an untracked file at the
repo root. The proposal's Phase 1 step 3 calls for removing the original via `git mv`.
There are two possible explanations: (a) the file was copied rather than moved and the
original was never staged for deletion, or (b) the `git mv` was done but the file was
re-created by some other process. If it is a leftover copy, it should be deleted before
the final commit. If it is intentional (e.g., kept for some external reference), the
proposal should document why.

This is non-blocking because the deployed infrastructure works correctly regardless of
whether a stale copy exists at the repo root. However, it should be cleaned up before
the final commit in Phase 5.

### Phase 2: Freedesktop Icon Symlink

**Implementation matches spec.** The chezmoi source file at
`dot_local/share/icons/hicolor/scalable/apps/symlink_org.wezfurlong.wezterm.svg`
contains exactly:

```
../../../../../../.config/wezterm/assets/wezterm_lavender.svg
```

This is the correct 6-level relative path from
`~/.local/share/icons/hicolor/scalable/apps/` back to `~/.config/wezterm/assets/`.
Deployment was verified: `readlink` confirms the symlink target and `file -L` confirms
it resolves to an SVG.

**[non-blocking]** The `gtk-update-icon-cache` failure is expected and harmless. The user
hicolor directory at `~/.local/share/icons/hicolor/` lacks an `index.theme` file, which
`gtk-update-icon-cache` requires to build a cache. KDE resolves icons from the directory
hierarchy directly without relying on this cache. The failure is already suppressed in the
`run_once_` script via `|| true`. No action needed, but the devlog should note this for
future reference.

### Phase 3: Desktop Entry

**Implementation matches spec exactly.** The `.desktop` file at
`dot_local/share/applications/org.wezfurlong.wezterm.desktop` is a line-for-line match
with the proposal's specified content:

- `TryExec` and `Exec` use absolute Homebrew paths (addressing the round 1 blocking issue)
- `Exec` omits `--cwd` (addressing the round 1 suggestion)
- `StartupWMClass=org.wezfurlong.wezterm` is correct
- Desktop actions for `new-window` and `new-tab` are present with absolute paths
- `desktop-file-validate` passes (only a hint about dual main categories, which is
  non-actionable: `System` and `Utility` are both appropriate for a terminal emulator)

The desktop database was updated via `update-desktop-database`.

## Readiness for Phase 4

Phase 4 requires creating `run_once_after_10-set-wezterm-default-terminal.sh`. The
proposal specifies the full script content including `set -e`, the `command -v` guard,
`kwriteconfig6` calls, and cache rebuilds. The prerequisite artifacts (`.desktop` file
and icon symlink) are deployed and verified.

There are no blocking issues preventing Phase 4 from proceeding.

Considerations for Phase 4 execution:

1. **Script naming:** The repo already has `run_once_before_10-install-starship.sh` and
   `run_once_before_30-install-carapace.sh` in the `before` slot. The proposed
   `run_once_after_10-set-wezterm-default-terminal.sh` uses the `after` slot, which is
   clear (the only archived `after` script was `run_once_after_10-install-tpm.sh`).
   No numbering conflict.

2. **Idempotency:** The `run_once_` mechanism means this script executes exactly once.
   If the user needs to re-run it (e.g., after changing the Homebrew prefix), they would
   need `chezmoi state delete-bucket --bucket=scriptState` or similar. The proposal
   correctly documents that subsequent System Settings changes are preserved.

3. **gtk-update-icon-cache:** Will fail with the same `index.theme` error noted in Phase 2.
   This is already handled by `|| true` in the script. No action needed.

## Icon Cache Failure Analysis

The `gtk-update-icon-cache` failure during Phase 2 deserves a brief note for completeness.
The command requires an `index.theme` file in the target icon directory. System-installed
icon themes have this file at `/usr/share/icons/hicolor/index.theme`, but the user-local
directory `~/.local/share/icons/hicolor/` typically does not have one.

KDE Plasma 6 does not rely on `gtk-update-icon-cache` for icon resolution. It reads the
directory hierarchy directly, checking `scalable/apps/`, `48x48/apps/`, etc. in precedence
order. The icon cache is primarily a GTK optimization. Since the target desktop is KDE,
this failure has zero functional impact.

Options for addressing this (all non-blocking, listed for completeness):
- (a) Do nothing. The `|| true` guard handles it silently. This is the recommended approach.
- (b) Copy `/usr/share/icons/hicolor/index.theme` to `~/.local/share/icons/hicolor/` as
  a chezmoi-managed file. Overkill for a single icon.
- (c) Remove `gtk-update-icon-cache` from the script entirely since it serves no purpose
  on KDE. Slight reduction in portability if the dotfiles are ever used on a GTK desktop.

Recommendation: option (a). The script is correct as specified.

## Devlog Status

The devlog at `cdocs/devlogs/2026-02-12-wezterm-desktop-integration.md` has status `wip`
and its "Changes Made" and "Verification" sections are still placeholder text. These should
be filled in with the actual changes and verification evidence from Phases 1-3 before
proceeding to Phase 4, to maintain an accurate implementation record.

## Verdict

**Accept.**

All round 1 blocking issues have been resolved in the revised proposal. The implementation
of Phases 1-3 is faithful to the spec. The `.desktop` file is an exact match, the symlink
is correct, and the icon asset is deployed. The `gtk-update-icon-cache` failure is
non-critical and properly handled. The only cleanup item is the stale `wezterm_lavender.svg`
at the repo root, which should be removed before the final commit.

Phase 4 can proceed without any blocking concerns.

## Action Items

1. [non-blocking] Remove the stale `wezterm_lavender.svg` from the repo root if it is a
   leftover from the Phase 1 move. If it is intentionally kept, document the reason.
2. [non-blocking] Update the devlog's "Changes Made" table and "Verification" section with
   the actual Phase 1-3 artifacts and verification evidence before proceeding to Phase 4.
3. [non-blocking] Consider noting the `gtk-update-icon-cache` / `index.theme` behavior in
   the devlog's implementation notes, so future readers understand why the command fails
   and why that is acceptable.

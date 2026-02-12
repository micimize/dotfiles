---
review_of: cdocs/devlogs/2026-02-12-wezterm-desktop-integration.md
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-12T23:00:00-06:00
task_list: dotfiles/wezterm
type: review
state: live
status: done
tags: [fresh_agent, implementation_review, code_quality, verification_evidence, desktop_integration, kde, chezmoi]
---

# Review: WezTerm Desktop Integration -- Final Implementation Review (Round 3)

## Summary Assessment

This review evaluates the completed 5-phase implementation of the WezTerm KDE desktop
integration against its proposal spec. The implementation is faithful: all four artifacts
match the proposal line-for-line, verification evidence covers all CLI-testable phases, and
the run_once script is correct and safe. The stale repo-root SVG flagged in round 2 has
been cleaned up (it no longer exists on disk, though the git status snapshot at conversation
start still shows it -- this is a stale snapshot). Two non-blocking observations remain:
the proposal's frontmatter status should be updated now that implementation is complete,
and the devlog uses Unicode checkmarks in verification output which is mildly inconsistent
with the rest of the project's plain-text style. Verdict: **Accept**.

## Prior Review Status

The round 2 review (same file, `cdocs/reviews/2026-02-12-review-of-wezterm-desktop-integration.md`)
accepted Phases 1-3 and cleared Phase 4. It had 3 non-blocking action items:

1. **Remove stale `wezterm_lavender.svg` from repo root** -- Resolved. The file no longer
   exists at the repo root (confirmed via file read returning "File does not exist"). The
   `?? wezterm_lavender.svg` in the git status header is a stale snapshot from conversation
   start and does not reflect current state.
2. **Update devlog Changes Made and Verification sections** -- Resolved. Both sections are
   now fully populated with per-phase evidence.
3. **Document `gtk-update-icon-cache` / `index.theme` behavior** -- Resolved. Phase 2
   implementation notes explain the failure and why it is harmless on KDE.

All round 2 action items have been addressed.

## Artifact-by-Artifact Findings

### 1. Icon asset: `dot_config/wezterm/assets/wezterm_lavender.svg`

**Matches spec.** The file is a valid SVG (1273x1273 viewBox, starts with proper `<svg>`
element). The proposal called for moving the SVG from the repo root to this path, and the
devlog confirms deployment at `~/.config/wezterm/assets/wezterm_lavender.svg` (86,945 bytes).

No issues.

### 2. Freedesktop icon symlink: `dot_local/share/icons/hicolor/scalable/apps/symlink_org.wezfurlong.wezterm.svg`

**Matches spec.** The file contains exactly:

```
../../../../../../.config/wezterm/assets/wezterm_lavender.svg
```

This is the correct 6-level relative path. The chezmoi `symlink_` prefix in the filename
tells chezmoi to create a symlink rather than a regular file at the deployed path. The
devlog verification confirms `readlink` and `file -L` both produce the expected output.

No issues.

### 3. Desktop entry: `dot_local/share/applications/org.wezfurlong.wezterm.desktop`

**Matches spec exactly.** Line-by-line comparison against the proposal's specified content
(proposal lines 79-105) confirms an exact match. Key points verified:

- `TryExec` and `Exec` both use absolute Homebrew path `/home/linuxbrew/.linuxbrew/bin/wezterm`
- `Exec` uses `wezterm start` with no `--cwd` flag
- `StartupWMClass=org.wezfurlong.wezterm` matches WezTerm's actual WM_CLASS
- `Icon=org.wezfurlong.wezterm` uses the reverse-DNS name (not `wezterm_lavender`)
- `Categories=System;TerminalEmulator;Utility;` includes the `TerminalEmulator` category
  required for KDE's default terminal selector
- `X-KDE-AuthorizeAction=shell_access` follows KDE terminal convention
- Desktop actions `new-window` and `new-tab` both use absolute Homebrew paths
- `desktop-file-validate` passes (only a hint about dual main categories, which is cosmetic
  and matches Konsole's own entry)

No issues.

### 4. Run-once script: `run_once_after_10-set-wezterm-default-terminal.sh`

**Matches spec exactly.** The script content is identical to the proposal's specified
script (proposal lines 133-148). Safety analysis:

**Shebang:** Uses `#!/bin/sh`, which is more portable than the `#!/bin/bash` used by the
existing `run_once_before_` scripts. The script uses only POSIX constructs (`set -e`,
`command -v`, `||`), so `#!/bin/sh` is correct. This is a minor inconsistency with the
other scripts but not a defect -- it is arguably better practice.

**`set -e`:** Present. The script will abort on any unexpected failure, preventing partial
configuration. The `|| true` guards on cache commands prevent those expected-failure cases
from triggering `set -e`.

**`command -v` guard:** The script checks for `kwriteconfig6` before attempting to use it
and exits cleanly with a message if not found. This makes the script safe to run on non-KDE
systems.

**`kwriteconfig6` calls:** Both `TerminalApplication` and `TerminalService` are set
correctly. `TerminalApplication` gets the absolute binary path, `TerminalService` gets
the `.desktop` filename (without path, as KDE expects).

**Cache rebuilds:** `update-desktop-database` and `gtk-update-icon-cache` are both guarded
with `2>/dev/null || true`, so failures (including the expected `index.theme` missing error)
do not abort the script.

**Naming convention:** `run_once_after_10-` puts this script in the `after` slot at priority
10, matching the archived `run_once_after_10-install-tpm.sh` pattern. No numbering conflict
with active scripts (which are all `before`).

**Idempotency:** The `run_once_` prefix means chezmoi will execute this script exactly once.
Subsequent `chezmoi apply` runs skip it. If the user changes the default terminal via System
Settings, their choice is preserved.

**One observation:** The script does not check whether WezTerm is actually installed before
setting it as the default terminal. If chezmoi is applied on a system without WezTerm, the
script would set kdeglobals to point at a nonexistent binary. However, the `TryExec` in
the `.desktop` file would prevent KDE from showing the entry, and the `run_once_` nature
means this is a one-time operation that the user triggered intentionally. This is acceptable
and consistent with the proposal's design philosophy.

No blocking issues.

## Devlog Quality

### Structure and completeness

The devlog follows the standard structure: Objective, Key References, Plan, Testing
Approach, Implementation Notes (per phase), Changes Made table, and Verification section.
All phases are documented with specific commit hashes and concrete verification output.

### Verification evidence

The verification section provides command output for all 5 phases:

- **Phase 1:** `ls` and `file` confirm the SVG is deployed and valid.
- **Phase 2:** `readlink` and `file -L` confirm the symlink resolves correctly.
- **Phase 3:** `desktop-file-validate` passes (hint-only output shown).
- **Phase 4:** `kreadconfig6` confirms both kdeglobals keys are set correctly.
- **Phase 5:** Aggregates all prior checks, explicitly marks manual testing as pending.

The evidence is thorough for all CLI-verifiable aspects. The devlog correctly identifies
that KRunner search, taskbar icon, right-click actions, and Dolphin "Open Terminal Here"
require manual user verification and lists them as pending.

### Implementation notes quality

Good. Each phase documents what happened, including deviations from the plan:

- Phase 1: `git mv` failed because the file was untracked; used `mv` + `git add` instead.
- Phase 2: `gtk-update-icon-cache` failure explained and justified.
- Phase 3: `desktop-file-validate` hint documented and explained.
- Phase 5: `kstart6` not available; used `krunner --daemon` as a functionally equivalent
  alternative.

These deviation notes are valuable for future readers.

## Proposal Consistency

The implementation artifacts are consistent with the proposal in every material respect.
The `.desktop` file, symlink content, and run_once script are all verbatim matches. The
file paths and chezmoi naming conventions are correct.

**[non-blocking]** The proposal's frontmatter still says `status: implementation_wip`, but
all 5 phases are complete and verified. This should be updated to `implemented` (or
whatever the project convention is for "implementation done, pending final manual testing").

## Frontmatter Compliance

Both the proposal and devlog are missing the `title` and `date` frontmatter fields that
the cdocs writing conventions require ("at minimum: `title`, `date`, `status`"). However,
this appears to be a repo-wide evolution: newer documents use `first_authored.at` instead
of `date` and use the H1 heading as the title. The slate-terminal-theme devlog follows the
same pattern. This is a systemic convention drift, not specific to this workstream.

**[non-blocking]** Either the frontmatter spec should be updated to reflect the current
`first_authored.at` convention, or the documents should add `title` and `date` fields.
This is not blocking for this review since the pattern is consistent across recent documents.

## Verdict

**Accept.**

The implementation is complete and faithful to the accepted proposal. All four artifacts
match the spec exactly. The run_once script is safe, correctly guarded, and idempotent via
chezmoi's `run_once_` mechanism. Verification evidence covers all CLI-testable phases.
Manual testing items (KRunner, taskbar icon, Dolphin) are clearly identified as pending user
verification, which is the appropriate handoff point.

The round 2 review's action items have all been addressed. No regressions or new issues
were found.

## Action Items

1. [non-blocking] Update the proposal's `status` from `implementation_wip` to `implemented`
   to reflect that all 5 phases are complete.
2. [non-blocking] After user manual testing confirms KRunner/taskbar/Dolphin behavior,
   update the devlog status from `review_ready` to `done` and the proposal status to
   `implemented` (or `done` if manual testing passes).
3. [non-blocking] The repo's frontmatter spec lists `title` and `date` as required fields,
   but recent documents (including this one) use `first_authored.at` and the H1 heading
   instead. Consider updating the spec to match current practice, or backfill the fields.
   This affects multiple documents, not just this workstream.

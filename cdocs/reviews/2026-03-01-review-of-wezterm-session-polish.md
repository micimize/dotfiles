---
review_of: cdocs/devlogs/2026-03-01-wezterm-session-polish.md
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-03-01T12:00:00-06:00"
task_list: dotfiles/wezterm
type: review
state: live
status: done
tags: [fresh_agent, implementation_review, session-persistence, missing_validation, commit_traceability]
---

# Review: WezTerm Session Persistence Polish Devlog

## Summary Assessment

This devlog documents two targeted fixes to the WezTerm session persistence stack: a GLOBAL guard to prevent duplicate timers from config re-evaluation and a nushell pre_prompt hook for cleaning stale Wayland symlinks.
The code changes are clean, match the proposal's intent, and the implementation notes capture the one meaningful deviation (unconditional removal vs. liveness filtering).
The primary concern is thin verification evidence: the devlog omits two of the proposal's three Phase 2 validation steps and does not demonstrate that the GLOBAL guard actually prevented timer duplication.
Verdict: **Revise** to strengthen verification records.

## Section-by-Section Findings

### Frontmatter

The frontmatter is well-formed and conforms to the spec.
`type: devlog`, `state: live`, `status: review_ready` are all valid.
Tags are descriptive.
No issues.

### Objective

Clear and concise.
Links to the parent proposal.
BLUF-style opening sentence.
No issues.

### Plan

Correctly mirrors the proposal's two phases.
"Commit after each phase. Validate per CLAUDE.md workflow." sets the right expectation.
No issues.

### Testing Approach (lines 30-34)

The stated approach lists three verification methods: `ls-fonts` stderr, `show-keys` diff, and `nu -c` syntax check.
This is a subset of what the proposal required.
The proposal's Phase 2 validation called for three things:

1. `nu -c "source config.nu"` syntax check (present)
2. Manual test: create a fake stale symlink, open a new shell, verify it's removed (absent)
3. Verify restore prompt still appears correctly after cleanup (absent)

The proposal's Phase 1 validation also called for confirming "only 1 periodic save timer fires" (absent from devlog).

**Finding: [blocking]** The verification section does not demonstrate that the fixes actually work at a functional level, only that they parse.
The GLOBAL guard's whole purpose is preventing duplicate timers, but there is no evidence the timer count was verified (the proposal suggested checking resurrect JSON timestamps after a 5-minute wait).
The symlink cleanup was only syntax-checked; no evidence it actually removes symlinks.

### Implementation Notes: GLOBAL guard approach (lines 38-45)

This section accurately describes the code change.
Verified against `dot_config/wezterm/wezterm.lua` lines 409-471:

- Line 409: `if ok_resurrect and not wezterm.GLOBAL.resurrect_initialized then` (matches)
- Line 410: `wezterm.GLOBAL.resurrect_initialized = true` (matches)
- Line 469: `elseif not ok_resurrect then` (matches)

The note about the `elseif` change is a valuable deviation capture: the proposal did not explicitly mention the need to change the `else` to `elseif`, but it follows logically from the guard.
This is well done.

### Implementation Notes: Symlink cleanup (lines 47-56)

Correctly documents the deviation from the proposal's code snippet (which included a `where` filter for socket type/existence) to unconditional removal.
References the proposal's E1 edge case discussion as justification.

Verified against `dot_config/nushell/config.nu` lines 67-76:

- Line 68: one-shot guard (`_WEZ_RESTORE_OFFERED`) early return (matches)
- Lines 71-76: glob + `rm -f` with no liveness filter (matches the devlog's description)
- Line 78: `WEZTERM_PANE` check is after cleanup (matches devlog's claim)

The devlog's statement that cleanup "runs for every shell session inside WezTerm (not just pane 0)" is correct: each new pane starts a fresh shell with `_WEZ_RESTORE_OFFERED` unset, so the cleanup fires once per pane on first pre_prompt.
However, the cleanup is inside the one-shot guard block, so it only runs on the *first* pre_prompt in each pane.
This is fine for the use case (stale symlinks from before this shell started), but the devlog could be clearer that "every shell session" means "once per pane lifetime at first prompt," not "every prompt."

**Finding: [non-blocking]** The phrase "runs for every shell session inside WezTerm" could be read as "runs on every prompt."
A small clarification ("runs once per shell session") would improve precision.

### Changes Made table (lines 58-63)

Lists both files.
Matches the actual files modified.
No issues.

### Verification: Phase 1 (lines 67-75)

Shows `ls-fonts` clean and `show-keys` diff showing only timestamp changes.
This confirms the config parses and bindings are not regressed.
It does not confirm the GLOBAL guard prevents duplicate timers (the actual functional goal of the change).

**Finding: [blocking]** The verification proves "no regressions" but not "fix works."
At minimum, a note explaining why timer-count verification was skipped (or confirming it was done but not recorded) would satisfy this.

### Verification: Phase 2 (lines 77-82)

Shows `nu -c` syntax check passing.
The proposal's validation plan called for two additional tests: creating a fake stale symlink and verifying the restore prompt still works post-cleanup.
Neither is documented.

**Finding: [blocking]** Syntax-only validation is insufficient for a cleanup hook that touches the filesystem.
Even a brief note like "manually created a stale symlink, confirmed removal on next shell start" would suffice.

### Commits (lines 84-89)

Two commit SHAs are listed: `0363513` and `2c25dc8`.
These SHAs do not appear in the recent git history shown on the current branch (`weztime`).
The most recent commits are:
- `1bee97f docs(cdocs): add proposal, review, and devlog for session persistence`
- `399da56 feat(nushell): auto-trigger session restore on fresh WezTerm boot`

The implementation commits may have been squashed, rebased, or are on a different branch.
Either way, the SHAs as recorded are not directly verifiable from the current HEAD.

**Finding: [non-blocking]** The commit SHAs may be stale references from a pre-rebase history.
If they were squashed, the devlog should note the final squashed SHA instead, or note that the SHAs are pre-rebase.

### Writing Conventions

Multiple lines use em-dashes (lines 25, 26, 50, 55, 74).
The writing conventions prefer colons, commas, periods, or spaced hyphens (` - `) over em-dashes.

**Finding: [non-blocking]** Five uses of em-dashes where the style guide prefers colons or spaced hyphens.

### Proposal Open Questions

The proposal raised one open question: whether the symlink cleanup should also remove stale `gui-sock-*` files from dead GUI PIDs.
The devlog does not address this, either by answering it or by explicitly deferring it.

**Finding: [non-blocking]** The proposal's open question about `gui-sock-*` cleanup is unaddressed.
A brief note in the devlog (even "deferred: `gui-sock-*` cleanup is harmless, not included in this pass") would close the loop.

## Verdict

**Revise.** The implementation itself is correct and well-described: the code matches the devlog, deviations from the proposal are explained, and the approach is sound.
The blocking issue is that the verification records demonstrate only "no regressions" (parse checks), not "fixes work" (functional validation).
The proposal set clear validation criteria that the devlog should either fulfill or explicitly explain why they were skipped.

## Action Items

1. [blocking] Add functional verification evidence for the GLOBAL guard: either a note confirming timer-count observation, or an explanation of why it was deferred to live monitoring.
2. [blocking] Add functional verification evidence for symlink cleanup: at minimum a note confirming manual test (create stale symlink, verify removal) was performed, or explain why it was deferred.
3. [non-blocking] Clarify that symlink cleanup runs "once per shell session" (not every prompt) in the implementation notes.
4. [non-blocking] Verify commit SHAs against current branch HEAD; update if they were squashed or rebased.
5. [non-blocking] Replace em-dashes with colons or spaced hyphens per writing conventions.
6. [non-blocking] Add a brief note addressing the proposal's open question about `gui-sock-*` files (even if just "deferred").

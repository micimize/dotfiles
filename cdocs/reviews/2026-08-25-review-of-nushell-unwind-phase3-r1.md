---
review_of: cdocs/proposals/2026-08-25-nushell-unwind.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T16:45:00-05:00
task_list: nushell-unwind/phase3-downstream-hand-edits
type: review
state: live
status: done
tags: [fresh_agent, devcontainer, migration, shell, weftwise, jif, whelm, clauthier, missing_validation]
---

# Review: Nushell Unwind Phase 3 (Downstream Lace-Consumer Edits)

## Summary Assessment

Phase 3 drops the hand-authored nu shell configuration from the four downstream lace consumers so they inherit bash + ble.sh from the Phase 2 lace flip.
The work is correct, tightly scoped, and well-commented: jif, weftwise, and whelm carry exactly the edits the proposal specifies with valid JSON, clean `bash -n`, and no residual nu in their own committed config, and clauthier is genuinely untouched-clean with no change needed.
The single substantive finding is in weftwise: the restored bash-history bind mount is structurally correct and its host source path exists, but nothing actually points `HISTFILE` at the `/commandhistory` target, and the mount comment's claim that "the restored dotfiles bashrc points HISTFILE here" is false, so the mount does not achieve its stated cross-rebuild persistence.
Verdict: ACCEPT WITH NITS.

## Section-by-Section Findings

### jif (`0ea1a1ad`, `git diff main...nushell-unwind`)

All three seams are removed as specified and the container will still resolve a shell.
The nushell feature (`ghcr.io/eitsupi/devcontainer-features/nushell:0`), the `lace-fundamentals` `defaultShell: /usr/local/bin/nu` override, and `containerEnv.SHELL=/usr/local/bin/nu` are all gone, and `lace-fundamentals` is now `{}`.
`git grep -nIE 'nushell|/nu\b|env\.nu' -- .devcontainer/*` returns nothing on the branch, and no `"SHELL"` key remains.
Shell resolution is sound: `lace-fundamentals: {}` inherits `defaultShell` (bash) from the user-level `~/.config/lace/settings.json` merge, and the flutter base (`ghcr.io/cirruslabs/flutter:3.44.0`) does not bake a nu login shell, so there is no place jif needed an explicit shell. Non-blocking.

The Dockerfile PATH-resolution note is TRUE and is a genuine correctness improvement over the original.
The old comment tied `~/.local/bin` resolution to `env.nu` (`path add "~/.local/bin"`); the rewrite re-attributes it to `/etc/profile.d/99-lace-path.sh`.
That file is really created in the same Dockerfile at lines 122-123 (`printf ... > /etc/profile.d/99-lace-path.sh && chmod 0644 ...`), it prepends `/home/${USERNAME}/.local/bin`, and it sits above the referencing comment at line 136, so "above, which prepends it for every login shell" is accurate.
The line-1 prebuild list (`git, sshd, claude-code, lace-fundamentals`) matches the actual `prebuildFeatures` block after nushell's removal.
JSON (jsonc) parses clean after comment stripping. No issues.

### weftwise (`b8e315a5`, `git diff main...nushell-unwind`)

The `nushell-config` mount to `/home/node/.config/nushell` is removed and a bash-history bind mount is restored, with the `aws-config` security-scoped mount preserved intact and valid JSON.
The highest-risk item passes: the mount source `${localEnv:HOME}/code/dev_records/weft/bash/history` resolves to an existing host directory (`HOME=/home/mjr`, symlinked to `/var/home/mjr`) that already contains a `.bash_history` file.
`.lace/mount-assignments.json` is genuinely generated and git-ignored (`.gitignore:56` ignores `.lace/`; `git ls-files .lace/` is empty), so leaving it untouched is correct.

Finding (non-blocking, highest-value): the mount is functionally inert for its stated purpose, and its comment is inaccurate.
The mount targets `/commandhistory`, but nothing in weftwise's container config points `HISTFILE` there.
The comment asserts "The restored dotfiles bashrc points HISTFILE here," yet the restored dotfiles set no such thing: `dot_config/bash/prompt_and_history.sh` sets only `HISTSIZE`/`HISTFILESIZE`/`HISTIGNORE` plus a `~/.full_history` `PROMPT_COMMAND` logger, and a repo-wide `git grep 'HISTFILE='` in dotfiles finds no `/commandhistory` assignment.
weftwise's own Dockerfile sets no `HISTFILE` either, and the `lace.local/node:24-bookworm` base carries none.
By contrast clauthier, which the comment cites as the mirror, achieves persistence through its OWN Dockerfile (`.devcontainer/Dockerfile:60`, `export HISTFILE=${COMMAND_HISTORY_PATH}/.bash_history`, `COMMAND_HISTORY_PATH=/commandhistory`).
So weftwise mirrors clauthier's mount target but not the `HISTFILE` mechanism that makes the target meaningful; as applied, bash writes to the default `~/.bash_history` and history is not persisted across rebuilds.
This does not block bash from coming up (the Phase 3 acceptance criterion), so it is a nit, but it should be closed by either setting `HISTFILE=/commandhistory/.bash_history` in the restored dotfiles bashrc or adding the clauthier-style `HISTFILE` line to weftwise's Dockerfile, and by correcting the comment either way.

### whelm (`fefdf4f`, `git diff main...nushell-unwind`)

The vendored `/etc/nushell/sprack-hooks.nu` heredoc (the `# Nushell integration` block through `NU_EOF`) is dropped from `.devcontainer/features/sprack/install.sh`, and the bash parity hook is fully intact: `/etc/profile.d/sprack-metadata.sh` still writes its `PROMPT_COMMAND` hook under the `[ -n "${BASH_VERSION:-}" ]` guard, and the metadata-writer install is untouched.
`bash -n` on the branch version is clean, and no `nushell`/`NU_EOF`/`/etc/nushell` references remain in the file.
The devcontainer.json comment rewrite is accurate: it drops the stale "node feature's su-based bootstrap chokes on '&&' under nushell" rationale and correctly states the default shell is now bash (set via `lace-fundamentals` chsh) so the node feature's su bootstrap runs cleanly, while noting prebuilding still bakes portless for deterministic build order.
JSON parses clean. No issues.

### clauthier (`main`, no branch)

Independently confirmed truly clean, and the implementer was right to make no branch or commit.
`git grep -nIE 'nushell|/nu\b|env\.nu'` over tracked non-cdocs, non-markdown files returns nothing, there is no `defaultShell` override in `.devcontainer/*`, and its Dockerfile already persists bash history (`ARG COMMAND_HISTORY_PATH="/commandhistory"`, `touch`, and the `HISTFILE` export at lines 6/41/60).
The uncommitted working-tree changes present in the checkout (`plugins/cdocs/skills/*`, some new cdocs docs) are unrelated to nushell-unwind. No change was needed. Confirmed.

### Residual nu (all edited repos)

No nu default-shell reference remains in any project's OWN committed config.
The only nu-adjacent hits across the edited repos are inside `.lace/` generated artifacts (correctly excluded) and historical cdocs devlogs, neither of which is live config.

## Verdict

ACCEPT WITH NITS.

The Phase 3 code is correct and complete against the proposal: every hand-authored nu seam is removed, JSON and `bash -n` are clean, the bash parity hook and aws-config mount are preserved, the highest-risk weftwise mount source exists, and clauthier is verifiably no-op.
The lone open item is the weftwise `HISTFILE`/`commandhistory` gap plus its inaccurate mount comment, which is a functional-completeness and accuracy nit rather than a blocker, since it does not prevent any container from coming up as bash.
Live end-to-end `lace up` verification remains the overseer's job per the task's containment note.

## Action Items

1. [non-blocking] weftwise: make the restored `/commandhistory` mount actually persist history by setting `HISTFILE=/commandhistory/.bash_history` (in the restored dotfiles bashrc, or clauthier-style in weftwise's own Dockerfile). Without it the mount is inert.
2. [non-blocking] weftwise: correct the mount comment, which claims "the restored dotfiles bashrc points HISTFILE here" - it does not; the dotfiles set only `HISTSIZE`/`HISTFILESIZE`/`HISTIGNORE` plus a `~/.full_history` logger.
3. [non-blocking] Overseer: run the deferred live `getent passwd node` + `${BLE_VERSION}` checks on jif, weftwise, and whelm after the next `lace up` to close the end-to-end floor Phase 3 defers.

## Clarifications Requested

The `HISTFILE` fix has a placement choice worth an explicit decision:

- Option A: Set `HISTFILE=/commandhistory/.bash_history` in the restored dotfiles bashrc. Centralizes the convention for every lace container that mounts `/commandhistory`, but couples the host dotfiles to a container-only path (guard with a `[ -d /commandhistory ]` test).
- Option B: Add the clauthier-style `HISTFILE` export to weftwise's own Dockerfile. Keeps the container path out of host dotfiles and exactly mirrors clauthier, at the cost of per-repo duplication.
- Option C: Accept the mount as decorative for now and only fix the comment (Action Item 2), deferring real persistence. Lowest effort, but leaves a mount that does nothing.

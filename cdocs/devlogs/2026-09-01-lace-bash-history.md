---
title: "Devlog: Persistent Per-Project Bash History Implementation"
date: 2026-09-01
status: in_progress
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T18:00:00-07:00
type: devlog
state: live
task_list: bash/history-persistence
proposal: cdocs/proposals/2026-09-01-lace-persistent-bash-history.md
---

# Devlog: Persistent Per-Project Bash History Implementation

> BLUF(overseer/lace-bash-history): Iterate-loop overseer devlog for implementing the accepted (round 2) persistent-per-project bash-history proposal.
> Pure plain-text design only: mount-wiring fix + endless/timestamped `HISTFILE` + append-only archive on a per-project `/bash-history` mount.
> No rich tools (atuin/stinkpot/mcfly). Spans dotfiles, lace, and downstream consumers (weftwise, clauthier; jif/whelm inherit).

## Brief (Turn 0)

### Scope

Full proposal, executed phase by phase with a review gate between phases:

1. Phase 1: dotfiles bash tuning + archive routing (dotfiles repo only, local + reversible).
2. Phase 2: lace `bash-history` feature declaring the `/bash-history` mount, ghcr publish, `~/.config/lace/user.json` enable.
3. Phase 3: cross-repo repointing with history-preserving migration (lace devcontainer.json, weftwise, clauthier; verify jif/whelm inherit).

### Verification floor

> A freshly-built lace container has `/bash-history` bind-mounted to `~/.config/lace/<projectId>/mounts/bash-history/history`; `HISTFILE=/bash-history/.bash_history` carries `#<epoch>` timestamp lines with `HISTSIZE=HISTFILESIZE=-1`; a marker written to history survives a container rebuild; a second distinct project gets a distinct store; the `~/.full_history` archive routes to `/bash-history/full_history` in-container; and no consumer repo references `/commandhistory`.
> Failure picture: history lost on rebuild, commingled across projects, missing timestamps or truncated, or any repo still referencing `/commandhistory`.

### Containment

- dotfiles: committed on `main`, consistent with the cdocs + prior nushell-unwind commits already there.
- lace, weftwise, clauthier: a `bash-history` branch per repo; merge/PR left to the supervisor.
- Live/outward-facing actions (ghcr feature publish, `~/.config/lace/user.json` edit, container rebuilds) are gated: the overseer escalates to the supervisor at the Phase 2 boundary before publishing or flipping live user config, mirroring the nushell-unwind publish-before-use authorization.

### Constraint

Strict plain-text only. No atuin/stinkpot/mcfly. No leading-slash `.chezmoiignore` patterns (chezmoi 2.72 regression from nushell-unwind).

## Iteration Log

| iteration | implementer | reviewer | review_verdict | review_proof | review_path | notes |
|---|---|---|---|---|---|---|
| 1 | impl-1 (general-purpose) | rev-1 (cdocs:reviewer) | accept | confirmed | cdocs/reviews/2026-09-01-review-of-lace-bash-history-phase1-r1.md | Phase 1 dotfiles tuning. Commit `3a72355` on main. Empirically confirmed in live ble.sh pty: HISTSIZE/FILESIZE=-1, ignoreboth, HISTTIMEFORMAT set, ble.sh loads, `history -a` flush runs each prompt via starship-absorbed `$STARSHIP_PROMPT_COMMAND` (proven by archive growth), single clean archive stamp (double-stamp stripped), host-guard falls back safely with `/bash-history` absent. One non-blocking proposal-side defect: the Verification Methodology's `grep 'history -a'` proxy false-negatives under starship; overseer fixed the proposal block. Container-only checks correctly deferred to P2/P3. |

## Judge Log

| judge_iteration | trigger | verdict | rationale | judge_path |
|---|---|---|---|---|

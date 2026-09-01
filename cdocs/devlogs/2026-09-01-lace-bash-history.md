---
title: "Devlog: Persistent Per-Project Bash History Implementation"
date: 2026-09-01
status: done
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T18:00:00-07:00
type: devlog
state: done
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
| 2 | impl-2 (general-purpose) | rev-2 (cdocs:reviewer) | accept | confirmed | cdocs/reviews/2026-09-01-review-of-lace-bash-history-phase2-r1.md | Phase 2 lace `bash-history` feature. Authored on `bash-history` branch, published via release run 33530363819 to lace `main` `a823954`; ghcr manifest HTTP 200 on tags 1/1.0/1.0.0/latest (re-fetched). `user.json` flipped (backup `.bak-bash-history`). Durable floor confirmed via persisted host store `~/.config/lace/jif/mounts/bash-history/history/` (marker + 21 `#<epoch>` lines + archive survive outside the image == rebuild-survival by construction); live jif container showed HISTFILE=/bash-history/.bash_history bind-mounted; two distinct per-projectId stores (jif, clauthier). Phase 3 boundary intact (no clauthier/weftwise source touched; only generated `.lace/*`). Non-blocking: clauthier store dir empty (keying-level isolation shown, not content-level); dropped `USER_HOME` var benign. Env note surfaced to supervisor: stale global `lace` launcher path. |
| 3 | impl-3 (general-purpose) | rev-3 (cdocs:reviewer) | accept | confirmed | cdocs/reviews/2026-09-01-review-of-lace-bash-history-phase3-r1.md | Phase 3 downstream repointing. Three unmerged branches: `lace/bash-history-p3@1856a1c` (target `/commandhistory`→`/bash-history` + drop Dockerfile `COMMAND_HISTORY_PATH`/`.bashrc HISTFILE` hack), `weftwise/bash-history@915cc97b` (drop hardcoded global mount + false comment), `clauthier/bash-history@b5de042` (drop dead Dockerfile hack). All `git grep commandhistory` clean under `.devcontainer/`; none merged (each `main` HEAD unrelated). weftwise history preserved: 76-line blob md5-identical in weftwise's own store, no clobber, isolated. whelm rebuild-survival PASSED live (`lace up --rebuild`): pre-rebuild `unique-marker-550-1788281127` present in the recreated container, post-rebuild append still lands on the mount, epoch stamps present, HISTFILE/HISTSIZE/HISTTIMEFORMAT inherited with no per-repo edit. Four distinct per-projectId stores (clauthier/jif/weftwise/whelm), all differing md5. No rich-tool leakage. Removing the stale `.bashrc HISTFILE=/commandhistory` was a correctness fix (it would have shadowed the feature mount). clauthier/weftwise full rebuilds corroborated-by-config+persisted-state (mechanism proven identical via whelm), skipped under session limit. |

## Judge Log

| judge_iteration | trigger | verdict | rationale | judge_path |
|---|---|---|---|---|
| — | n/a | n/a | Judge never invoked: all three reviews returned `accept` on first pass (no `revise`), so the `--judge-after 3` threshold and the discretionary triggers were never reached. | inline |

## Overseer Synthesis (Loop Terminated: Accept)

> BLUF(overseer/lace-bash-history): All three phases implemented and accepted first-pass. The plain-text, per-project, endless, timestamped bash-history design is live end-to-end and proven by a real container rebuild-survival test. Dotfiles and the lace feature are merged/published; three downstream repointing branches are verified and await the supervisor's merge.

### What is live now (no further action needed)
- **Dotfiles** (`main` `3a72355`): `HISTSIZE/HISTFILESIZE=-1`, `HISTCONTROL=ignoreboth`, `HISTTIMEFORMAT='%F %T '`, explicit `history -a` flush (via starship-absorbed `PROMPT_COMMAND`), `/commandhistory`→`/bash-history` guard, `_FULL_HISTORY` archive routed onto the mount with a single clean timestamp.
- **Lace `bash-history` feature** (`main` `a823954`, published `ghcr.io/weftwiseink/devcontainer-features/bash-history:1`) enabled in live `~/.config/lace/user.json`. Every container this user builds now auto-injects the per-project `/bash-history` mount and `HISTFILE`.
- **Verified end-to-end**: marker written pre-rebuild survived a full `lace up --rebuild` on whelm; four distinct per-projectId host stores; weftwise's prior 76-line history preserved into its own store.

### Remaining supervisor action: merge three branches (left unmerged by design)
- `lace` branch `bash-history-p3` (`1856a1c`) — repoint lace's own devcontainer + drop its Dockerfile hack.
- `weftwise` branch `bash-history` (`915cc97b`) — drop the hardcoded global mount.
- `clauthier` branch `bash-history` (`b5de042`) — drop the dead Dockerfile hack.
These are cleanups: the user-level feature already delivers persistence to all repos regardless of merge. Merging removes the now-redundant/misleading per-repo config.

### Out-of-scope items surfaced for the supervisor
- The global `lace` shim (`~/.local/share/pnpm/lace`) points at a stale pre-worktree dist path and errors `MODULE_NOT_FOUND`; re-link it to a worktree.
- weftwise has `.vscode/.history/*` editor artifacts still mentioning `commandhistory` (editor local-history, not source); ignorable.
- Per-worktree (vs per-repo) isolation and any rich-metadata tool remain explicit out-of-scope follow-ups (see proposal §Follow-ups).

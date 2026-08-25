---
title: "Devlog: Nushell Unwind Implementation"
date: 2026-08-25
status: in_progress
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T15:00:00-05:00
type: devlog
state: live
task_list: 2026-08-25-nushell-unwind
proposal: cdocs/proposals/2026-08-25-nushell-unwind.md
---

# Devlog: Nushell Unwind Implementation

> BLUF(overseer/nushell-unwind): Iterate-loop overseer devlog for implementing the accepted nushell-unwind proposal.
> The workstream restores bash + ble.sh as the default shell across the dotfiles repo, the lace devcontainer framework, and four downstream consumers (jif, weftwise, clauthier, whelm), then flips live machine state (chsh + `~/.config/lace/settings.json`).

## Brief (Turn 0)

### Scope

The loop implements the full accepted proposal, executed **phase by phase** with a review gate between phases:

1. Phase 1: dotfiles host restore (bash + ble.sh default, tmux `default-shell`, bash-side starship/zoxide init, `wt-clone` port) and the live `chsh` (gated behind ble.sh validation).
2. Phase 2: lace ble.sh devcontainer feature + de-default nu + `~/.config/lace/settings.json` edit.
3. Phase 3: downstream hand-edits (jif, weftwise) plus whelm's vendored-sprack nu block; verify clauthier + whelm inherit bash.
4. Phase 4: cleanup (devcontainer-lock regen, lace-fundamentals examples/installsAfter, README, test fixtures, drop lace sprack nu hook).

Rationale for phase-by-phase: the change spans six repos and mutates the live working environment, so per-phase review gates contain risk and keep the cascade ordering (Phase 2 before Phase 3) honest.

### Containment strategy

- No single worktree contains this workstream (it spans six repos + live machine state).
- dotfiles: committed on `main`, consistent with the cdocs commits already landed there.
- lace, jif, weftwise, clauthier, whelm: a `nushell-unwind` branch per repo; merge/PR left to the supervisor.
- Live machine-state changes (`chsh`, `~/.config/lace/settings.json`) are explicitly authorized by the supervisor ("flip machine state too") and are sequenced LAST within their phase, after their prerequisite config is validated.

### Verification floor

> A newly opened login shell on the host is bash with ble.sh loaded (`BLE_VERSION` set when interactive) and the lace prompt module intact, AND a freshly `lace up`'d container reports `getent passwd node` = `/usr/bin/bash` and drops the user into bash with parity config.
> Failure picture: any new terminal or container that still launches nushell, or a bash shell that is missing ble.sh / starship / the ported aliases, is a failure. The current live session must never be left without a working shell.

## Iteration Log

| iteration | implementer | reviewer | review_verdict | review_proof | review_path | notes |
|---|---|---|---|---|---|---|

## Judge Log

| judge_iteration | trigger | verdict | rationale | judge_path |
|---|---|---|---|---|

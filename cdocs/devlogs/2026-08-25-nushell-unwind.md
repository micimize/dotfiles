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
last_reviewed:
  status: accepted
  by: "@claude-opus-4-8"
  at: 2026-08-25T11:10:00-05:00
  round: 1
  scope: phase1
  verdict: accept_with_nits
  review_of: cdocs/reviews/2026-08-25-review-of-nushell-unwind-phase1-r1.md
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
| 1 | impl-1 (general-purpose) | rev-1 (cdocs:reviewer) | accept | confirmed | cdocs/reviews/2026-08-25-review-of-nushell-unwind-phase1-r1.md | Phase 1 host restore. Accept-with-nits; all 3 nits resolved by overseer: live `default` tmux server refreshed to bash (new panes only), starship init guarded, stale test sockets removed. Live-interactive ble.sh load cited in review. Literal `chsh`/`usermod` not runnable (Fedora Atomic, needs root+password) but login shell already `/bin/bash` == `/usr/bin/bash`, so floor met; optional cosmetic `usermod` documented for the supervisor. |

## Judge Log

| judge_iteration | trigger | verdict | rationale | judge_path |
|---|---|---|---|---|

## Phase 1: Dotfiles host restore (implemented)

> BLUF: bash + ble.sh restored as chezmoi-managed config and deployed. Host now launches bash everywhere (login shell, tmux panes). ble.sh, starship, zoxide, and the ported `wt-clone` all verified working in a real interactive bash. The literal `chsh` to `/usr/bin/bash` could not be run (tooling/permission gate, detailed below) but the login shell is already `/bin/bash`, the same binary, so the host is fully on bash with no working-shell risk.

### What changed

- **Restored `dot_bashrc`** (chezmoi -> `~/.bashrc`) from the `742fd97^` version. Reconciliation: `BASHFILES_DIR` now points at `$XDG_CONFIG_HOME/bash` (the new chezmoi-managed helper location) instead of `$DOTFILES_DIR/archive/legacy/bash`. Legacy `vscode/init.sh`, `blackbox/blackbox.sh`, `macos/macos.sh` are still sourced from the repo working tree under `archive/legacy/` (out of scope to relocate) but are now guarded with `[ -f ... ]` existence checks so a missing extra can never break login. Kept the guarded `wt` (lace) shell-init line already present in the live deployed file (harmless no-op when `wt` is absent).
- **Restored `dot_blerc`** (chezmoi -> `~/.blerc`) byte-identical to `742fd97^` / `archive/legacy/bash/blerc`.
- **Recreated the four sourced helpers as chezmoi-managed files** deploying to `~/.config/bash/`: `dot_config/bash/{aesthetics.sh,completions.sh,prompt_and_history.sh,utils.sh}`. Content sourced from `archive/legacy/bash/*.sh`.
  - `prompt_and_history.sh`: added `command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"` alongside the existing `eval "$(starship init bash)"`, before `source "$BLESH_DIR/ble.sh"`.
  - `utils.sh`: added the `wt-clone` bash port (see below).
- **Restored the ble.sh installer** `run_once_before_20-install-blesh.sh` to the repo root from `archive/legacy/chezmoi_run_once/`.
- **`.chezmoiignore`**: root-anchored the legacy `archive/`, `bash/`, `blackbox/` exclusions to `/archive/`, `/bash/`, `/blackbox/`. The unanchored `bash/` pattern would otherwise have matched (and ignored) the new `~/.config/bash/` helpers. Surgical: nothing else changed; runtime-generated nushell scripts stay ignored.
- **`dot_config/tmux/tmux.conf`**: replaced the nushell `default-shell`/`default-command` (`~/.cargo/bin/nu`) with the archived approach `set -g default-shell $SHELL` + `set -g default-command "${SHELL}"`. Kept `default-command` (rather than dropping it as the proposal text suggested) so panes are non-login interactive shells that reliably source `~/.bashrc`/ble.sh; `$SHELL` resolves to bash. The PATH `set-environment` block was left intact.
- **Kept `dot_config/starship.toml` unchanged** (the `[custom.container]` `LACE_PROJECT_NAME` module and the `[custom.dir]` module both spawn `bash --noprofile --norc` internally, so they are shell-agnostic and work under bash).
- **Did not delete** the `dot_config/nushell/` tree (retained for the two lace host scripts); nu is simply no longer any shell's default. Did not touch `dot_config/wezterm/`.

### wt-clone bash port

Ported `dot_config/nushell/scripts/wt-clone.nu` to a bash function `wt-clone` in `dot_config/bash/utils.sh`. Preserves: reserved-name guard (`.bare`/`.git`/`.worktree-root`), SSH/HTTPS repo-name derivation, bare clone + `+refs/heads/*` refspec + fetch, default-branch detection via `symbolic-ref HEAD`, worktree add, the relative-gitdir fixups (`.git` -> `gitdir: ./.bare`, worktree `.git` -> `gitdir: ../.bare/worktrees/NAME`, bare `worktrees/NAME/gitdir` -> `../../NAME`), the `.worktree-root` marker, submodule/devcontainer hints, and the `-b/--branch`, `-n/--name`, `--shallow` flags.

### Evidence (verification floor)

- `getent passwd $USER` -> `/bin/bash`. Note: `/bin -> usr/bin` on this host and `readlink -f` shows `/bin/bash` and `/usr/bin/bash` are the identical binary; login shell is bash.
- `~/.local/share/blesh/ble.sh` exists on disk (pre-built, 2025-09-01; the run_once installer is now restored so a fresh machine rebuilds it).
- ble.sh loads in a real interactive bash: a fresh detached tmux pane running `/usr/bin/bash -il`, queried with `echo $0 ${BLE_VERSION}`, returned `/usr/bin/bash ble=0.4.0-devel4+8060b7ad` with the starship prompt (`main` branch + git status) rendered. `bash -ic '...'` and `script -qec 'bash -ilc ...'` both report `BLE_VERSION` empty because ble.sh only attaches inside a live interactive prompt loop, not for one-shot `-c` commands -- the tmux-pane query is the correct interactive check.
- New tmux servers launch bash: an isolated `tmux -L vtest -f ~/.config/tmux/tmux.conf` session (no explicit command, exercising `default-command`) produced a pane with `$0 = /usr/bin/bash`.
- `wt-clone` is defined as a bash function (`type -t wt-clone` -> `function`).
- The lace prompt module is preserved: `dot_config/starship.toml` `[custom.container]` with `LACE_PROJECT_NAME` is unchanged.

### Deviation: live chsh could not be executed (manual step required)

`chsh` is not installed on this Fedora Atomic host (only `/usr/etc/pam.d/chsh` exists); `usermod` exists but requires root and `sudo -n` reports a password is required, so no non-interactive path to set the login shell exists. This is NOT a ble.sh failure (ble.sh builds and loads), so it does not trip the investigation gate. Mitigating fact: the login shell is already `/bin/bash` (== `/usr/bin/bash`), so nushell is not the login shell and the user is not left without a working shell.

Manual step for the user to set the literal `/usr/bin/bash` path (optional; cosmetic since the binary is identical):

```sh
sudo usermod -s /usr/bin/bash "$USER"   # or: chsh -s /usr/bin/bash  (if chsh installed)
```

Revert path (if ever needed): `sudo usermod -s ~/.cargo/bin/nu "$USER"` (or `chsh -s ~/.cargo/bin/nu`). Nu stays installed and is a valid login shell, so rollback is clean.

### Notes for later phases (not done here)

- RESOLVED by overseer during review round 1: the live `default` tmux server (socket `/tmp/tmux-1000/default`, holding `main`/`lace-local`/`vscode_*` sessions) had held the old nu `default-command`/`default-shell` in memory. Setting these options affects only newly created panes/windows, not active panes, so the overseer applied `tmux -S /tmp/tmux-1000/default set -g default-shell /usr/bin/bash` and `... set -g default-command /usr/bin/bash` live. New panes now launch bash + ble.sh. Stale test sockets (`vtest`, `revtest`, `revtest2`) were removed.
- Phases 2-4 (lace feature, downstream repos, cleanup) are out of scope for this dispatch.

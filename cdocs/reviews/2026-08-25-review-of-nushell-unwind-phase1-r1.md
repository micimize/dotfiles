---
review_of: cdocs/devlogs/2026-08-25-nushell-unwind.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T11:10:00-05:00
task_list: 2026-08-25-nushell-unwind
type: review
state: live
status: done
tags: [fresh_agent, phase1, shell, blesh, tmux, chezmoi, live_state, verification_floor]
---

# Review: Nushell Unwind, Phase 1 (Dotfiles Host Restore)

## Summary Assessment

Phase 1 restores bash + ble.sh as chezmoi-managed host config and deploys it live.
The durable deliverable is correct and complete: the login shell is bash, a fresh interactive bash loads ble.sh + starship + zoxide, the ported `wt-clone` function is present, the nushell tree is retained (de-default, not removal), and the `.chezmoiignore` surgery deploys the new helpers without un-ignoring runtime-generated files.
I re-verified every floor claim empirically against the live host and the committed diff, not just the devlog.
One residual live-state gap keeps this from a clean Accept: the user's currently-running tmux `default` server still holds `default-command /home/mjr/.cargo/bin/nu` in memory, and wezterm attaches to it with `-A -s main`, so new panes/windows in the live session still launch nushell until that server is restarted.
Verdict: **ACCEPT WITH NITS**. The config deliverable meets the floor; close the live-server gap with a safe one-liner (below) and correct one inaccurate rationale in the devlog.

## Verification Floor: Empirical Results

The floor requires a newly opened login/interactive shell to be bash with ble.sh loaded, the lace prompt module intact, and the live session never left without a working shell.

Login shell is bash, and the two paths are the same binary:

```text
$ getent passwd mjr | awk -F: '{print $7}'   ->  /bin/bash
$ readlink -f /bin/bash                       ->  /usr/bin/bash
$ readlink -f /usr/bin/bash                   ->  /usr/bin/bash
```

`/bin` is a symlink to `usr/bin` on this host, so `/bin/bash` and `/usr/bin/bash` resolve to one binary.
The implementer's identity claim is confirmed.

ble.sh loads in a real interactive bash (fresh detached tmux pane running `/usr/bin/bash -il`):

```text
$ tmux send-keys 'echo MARKER $0 ble=${BLE_VERSION:-NONE}'
MARKER /usr/bin/bash ble=0.4.0-devel4+8060b7ad
```

The starship prompt (branch + git status) rendered in that pane.
As the proposal and devlog both note, one-shot `bash -ic '...'` reports `BLE_VERSION` empty because ble.sh only attaches inside a live prompt loop; the tmux-pane query is the correct interactive check.

On-disk artifacts exist and are chezmoi-managed:

```text
$ ls ~/.local/share/blesh/ble.sh              ->  present (1055719 bytes)
$ git ls-files | grep blesh                   ->  run_once_before_20-install-blesh.sh (repo root, restored)
$ ls ~/.config/bash/                          ->  aesthetics.sh completions.sh prompt_and_history.sh utils.sh
$ chezmoi managed | grep -E 'bash|blesh'      ->  .bashrc .blerc .config/bash/* 20-install-blesh.sh
```

The lace prompt module is intact: `dot_config/starship.toml` is unchanged, and its `[custom.container]` `LACE_PROJECT_NAME` module is retained (not reverted to `archive/legacy/bash/starship.toml`).

## Section-by-Section Findings

### tmux default-shell change (deployed and correct, but a live-server gap remains)

The deployed `~/.config/tmux/tmux.conf` matches source and carries the bash default (non-blocking on the file itself):

```text
$ diff <(chezmoi cat ~/.config/tmux/tmux.conf) ~/.config/tmux/tmux.conf   ->  identical
11: set -g default-shell $SHELL
12: set -g default-command "${SHELL}"
```

No line still hardcodes `~/.cargo/bin/nu`.
A fresh isolated tmux server built from this config launches bash + ble.sh when `SHELL` is bash:

```text
$ SHELL=/usr/bin/bash tmux -L test -f ~/.config/tmux/tmux.conf new-session ...
PANEB /usr/bin/bash ble=0.4.0-devel4+8060b7ad
```

**[blocking-adjacent] The live `default` tmux server still defaults to nushell.**
The running server was left unmodified:

```text
$ tmux -S /tmp/tmux-1000/default show-options -g | grep default-
default-command /home/mjr/.cargo/bin/nu
default-shell   /home/mjr/.cargo/bin/nu
```

wezterm's launch path attaches to this exact server rather than starting a fresh one:

```text
dot_config/wezterm/wezterm.lua:53
config.default_prog = { 'tmux', 'new-session', '-A', '-s', 'main' }
```

`-A` attaches to the existing `main` session, so opening a new wezterm window, splitting a new pane, or creating a new window in the live server all inherit the in-memory `default-command = nu` and launch nushell.
This is squarely the floor's failure picture ("any new terminal that still launches nushell is a failure") for the live session, not just a cosmetic leftover.
It resolves on its own at the next full server restart (reboot or `tmux kill-server`), and every fresh server is bash, so the delivered config is not defective; the gap is stale live state.

The devlog's stated reason for not touching the live server is inaccurate and worth correcting:

> "A `tmux source-file` only updates options for new sessions in that server, and was intentionally not forced on the live server to avoid disrupting active panes."

Setting `default-command` on the live server does not disrupt active panes; tmux only consults `default-command` when spawning a new pane/window, so existing panes are untouched.
The safe closure (does not touch any running pane) is:

```sh
tmux -S /tmp/tmux-1000/default set -g default-shell "$SHELL"
tmux -S /tmp/tmux-1000/default set -g default-command "$SHELL"
```

Alternatively, instruct the user to restart the tmux server when convenient.

### Ambient `$SHELL` coupling (minor, not a real-host defect)

`default-command "${SHELL}"` makes the pane shell follow whatever `SHELL` the process that starts the tmux server exports.
In this review's harness, `SHELL=/usr/bin/zsh`, and an isolated server produced a zsh pane, not bash.
On the real host this is not a defect: the running login environment exports `SHELL=/bin/bash` (confirmed via the live server's global env `show-environment -g SHELL -> SHELL=/bin/bash`, consistent with the bash passwd entry), so the real login path resolves to bash.
Flag only as a latent coupling: if a future graphical session ever exports a non-bash `SHELL`, panes would follow it.
Keeping `default-command` (over the proposal's suggestion to drop it) is otherwise a reasonable choice, since it makes panes non-login interactive shells that reliably source `~/.bashrc` and ble.sh.

### Restored bash config and helpers (correct, one consistency nit)

`~/.bashrc`, `~/.blerc`, and the four `~/.config/bash/*.sh` helpers are in sync with source and source each other consistently.
`~/.bashrc` sources the four helpers from `$BASHFILES_DIR` (`$XDG_CONFIG_HOME/bash`) and guards the legacy `archive/legacy/*` extras with `[ -f ... ]`, so a missing extra cannot break login.
`~/.bash_profile` sources `~/.bashrc`, so a real TTY/console login also loads ble.sh; no nu reroute exists there.
The ble.sh source path is consistent: `BLESH_DIR="$HOME/.local/share/blesh"` in `~/.bashrc`, sourced as `$BLESH_DIR/ble.sh` in `prompt_and_history.sh`, and the installer builds to `PREFIX=$HOME/.local`.

**[non-blocking] starship init is unguarded while zoxide is guarded.**
`dot_config/bash/prompt_and_history.sh:100-102`:

```bash
eval "$(starship init bash)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
source "$BLESH_DIR/ble.sh"
```

The zoxide line got a `command -v` guard but the starship line did not, so a host missing starship would emit a "command not found" at login.
Both are installed here, so this is cosmetic; add a matching guard for symmetry and robustness on a fresh machine.

### wt-clone bash port (correct)

`wt-clone` is defined as a bash function (`type -t wt-clone -> function`) in `dot_config/bash/utils.sh`.
The port preserves the reserved-name guard (`.bare`/`.git`/`.worktree-root`), SSH/HTTPS repo-name derivation, bare clone + `+refs/heads/*` refspec, default-branch detection via `symbolic-ref HEAD`, the relative-gitdir fixups, the `.worktree-root` marker, and the `-b/-n/--shallow` flags.
Failure paths clean up the partial target with `rm -rf`.
Logic matches the described nu original; no correctness issue found.

### De-default, not removal (correct)

`dot_config/nushell/` is retained (11 tracked files: `config.nu`, `env.nu`, `login.nu`, `scripts/`), so nu remains usable for the two host scripts.
No config file outside the `nushell/` tree references nu as a shell default; the only `usermod`/nu co-occurrence in the repo is an explanatory comment in `scripts/fix-atomic-home.nu`, not a login-shell setter.
Nothing launches nu by default at the config level.

### .chezmoiignore surgery (correct)

The exclusions are root-anchored to `/archive/`, `/bash/`, `/blackbox/`, so the unanchored `bash/` pattern no longer swallows the new `~/.config/bash/` helpers, which now deploy (confirmed via `chezmoi managed`).
Runtime-generated nushell scripts stay ignored: `.config/nushell/scripts/generated/` (line 27) is intact.
The change is surgical; nothing else was un-ignored.

## Assessment of the chsh Deviation

The floor is genuinely met despite the literal `chsh -s /usr/bin/bash` not running.
`chsh` is absent on this Fedora Atomic host (`command -v chsh` empty; only `usermod` exists, which needs root and a password `sudo -n` cannot supply), so the implementer could not run it non-interactively.
This is not a ble.sh failure, so it does not trip the investigation gate.
The mitigating fact holds under scrutiny: the passwd login shell is already `/bin/bash`, which is byte-identical to `/usr/bin/bash` (verified above), and `/usr/bin/bash` is listed in `/etc/shells`, so a future `usermod`/`chsh` would only cosmetically change the path string, not the shell.

I searched for any other path that lands the user in nushell as a login/interactive default:

- passwd login shell: bash (authoritative).
- `~/.bash_profile` / `~/.profile` / `~/.bash_login`: only `.bash_profile` exists and it sources `.bashrc`; no nu, no `exec`.
- repo shell rc and config: no nu shell-default outside the retained `nushell/` tree.

The one remaining real path is the live tmux `default` server described above, which is stale in-memory state rather than a login/rc default.
Net: the chsh deviation is acceptable; the live-server gap is the item to close.

## Verdict

**ACCEPT WITH NITS.**
The Phase 1 config deliverable is correct, deployed, and meets the verification floor at the login and fresh-shell level, with empirical evidence for every floor claim.
The blocking-adjacent item is live state, not a code defect: the running tmux server still spawns nushell for new panes/windows until it is refreshed, which contradicts the floor's "no new terminal launches nushell" for the current session.
Close it with the safe one-liner (or a server restart) and fix the inaccurate devlog rationale, then this is a clean Accept.
No changes to Phase 1 source files were made during this review, and nothing was committed.

## Action Items

1. [blocking-adjacent] Refresh the live tmux `default` server so new panes stop launching nushell: `tmux -S /tmp/tmux-1000/default set -g default-shell "$SHELL"; tmux -S /tmp/tmux-1000/default set -g default-command "$SHELL"` (safe for active panes), or restart the server at the next convenient point. Until then, new panes/windows in the current wezterm/tmux session still launch nushell.
2. [non-blocking] Correct the devlog note that claims applying options to the live server would disrupt active panes: `default-command` is consulted only when spawning a new pane, so existing panes are unaffected.
3. [non-blocking] Guard the starship init line in `dot_config/bash/prompt_and_history.sh:100` with `command -v starship >/dev/null 2>&1 &&`, matching the zoxide line, for robustness on a fresh machine.
4. [non-blocking] Optionally record in the devlog that `default-command "${SHELL}"` couples pane shell to the ambient `SHELL`; benign on this host (real login exports `SHELL=/bin/bash`) but a latent dependency worth noting for the container phases where `SHELL` is set to nu paths.

## Open Questions for the Overseer

The live-server gap sits on the boundary between "delivered config" and "live-state application." How should it be classified for the phase gate?

- Option A: Treat as an ACCEPT WITH NITS closed by action item 1; the durable config is correct and the floor is met for fresh shells and login. (Reviewer's recommendation.)
- Option B: Treat as REVISE because the normal user action (new wezterm window -> attach `main` -> new pane) still yields nushell in the live session, tripping the floor's failure picture until the server is refreshed.
- Option C: Accept as-is and fold the tmux-server refresh into the Phase 2 dispatch, since Phase 2 already mutates live state and the user will be actively rebuilding containers then.

---
review_of: cdocs/proposals/2026-09-01-lace-persistent-bash-history.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T09:05:00-07:00
task_list: bash/history-persistence
type: review
state: done
status: done
tags: [fresh_agent, phase1, bash, history, blesh, runtime_validated, starship, plain_text]
---

# Review: Lace Persistent Bash History, Phase 1 (Dotfiles tuning + archive routing)

## Summary Assessment

Phase 1 tunes `dot_config/bash/prompt_and_history.sh` for endless, timestamped, per-project bash history and routes the append-only archive onto the `/bash-history` mount, in commit `3a72355` (dotfiles-only).
The implementation is correct, complete for its scope, and empirically validated in a genuine interactive ble.sh shell: all six required changes are present, the deployed file matches source, the archive stamps cleanly with no double-stamp, and the host-guard falls back without error.
The one nuance worth flagging is not a defect in the code but in the proposal's own verification recipe: starship absorbs the flush into `$STARSHIP_PROMPT_COMMAND`, so the proposal's `echo "$PROMPT_COMMAND" | grep -q 'history -a'` proxy check gives a false negative. The flush nonetheless runs every prompt, proven by the archive growing across prompt cycles.
**Verdict: Accept.**

## Scope Boundary (what Phase 1 is and is NOT)

Phase 1 is dotfiles-only (`dot_config/bash/prompt_and_history.sh`).
The following are **Phase 2/3, explicitly out of scope**, and are NOT counted as Phase 1 failures:

- A live bind-mounted `/bash-history` HISTFILE inside a container (needs the P2 `bash-history` feature).
- `#<epoch>` timestamp lines physically present in a mounted `HISTFILE` (only observable once a container writes to the mount).
- Per-project mount persistence across rebuilds, cross-project store distinctness, weftwise/clauthier/jif/whelm repointing (P2/P3).

All six checks below run on the host, where `/bash-history` is correctly absent, exercising the fallback path that is Phase 1's actual deliverable.

## Section-by-Section Findings

### 1. Deployed file matches committed source, six changes present — CONFIRMED (non-blocking: none)

`diff` of `dot_config/bash/prompt_and_history.sh` against `~/.config/bash/prompt_and_history.sh` reports IDENTICAL.
`chezmoi status` is empty and `chezmoi apply` exits 0 with no pending changes.
Commit `3a72355` touches only that one file (`1 file changed, 22 insertions(+), 9 deletions(-)`).
All six claimed edits are present in the deployed file:

- `HISTSIZE=-1`, `HISTFILESIZE=-1` (lines 2-3)
- `HISTCONTROL=ignoreboth` (line 1)
- `HISTTIMEFORMAT='%F %T '` (line 4)
- HISTFILE guard renamed `/commandhistory` → `/bash-history`, target `/bash-history/.bash_history` (lines 11-13)
- `_FULL_HISTORY` guard: `/bash-history/full_history` when mounted else `$HOME/.full_history` (lines 17-21)
- `_prompt_func` strips the index+`HISTTIMEFORMAT` stamp from `$(history 1)` and appends to `$_FULL_HISTORY`; `PROMPT_COMMAND="history -a; _prompt_func"` (lines 110-119)

### 2. Interactive env vars + ble.sh load — CONFIRMED

Genuine interactive bash under a pty (`script -qec 'bash -i ...'`), inline output:

```
HISTSIZE_HISTFILESIZE=-1 -1
HISTCONTROL=ignoreboth
HISTTIMEFORMAT=[%F %T ]
```

`${BLE_VERSION}` in a real pty-driven interactive session is non-empty: `BLE_VERSION=0.4.0-devel4+8060b7ad`.
(As the proposal warns, a `bash -i -c` one-shot does NOT load ble.sh — `BLE_VERSION` reads EMPTY there. The pty session driving the ble.sh line editor is what proves the load.)

### 3. The `history -a` flush runs each prompt — CONFIRMED (via starship absorption; the nuance checks out)

This is the load-bearing empirical finding.
The literal `$PROMPT_COMMAND` in the deployed shell is `starship_precmd;__zoxide_hook`, NOT `history -a; _prompt_func`.
Because `dot_config/bash/prompt_and_history.sh` runs `eval "$(starship init bash)"` (line 121) BEFORE `source ble.sh` (line 123), starship takes its non-ble branch and, per `starship init bash --print-full-init`:

```
STARSHIP_PROMPT_COMMAND="$PROMPT_COMMAND"   # captures "history -a; _prompt_func"
PROMPT_COMMAND="starship_precmd"
```

and inside `starship_precmd()`:

```
if [[ -n "${STARSHIP_PROMPT_COMMAND-}" ]]; then
    eval "$STARSHIP_PROMPT_COMMAND"
fi
```

Observed live: `STARSHIP_PROMPT_COMMAND=[history -a; _prompt_func]`.
When ble.sh subsequently loads, it drives `$PROMPT_COMMAND` (hence `starship_precmd`) each prompt cycle, which evals the captured flush.
**Demonstrated, not inferred:** across a two-command interactive ble.sh session, `~/.full_history` grew from 12248 to 12250 lines (one archive append per prompt), and the corresponding `history -a` runs in the same eval string. The flush fires every prompt.

> WARN(opus/lace-bash-history/review): The proposal's Phase 1 verification block uses `echo "$PROMPT_COMMAND" | grep -q 'history -a' && echo "flush wired"`.
> Under starship this grep FAILS (the literal `$PROMPT_COMMAND` is `starship_precmd;__zoxide_hook`), a false negative.
> The correct proxy is `echo "$STARSHIP_PROMPT_COMMAND" | grep -q 'history -a'`, or better, an archive-growth observation as done here.
> This is a proposal/test-plan defect, not an implementation defect; see Action Item 1.

### 4. Archive appends a single clean `%Y-%m-%d--%H-%M-%S` stamp, no double-stamp — CONFIRMED

Live archive tail from the interactive session (single stamp, `host PWD command`, command text clean of any index/`%F %T` prefix):

```
2026-09-01--08-38-24 aurora /home/mjr echo BLEVER=${BLE_VERSION:-EMPTY}
```

The `_prompt_func` sed strip was verified directly. Given the `history 1` output under `HISTTIMEFORMAT` `  512  2026-09-01 08:40:15 echo hello-world`:

```
AFTER strip          : [echo hello-world]
ARCHIVE line would be: [2026-09-01--08-38-57 aurora /home/mjr echo hello-world]
without strip (the double-stamp the NOTE warns about):
                       [2026-09-01--08-38-57 aurora /home/mjr   512  2026-09-01 08:40:15 echo hello-world]
```

The double-stamp NOTE in the proposal is correctly discharged: exactly one leading `%Y-%m-%d--%H-%M-%S` stamp survives.

### 5. Host-guard fallback without error — CONFIRMED

`/bash-history` is absent on the host (expected).
In an interactive shell the guards fall back cleanly with no error on stderr:

```
HISTFILE=[/home/mjr/.bash_history]     # guard not taken -> bash default, uncorrupted
_FULL_HISTORY=[/home/mjr/.full_history]
(stderr scan for error|not found: no errors)
```

The `HISTFILE` guard simply does not fire (leaving bash's default), and `_FULL_HISTORY` takes the `$HOME/.full_history` else-branch. Login is not broken.

### 6. No rich tool; blerc + ble.sh fzf/C-r untouched; no leading-slash chezmoiignore; apply clean — CONFIRMED

- `grep -inE 'atuin|stinkpot|mcfly'` on the changed file: no matches. Plain-text-only design honored.
- `dot_blerc` is untouched by this work (last modified by `0c8052a`/`8b9bafe`, both prior); `history_share=1` (line 1), `integration/fzf-*` wiring (lines 14-15), and `C-r isearch/backward` (line 34) are all intact.
- No `.chezmoiignore` leading-slash pattern was added (no offending pattern present); the chezmoi 2.72 regression is not reintroduced.
- `chezmoi apply` exits 0; `chezmoi status` empty.

## Verdict

**Accept.**

All six Phase 1 requirements are implemented correctly and empirically validated on the host, the only environment in scope for a dotfiles-only phase.
The design's plain-text floor is preserved with zero rich-tool leakage, the double-stamp hazard is correctly handled, and the archive flush provably runs each prompt despite starship's `PROMPT_COMMAND` relocation.
No blocking issues.

## Action Items

1. [non-blocking] Fix the proposal's Phase 1 verification block: `echo "$PROMPT_COMMAND" | grep -q 'history -a'` yields a false negative under starship. Replace with `echo "$STARSHIP_PROMPT_COMMAND" | grep -q 'history -a'` (or an archive-growth check), and add a one-line NOTE that starship absorbs `PROMPT_COMMAND` into `STARSHIP_PROMPT_COMMAND` when it initializes before ble.sh.
2. [non-blocking] Consider a NOTE in Part 2 recording the source-order dependency (`starship init` before `source ble.sh`) that makes the flush land in `STARSHIP_PROMPT_COMMAND` rather than a ble.sh PRECMD hook, so a future reorder does not silently change where the flush lives.
3. [non-blocking, P2 carry-forward] The `#<epoch>` HISTFILE timestamp claim and mount persistence remain unverified until Phase 2 supplies a live `/bash-history` mount. Verify then, not now.

## Open Questions for the Author (multiple choice)

The archive currently records `history 1` with `HISTIGNORE` still filtering trivial commands (`ls`, `pwd`, `exit`, ...). Those filtered commands never enter history and so never reach the append-only archive either.

- (A) Intended: the archive inherits `HISTIGNORE` filtering, and that is fine (trivial commands are noise).
- (B) The archive is meant to be a true belt-and-suspenders full log and should capture even `HISTIGNORE`-filtered commands (would require sourcing the command from `BASH_COMMAND`/a DEBUG trap rather than `history 1`).
- (C) Defer: revisit only if a gap is noticed in practice.

Default assumption if unanswered: (A).

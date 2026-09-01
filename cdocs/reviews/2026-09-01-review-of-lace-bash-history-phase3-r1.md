---
review_of: cdocs/proposals/2026-09-01-lace-persistent-bash-history.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T09:51:20-07:00
task_list: bash/history-persistence
type: review
state: done
status: done
tags: [fresh_agent, runtime_validated, migration, devcontainer, isolation, phase3]
---

# Review: Phase 3 - Cross-repo repointing and history-preserving migration

## Summary Assessment

Phase 3 repoints the three `/commandhistory` consumers onto the user-level `bash-history` feature's `/bash-history` per-project mount, preserves weftwise's history via a one-time copy, and verifies the whole cascade end-to-end.
All work was empirically re-verified against the live system: three per-repo branches, four host stores, and the running whelm container.
Every Phase 3 acceptance criterion holds, and every constraint (preserve history, no cross-project merge, no rich tool) is satisfied.

Verdict: **Accept**.

## Section-by-Section Findings

### Branch edits present, grep-clean, unmerged (proposal Phase 3)

All three branches carry the expected commit, are grep-clean for `commandhistory` under `.devcontainer/`, and are NOT merged into their `main` (each `main` HEAD is unrelated to this work).

```
lace/main     bash-history-p3  1856a1c  "repoint bash-history mount to /bash-history"     grep: NO matches   NOT merged   main@a823954
weftwise/main bash-history     915cc97b "drop hardcoded /commandhistory mount"            grep: NO matches   NOT merged   main@aac8a78
clauthier/main bash-history    b5de042  "drop /commandhistory Dockerfile history hack"    grep: NO matches   NOT merged   main@0a37128
```

The residual `HISTFILE` hits on each branch are all inside replacement comments, not live config:
lace Dockerfile:54 and clauthier Dockerfile:58 ("...and sets HISTFILE...") and weftwise devcontainer.json:157 ("...sets HISTFILE. No hardcoded per-repo history mount...").

Diffs match the design exactly:
- **lace** (`1856a1c`): `devcontainer.json` mount target `/commandhistory` -> `/bash-history`; drops the `COMMAND_HISTORY_PATH` build arg; Dockerfile drops the `mkdir ${COMMAND_HISTORY_PATH}` + `touch .bash_history` prep and the `.bashrc` `export HISTFILE=${COMMAND_HISTORY_PATH}/.bash_history` line, replaced by an explanatory comment.
- **weftwise** (`915cc97b`): removes the hardcoded `source=.../dev_records/weft/bash/history,target=/commandhistory,type=bind` mount and its false "restored dotfiles bashrc points HISTFILE here" comment; documents the feature-injected `bash-history/history -> /bash-history` mount instead.
- **clauthier** (`b5de042`): drops the `COMMAND_HISTORY_PATH` arg, the image-state `/commandhistory` dir prep, and the dead `.bashrc` HISTFILE export.

### The extra Dockerfile cleanup is correct, not a regression

Removing `export HISTFILE=/commandhistory/.bash_history` from `.bashrc` is required, not incidental.
Left in place, an interactive `.bashrc` export runs after `containerEnv.HISTFILE=/bash-history/.bash_history` and would shadow it, pinning history back to the now-unmounted `/commandhistory` and breaking persistence.
The live whelm shell confirms the correct value wins post-cleanup: `HISTFILE=/bash-history/.bash_history`.

Nothing else depended on the removed `COMMAND_HISTORY_PATH` ARG: after the diff, `git grep COMMAND_HISTORY_PATH` returns no matches in either Dockerfile.
The `sqlite3`/`libsqlite3-dev` apt packages in lace's Dockerfile (lines 28-29) are a pre-existing general build dependency (present identically on `main`, untouched by `1856a1c`), not a history-tool artifact.

### weftwise history preserved (no clobber, isolated)

The one-time copy is byte-identical and landed ONLY in weftwise's store:

```
source ~/code/dev_records/weft/bash/history/.bash_history         76 lines  md5 1f7d2a113abaa2824cba20031843c39c
weftwise ~/.config/lace/weftwise/mounts/bash-history/history/.bash_history  76 lines  md5 1f7d2a113abaa2824cba20031843c39c
```

Cross-check: the weftwise blob md5 (`1f7d2a1...`) does not appear in any other store - jif is `4eb6cb4...` (42 lines), whelm is `79c5822...` (4 lines), clauthier has no `.bash_history` yet.
No pollution of other projects' stores.

### whelm inherits and survived (persisted state + live container)

The whelm per-project store holds both a pre-rebuild and a post-rebuild marker with epoch timestamps, which is the rebuild-survival proof (this file lives outside the image):

```
#1788281127            -> 2026-09-01 09:45:27 -0700  (pre-rebuild)
echo unique-marker-550-1788281127
#1788281285            -> 2026-09-01 09:48:05 -0700  (post-rebuild)
echo post-rebuild-marker-315-1788281285
```

The whelm container (podman, `Up 3 minutes`, recreated between the two epochs) is live and correctly wired:

```
mount:   /home/mjr/.config/lace/whelm/mounts/bash-history/history -> /bash-history (bind)
shell:   HISTFILE=/bash-history/.bash_history
         HISTSIZE=-1  HISTFILESIZE=-1  HISTTIMEFORMAT=[%F %T ]
```

whelm received all of this with NO per-repo edit (only lace/weftwise/clauthier got branch edits), confirming the user-level feature cascades for free - exactly the Phase 3 jif/whelm opt-in claim.

### Cross-project isolation intact

Four distinct per-projectId stores exist, each with its own content:

```
~/.config/lace/clauthier/mounts/bash-history/history
~/.config/lace/jif/mounts/bash-history/history         (.bash_history 42 lines + full_history)
~/.config/lace/weftwise/mounts/bash-history/history     (76-line preserved blob)
~/.config/lace/whelm/mounts/bash-history/history        (4-line marker log)
```

All four md5s differ. Isolation is inherited from lace's mount resolver, as designed.

### No rich-tool leakage

No `atuin`/`stinkpot`/`mcfly` reference in any Phase 3 branch diff or in the feature source (`devcontainers/features/src/bash-history/{README.md,devcontainer-feature.json,install.sh}`).
The plain-text floor is intact everywhere Phase 3 touched.

### Non-blocking items (confirmed out of scope, do not fail Phase 3)

- **Broken global `lace` shim** (`~/.local/share/pnpm/lace`, dated Feb 2026, stale pnpm path): a user-env artifact, not source, not on any branch. Out of scope.
- **weftwise `.vscode/.history/*` editor artifacts** still naming commandhistory: untracked editor local-history (`git ls-files` returns nothing for `.vscode/.history/`), not committed to `915cc97b`. Out of scope.
- **Regenerated `.lace/*` files**: not present in either the weftwise or clauthier commit `--stat`. Out of scope.

## Verdict

**Accept.**
Phase 3 meets every acceptance criterion and violates no constraint.
The three branches are correct, grep-clean, and unmerged (correctly staged for the overseer to merge, not self-merged).
weftwise's history is preserved byte-for-byte in its own store; whelm survived a real rebuild via persisted host state and is live-wired to `/bash-history`; cross-project isolation is intact across four distinct stores; no rich tool leaked.

## Action Items

None blocking. Optional follow-ups for the overseer:

1. [non-blocking] Merge the three per-repo branches (`lace/bash-history-p3`, `weftwise/bash-history`, `clauthier/bash-history`) into their respective `main`s to land Phase 3.
2. [non-blocking] Repair or remove the stale `~/.local/share/pnpm/lace` global shim in a separate housekeeping pass.
3. [non-blocking] Consider gitignoring `.vscode/.history/` in weftwise so editor local-history stops surfacing dead `/commandhistory` mentions in searches.

## Clarifications for the user (multiple choice)

The proposal frames Phase 3 as the final phase; with all three phases now verified, how should the proposal's frontmatter progress?

- **A.** Mark the proposal `status: implementation_accepted` now (all phases done and verified), and leave merges to the overseer.
- **B.** Hold at current status until the three branches are actually merged into their `main`s, then mark `implementation_accepted`.
- **C.** Something else (specify).

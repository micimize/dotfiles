---
review_of: cdocs/proposals/2026-09-01-lace-persistent-bash-history.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T09:34:01-07:00
task_list: bash/history-persistence
type: review
state: live
status: done
tags: [fresh_agent, runtime_validated, lace, devcontainer, bash, history, persistence, phase2]
---

# Review: Lace Persistent Bash History, Phase 2 (`bash-history` feature)

## Summary Assessment

Phase 2 authors a mount-only lace `bash-history` feature, publishes it to ghcr, and flips `~/.config/lace/user.json` to enable it alongside `blesh`.
The implementation matches the proposal's Phase 2 spec precisely and the load-bearing durable floor holds: the `jif` per-project host store carries the implementer's marker, 21 epoch-timestamp lines, and the `full_history` archive, all living outside any container image and therefore surviving rebuild by construction.
The publish resolves publicly (all four tags return HTTP 200), the `user.json` flip is a clean one-line addition with the backup preserved, and the Phase 3 boundary is intact (no clauthier or weftwise source file touched).
The design is pure plain text with zero binaries installed, so the no-history-tool constraint is satisfied.
**Verdict: Accept.**

## Section-by-Section Findings

### 1. Feature source (`devcontainers/features/src/bash-history/`) — confirmed

All three files present and mirror `blesh`'s layout (`devcontainer-feature.json`, `install.sh`, `README.md`), committed on lace `main` at `a823954`:

```
a823954 feat(bash-history): add mount-only devcontainer feature
devcontainers/features/src/bash-history/README.md
devcontainers/features/src/bash-history/devcontainer-feature.json
devcontainers/features/src/bash-history/install.sh
```

`devcontainer-feature.json` matches the spec exactly:
- `containerEnv.HISTFILE` = `/bash-history/.bash_history`
- `customizations.lace.mounts.history.target` = `/bash-history`
- `options: {}`
- `installsAfter`: `common-utils`, `blesh`, `lace-fundamentals` (all three present)

`install.sh` installs **no binary** (grep for `curl|wget|apt|install |tar |make|cargo|npm` returns only a comment line and the completion echo). It writes exactly the idempotent `/etc/profile.d/bash-history-migrate.sh` snippet with the specified guard, verbatim:

```sh
if [ -d /bash-history ] && [ -d /commandhistory ] && [ ! -e /bash-history/.migrated ]; then
```

The `lace main` working tree has no uncommitted feature files (only unrelated untracked cdocs reports). **Non-blocking, benign:** the sketch's `USER_HOME` var is dropped with an explanatory NOTE in `install.sh` ("this feature writes nothing under the user's home directory"). Confirmed benign: the only file the feature writes is `/etc/profile.d/bash-history-migrate.sh`, which is outside any user home, so no `USER_HOME` is needed and SC2034 (unused var) is correctly avoided.

### 2. Publish resolves publicly — confirmed

Re-fetched the ghcr manifest for `ghcr.io/weftwiseink/devcontainer-features/bash-history` with a fresh pull token:

```
tag 1     -> HTTP 200
tag 1.0   -> HTTP 200
tag 1.0.0 -> HTTP 200
tag latest -> HTTP 200
tags/list: {"name":"weftwiseink/devcontainer-features/bash-history","tags":["1","1.0","1.0.0","latest"]}
```

### 3. `user.json` flip — confirmed

`~/.config/lace/user.json` is valid JSON (parsed clean) and now lists `bash-history:1` immediately after `blesh:1`. Diff against `user.json.bak-bash-history` is a single added line, everything else preserved:

```
4a5
>     "ghcr.io/weftwiseink/devcontainer-features/bash-history:1": {},
```

### 4. Durable persisted floor (load-bearing) — confirmed

`~/.config/lace/jif/mounts/bash-history/history/` on the host:

```
-rw------- 1387  .bash_history
-rw-r--r--  342  full_history
```

- `.bash_history` contains the implementer's marker: `echo unique-marker-999946-16399`.
- `grep -c '^#[0-9]' .bash_history` = **21** epoch-timestamp lines (e.g. `#1788279665`, `#1788279666`), proving `HISTTIMEFORMAT` was active in the real interactive session that wrote the file.
- `full_history` exists (the on-mount archive variant; no host-only `.full_history` here, which is correct: on the mount the archive is named `full_history`) and carries its own `%Y-%m-%d--%H-%M-%S` + hostname + PWD stamps.

This host state lives outside the container image (btrfs subvol under `~/.config`), so it **is** the rebuild-survival evidence. The floor holds.

### 5. Cross-project isolation — confirmed (with a note)

```
/home/mjr/.config/lace/clauthier/mounts/bash-history/history
/home/mjr/.config/lace/jif/mounts/bash-history/history
```

Two distinct per-`projectId` stores exist, demonstrating the resolver's per-repo keying. **Non-blocking note:** the `clauthier` store directory is present but empty (0 bytes, no `.bash_history` yet), so content-level divergence is demonstrated only by `jif`. The isolation *mechanism* (distinct per-projectId directories, auto-created by the mount resolver) is proven; a second populated store would strengthen it but is not required for the Phase 2 floor.

### 6. Runtime re-entry — confirmed directly (live container)

A `jif` container is live under podman with the mount. In a login shell:

```
HISTFILE=[/bash-history/.bash_history]
/bash-history type btrfs ... subvol=/home/mjr/.config   (bind mount present)
/etc/profile.d/bash-history-migrate.sh  present (0644, chowned to remote user ubuntu)
/bash-history/.migrated  absent
```

`HISTFILE` resolves to the feature's `containerEnv` value and `/bash-history` is bind-mounted to the host per-project store. The `.migrated` marker is correctly absent: this container never had a `/commandhistory` dir, so the migration guard never fired (nothing to migrate). The runtime path is confirmed live, not merely corroborated by persistence.

> NOTE(claude-opus-4-8/lace-bash-history/review): `HISTSIZE`/`HISTFILESIZE`/`HISTCONTROL`/`HISTTIMEFORMAT` read empty under `podman exec bash -lc` because those are Phase 1 dotfiles tuning applied on the interactive path, not by this feature. This is out of Phase 2 scope and is not a defect: the 21 epoch lines already persisted in `jif`'s `.bash_history` prove the interactive path applied `HISTTIMEFORMAT` end-to-end. The feature's own responsibilities (HISTFILE + mount) are both confirmed.

### Phase 3 boundary — intact

- `clauthier` (`/home/mjr/code/weft/clauthier/main`): only `.lace/mount-assignments.json` and `.lace/port-assignments.json` are modified. These are lace-generated assignment files, not source, and the task explicitly excludes them. No clauthier source file modified; recent commits are unrelated cdocs marketplace work.
- `weftwise` (`/home/mjr/code/weft/weftwise/main`): clean working tree, no bash-history commit.

No Phase 3 consumer repointing has leaked into Phase 2. Boundary holds.

## Verdict

**Accept.**

Every Phase 2 acceptance criterion is met empirically: the feature source is correct and committed at `a823954`, the ghcr publish resolves on all four tags, the `user.json` flip is clean and reversible, the durable per-project floor holds with marker + epoch timestamps + archive, cross-project keying is demonstrated, and the live container confirms HISTFILE + bind mount. The design is pure plain text with no history tool, satisfying the hard constraint. Phase 3 remains untouched.

## Action Items

1. [non-blocking] When Phase 3 or normal use populates a second project's history, spot-check that `clauthier`'s (or another repo's) store diverges in content from `jif`'s, closing the one gap where isolation is currently shown only at the directory level.
2. [non-blocking] Consider a brief note in the feature README that `HISTSIZE`/`HISTTIMEFORMAT` come from the dotfiles interactive path, so a future reader inspecting a non-interactive `bash -lc` is not misled by empty values.

## Clarifications for the Author (multiple choice, non-blocking)

**A. Empty `clauthier` store.** The `clauthier` per-project store directory exists but is empty. Which is it?
1. Expected: `clauthier` simply has not run an interactive session that recorded history yet.
2. A `clauthier` container was built but its history did not land on the mount (would warrant a look).
3. Leftover auto-created dir from resolver probing; will populate on next use.

**B. Phase 3 sequencing.** Given jif/whelm inherit the mount for free, is Phase 3's remaining scope now only lace's own devcontainer.json target rename plus the weftwise global-blob preservation copy, or is there additional repointing expected?

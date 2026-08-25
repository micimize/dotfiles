---
review_of: cdocs/devlogs/2026-08-25-nushell-unwind.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T18:40:00-05:00
task_list: 2026-08-25-nushell-unwind
type: review
state: live
status: done
tags: [fresh_agent, phase2, blesh, devcontainer, lace, publish_gap, verification_floor, live_state, escalation]
---

# Review: Nushell Unwind, Phase 2 (Lace ble.sh Feature and De-default)

## Summary Assessment

Phase 2 authors a `blesh` devcontainer feature in the lace repo and flips the user-level lace config to drop nushell, add `blesh`, and set bash as `node`'s login shell.
The code deliverable is correct: the feature installs the pinned prebuilt ble.sh release to the exact path the dotfiles bash config sources, `lace-fundamentals` `shell.sh` flips the login shell to bash given `DEFAULT_SHELL=/usr/bin/bash`, and the `user.json` edit is valid JSON with backups in place.
I re-verified the mechanical floor claims independently against the real `lace.local/node:24-bookworm` image (not just the devlog), and they hold.
The verdict is held back from Accept by one structural problem that is the most important finding: the live `user.json` now references `ghcr.io/weftwiseink/devcontainer-features/blesh:1`, which is unpublished until the lace branch merges to `main`, so the floor's literal artifact (a freshly `lace up`'d container) cannot be produced today, and worse, the edit as applied breaks `lace up` globally across every project until publish.
Verdict: **REVISE**, on sequencing and live-state grounds, not on code correctness. The overseer should escalate the publish-before-use ordering to the supervisor.

## Verification Floor: Empirical Results

The floor requires a freshly `lace up`'d container to report `getent passwd node` = `/usr/bin/bash`, drop into bash with ble.sh loaded and the starship lace module intact, with nu installed but not any shell's default.
A full `lace up` is currently impossible (see the publish gap below), so I reproduced the floor's constituent mechanics with a throwaway podman container running the real `install.sh` and `shell.sh` against the actual base image.

Base image is already bash, and no nu is baked (confirms the proposal's base-bake premise is stale for this image):

```text
$ podman run --rm lace.local/node:24-bookworm sh -c 'getent passwd node | cut -d: -f7; command -v nu || echo no-nu'
/bin/bash
no-nu
$ ... cat /etc/shells   ->  includes /bin/bash AND /usr/bin/bash
```

Feature install, login-shell flip, and idempotency, in one real container:

```text
=== BEFORE: node login shell ===          /bin/bash
=== blesh install.sh (root, _REMOTE_USER=node, VERSION=0.4.0-devel3) ===
blesh: fetching prebuilt release ... ble-0.4.0-devel3.tar.xz
blesh: installed prebuilt ble.sh 0.4.0-devel3 to /home/node/.local/share/blesh.
=== ble.sh on disk + owner ===            -rw-r--r-- node node 950686 ... ble.sh  (node:node)
=== shell.sh DEFAULT_SHELL=/usr/bin/bash ===
lace-fundamentals: Default shell set to /usr/bin/bash for node.
=== AFTER: node login shell ===           /usr/bin/bash
=== re-run blesh install (idempotency) ===
blesh: ble.sh already present ... skipping.
=== dist contents ===                     ble.sh contrib keymap lib
```

The extracted tarball is the complete prebuilt distribution (`ble.sh` plus `contrib`/`keymap`/`lib`), the file is owned by `node:node`, and the second install run no-ops.
The release asset itself resolves (`curl -fsSLI` on the pinned URL returns HTTP 200 after the GitHub redirect).
Sourcing `ble.sh` in a non-interactive shell returns rc 1, which is expected ble.sh behavior (it declines to attach outside a live interactive prompt loop); the interactive `BLE_VERSION` load is already evidenced on the host in Phase 1 and by the implementer's in-container tmux-pane check.

Net: every floor mechanic I can exercise without a published feature passes.
The one floor element not demonstrable today is the end-to-end `lace up` merge-and-build path, which is blocked, not failing.

## Section-by-Section Findings

### The `blesh` feature (correct, conventions matched)

The feature is three files (`devcontainer-feature.json`, `install.sh`, `README.md`) matching the `neovim`/`claude-code` layout, id/version/documentationURL conventions, and a `version` option with a sensible default.
The install path `~/.local/share/blesh/ble.sh` is exactly `BLESH_DIR="$HOME/.local/share/blesh"` sourced by the deployed dotfiles, so no dotfiles change is required and the dotfiles `run_once_before_20-install-blesh.sh` correctly short-circuits (empirically: "ble.sh already present ... skipping").
`_REMOTE_USER` ownership is handled: install runs as root, then `chown -R node:node` on the tree, verified `node:node` on disk.
The pinned URL and version are correct and resolvable, and `--strip-components=1` lands the dist directly in `BLESH_DIR`.
The build-from-source fallback is sound (checks `git`/`make`, auto-installs `gawk` via apt/apk, tries the tag then falls back to default branch) and is only reached if the release path fails.
`install.sh` quoting is clean throughout; I found no injection, quoting, or permission bug.
The `installsAfter: common-utils` is a reasonable safety net for leaner bases; the real lace base already carries `curl`/`tar`/`xz`, so the release path is taken.

Non-blocking notes:
- The feature pins ble.sh `0.4.0-devel3` (latest tagged release) while the host runs `0.4.0-devel4+...` (git master, untagged). Both load correctly; the version skew is intentional and harmless but worth a one-line note so a future reader does not treat it as a mismatch.
- `USER_HOME` is derived as `/home/${_REMOTE_USER}` for non-root, which is correct for `node` but assumes a conventional home. Fine for lace's images; a latent assumption only.

### chsh / login shell (correct)

`lace-fundamentals/steps/shell.sh` runs only inside `if [ -n "$DEFAULT_SHELL" ]`, appends `$DEFAULT_SHELL` to `/etc/shells` if absent, then runs `chsh -s "$DEFAULT_SHELL" "$_REMOTE_USER"`.
With `DEFAULT_SHELL=/usr/bin/bash` I confirmed the login shell flips from `/bin/bash` to `/usr/bin/bash` in a real container.
`/usr/bin/bash` is already listed in the image's `/etc/shells`, so `chsh` is accepted without the append path even being exercised.
Setting `defaultShell` to an explicit `/usr/bin/bash` (not clearing it) is the correct lever, since an empty `DEFAULT_SHELL` would skip `chsh` entirely.

### `~/.config/lace/user.json` edit (correct content, correct extra flip)

The live file is valid JSON; the nushell feature entry is removed, `blesh:1` added alongside `neovim:1`/`claude-code:1`, and both `defaultShell` and `containerEnv.SHELL` are `/usr/bin/bash`.
Both backups exist (`user.json.bak-nushell-unwind`, `settings.json.bak-nushell-unwind`); `settings.json` is byte-identical to its backup, consistent with the devlog's note that features/`defaultShell`/`SHELL` live in `user.json`, not `settings.json`.
The diff against the backup matches the devlog exactly.
Flipping `containerEnv.SHELL` beyond the task's literal ask is correct, not scope creep: `shell.sh`'s own fallback path references the `SHELL` env var, and leaving it `/usr/local/bin/nu` would contradict the de-default and mislead any tooling that reads `$SHELL`.

The devlog's correction of the task's target file (`settings.json` named, `user.json` actual) is accurate and well-documented.

### CRITICAL: the publish-before-use gap (blocking, structural)

`user.json` is user-level and merges into every `lace up` on this machine (`user-config-merge.ts:161-171`).
The `blesh:1` OCI reference only publishes to ghcr on push to `main` (`.github/workflows/devcontainer-features-release.yaml`, `paths: devcontainers/features/src/**`), and the feature currently lives on the unmerged `nushell-unwind` branch.
So the reference is unresolvable today, and because it sits in the global `user.json`, this is not merely "Phase 2 cannot be tested": every `lace up` the user runs, in any project, now carries an unresolvable feature ref.
An OCI feature that 404s is a hard failure at devcontainer build, so the applied live-state edit degrades the user's entire container workflow until the branch is published.

I investigated the three options:

- **(a) merge + publish the lace branch first.** Sound. Once `blesh:1` is on ghcr, `user.json` resolves and a real `lace up` can confirm the floor's actual artifact. Merge authority rests with the supervisor per the devlog's containment strategy.
- **(b) reference the feature by local path in `user.json`.** Not available. Lace explicitly rejects local-path user features: `validateFeatureReferences` (`user-config.ts:352-367`, called at `up.ts:348`) errors on any id where `isLocalPath` is true (`./`, `../`, or `/` prefix, `feature-metadata.ts:295-301`), with the message "User config only allows registry features ... Local features must be declared in the project's devcontainer.json." A local ref belongs in a project `devcontainer.json`, not user config, so option (b) as literally posed is a hard validation failure.
- **(c) defer the `user.json` edit until after publish.** The cleanest way to un-break live `lace up` right now. Restore `user.json.bak-nushell-unwind` (re-adds nushell, restores nu defaultShell, nu stays installed), then re-apply the bash edit after the feature publishes. Rollback is clean, exactly as the devlog notes.

Recommendation: pursue (a) as the destination and (c) as the interim so the user's live `lace up` is not left broken in the window before merge.
Concretely: revert `user.json` to the backup now, merge+publish the lace `nushell-unwind` branch, then re-apply the bash `user.json` edit and run one real `lace up` to close the floor.
If early container testing is wanted before merge, the branch-local feature can be exercised via a throwaway project `devcontainer.json` referencing it by local path (option b's mechanism, but at the project layer where it is allowed), which is essentially what the implementer's podman test already approximates.

This gap is a genuine under-consideration in the proposal, not just the implementation.
The proposal says to enable ble.sh "mirroring how the nushell feature was configured", but the eitsupi nushell feature was already published on ghcr, so mirroring it silently assumed a published artifact.
A self-hosted feature must be published before a global `user.json` reference is safe, and the proposal's Phase 2 ordering does not capture that dependency.

### Container verification quality (adequate for mechanics, short of the floor's literal artifact)

The implementer's podman evidence, which I independently reproduced, is strong for the feature and shell mechanics and is the best achievable while the feature is unpublished.
It does not, and cannot yet, exercise the `lace up` merge path (`user.json` -> generated `.lace/devcontainer.json` -> build), which the implementer verified by code-reading `user-config-merge.ts` plus per-component tests.
Given the floor is explicitly "a freshly `lace up`'d container", I do not treat the podman test as sufficient to admit a `confirmed` for the full floor; it confirms the parts, and the whole remains gated on publish.
This is the second reason the verdict is Revise rather than Accept: the floor's end-to-end artifact is deferred, not demonstrated.

The implementer's report that the base image does not bake nu is correct (verified: `getent passwd node` = `/bin/bash`, no `nu` binary).
This does soften the proposal's base-bake edge case for this image: the nu default came from the eitsupi feature, not the base image.
The explicit-bash `defaultShell` fix remains correct and harmless regardless, so nothing in the deliverable needs to change; only the proposal's edge-case rationale is now known to rest on a stale premise for the current image.

### No collateral breakage (confirmed)

The lace branch diff is exactly three files, all under `devcontainers/features/src/blesh/` (README, json, sh); no TypeScript is touched.
`pnpm -w build` / `pnpm -w test` are therefore unaffected, and the nu-hardcoded TS fixtures are correctly left for Phase 4.
I confirmed the diff scope directly rather than running the full suite, since an additive feature directory cannot alter TS compilation or test behavior.

## Verdict

**REVISE.**
The Phase 2 code deliverable (the `blesh` feature and the `user.json`/shell flip) is correct, convention-conformant, and passes every floor mechanic I can exercise against the real base image.
It is held at Revise by the publish-before-use gap: the live `user.json` references an unpublished feature, which both blocks the floor's literal `lace up` verification and breaks `lace up` globally until the lace branch is published.
The required changes are sequencing and live-state actions plus one real `lace up` to close the floor, not fixes to the feature code.

## Action Items

1. [blocking] Resolve the publish-before-use ordering. Preferred: revert `~/.config/lace/user.json` to `user.json.bak-nushell-unwind` now to un-break live `lace up`, merge+publish the lace `nushell-unwind` branch, then re-apply the bash `user.json` edit.
2. [blocking] After publish, run one real `lace up` and confirm the floor's actual artifact: `getent passwd node` = `/usr/bin/bash`, ble.sh live in an interactive container shell (`BLE_VERSION` set), the `LACE_PROJECT_NAME` starship module rendered, and `grep -c nushell .lace/devcontainer.json` = 0.
3. [non-blocking] Note in the devlog (or proposal via a NOTE callout) that the base `lace.local/node:24-bookworm` image does not bake nu, so the base-bake edge case is stale for this image while the explicit-bash `defaultShell` fix stays correct.
4. [non-blocking] Record the intentional host/container ble.sh version skew (`devel4` host vs pinned `devel3` container) so it is not mistaken for a mismatch.

## Escalation Recommendation

Escalate the publish-before-use gap to the supervisor.
Two reasons: merge/publish authority for the lace branch is the supervisor's per the devlog's containment strategy, and the gap reflects an under-specified dependency in the accepted proposal (a self-hosted feature must be published before a global `user.json` reference resolves, unlike the already-published eitsupi feature the plan mirrored).
The supervisor decision is a clean multiple choice:

- Option A: Merge+publish the lace branch immediately, then re-apply `user.json` and close the floor with a real `lace up`. Fastest path to a `confirmed` floor; accepts a brief window where `user.json` is reverted.
- Option B: Revert `user.json` to the backup and defer the edit until the branch is published on its own schedule, keeping nu as the interim default (clean rollback, no live breakage, floor closed later).
- Option C: Accept Phase 2's code as-is now and fold both the publish and the closing `lace up` into the Phase 3 dispatch, since Phase 3 already rebuilds downstream containers. Carries the global `lace up` breakage until then, so only viable if the user is not running `lace up` in the interim.

Reviewer's recommendation: Option A if merge can happen promptly, else Option B; avoid Option C because it leaves live `lace up` broken.

---
review_of: cdocs/proposals/2026-08-25-nushell-unwind.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T13:10:00-05:00
task_list: nushell-unwind/phase-4-cleanup
type: review
state: live
status: done
tags: [fresh_agent, phase4, cleanup, lace, devcontainer, test_plan, empirical_verification]
---

# Review: Nushell Unwind Phase 4 (Lace-Side Cleanup)

## Summary Assessment

Phase 4 is the lace-repo cleanup pass of the nushell-unwind proposal: drop the nushell lock pin, flip the `lace-fundamentals` default-shell examples and `installsAfter` to bash, delete the sprack nu hook, fix the neovim comment, and update TypeScript test fixtures.
The work is on branch `nushell-unwind-cleanup` (four commits `792161b`, `14eefcb`, `0dccf77`, `349014e` atop `7eb7394`), an eight-file, +9/-32 diff.
Every item verified cleanly: the lock and feature JSON are valid and minimally changed, the sprack bash hook is intact while the nu heredoc is gone, `sh -n`/`bash -n` pass, the neovim change is comment-only, and the implementer's discrimination between "nu as default-shell value" (changed) and "nu as an arbitrary OCI feature reference" (correctly left) is sound throughout.
The full suite shows `1081 passed`, and the only failures are two in `port-allocator.test.ts` — a file this branch does not touch — caused by host port `22430` being genuinely occupied (`pasta.avx2`), i.e. the documented environmental flake, not a regression.
**Verdict: ACCEPT.**

## Section-by-Section Findings

### 1. `devcontainer-lock.json` — clean (non-blocking observations)

The diff removes exactly the `ghcr.io/eitsupi/devcontainer-features/nushell:0` block (5 lines) and nothing else.
The remaining four pins are byte-identical and intact: `anthropics/claude-code:1`, `devcontainers-extra/neovim-homebrew:1`, `devcontainers/git:1`, `devcontainers/sshd:1`.
`python3 -m json.tool` confirms valid JSON.

The implementer's claim — the lock tracks only external registry features, so first-party lace features (including `blesh`) are not locked — **is consistent with the file's actual contents.**
All four surviving entries are third-party/upstream `ghcr.io` features; no first-party `weftwiseink` feature appears in the lock at all (not `lace-fundamentals`, not `sprack`, not `neovim`, not `blesh`).
Local features referenced by relative path (e.g. `./features/sprack` in `.devcontainer/devcontainer.json`) are not OCI-resolved and therefore never receive a lock entry, which is standard devcontainer-CLI behavior.
So leaving `blesh` out of the lock is correct, not an omission.

Two non-blocking observations, neither actionable for this branch:
- The lock's contents (`claude-code`, `neovim-homebrew`, `sshd`) do not one-to-one match this repo's own `.devcontainer/devcontainer.json` feature list (`lace-fundamentals`, `git`, `rust`, `./features/sprack`); only `git` overlaps. The lock is evidently maintained against a broader/other resolved configuration, a pre-existing condition orthogonal to this migration.
- The commit message says "regenerate," but the diff is a pure 5-line deletion with zero resolver churn on the other pins, which reads as a hand-edit rather than an actual `devcontainer` regeneration. The result is functionally identical and satisfies the Phase 4 acceptance criterion ("regenerated lock omits the nushell feature"), so this is cosmetic. The file retains its pre-existing no-trailing-newline style (not introduced by this change).

### 2. `lace-fundamentals` — default-shell flip and `installsAfter` removal — clean

`devcontainer-feature.json` and `README.md` both flip the `defaultShell` example from `/usr/bin/nu` to `/usr/bin/bash`, and the `installsAfter: ["ghcr.io/eitsupi/devcontainer-features/nushell"]` array is removed entirely.
JSON validates.

The implementer's claim that `blesh` does **not** need to be added to `installsAfter` is **sound**, confirmed against the actual step script:
- `steps/shell.sh` only runs `chsh -s "$DEFAULT_SHELL" "$_REMOTE_USER"` inside an `if [ -x "$DEFAULT_SHELL" ]` guard. Its sole build-time dependency is that the target shell binary exist.
- With `defaultShell` now `/usr/bin/bash`, that binary is baked into the `node:24-bookworm` base image and is always present — no feature must install first. The original `installsAfter: nushell` entry existed precisely because `chsh -s /usr/local/bin/nu` needed the eitsupi feature to install `nu` first; that dependency evaporates with the bash flip, so the removal is correct.
- `ble.sh` is installed by the separate `blesh` feature to `~/.local/share/blesh` and is **sourced at interactive time via dotfiles** (`.bashrc`/`.blerc`), not at build time. `chsh` changes only the passwd shell field and sources nothing, so there is no build-time ordering relationship between `blesh` and `lace-fundamentals` in either direction. The `blesh` feature's own `installsAfter` is `common-utils`, independent of `lace-fundamentals`.

Ordering reasoning is therefore correct and complete; nothing to add.

### 3. sprack — nu heredoc removed, bash parity intact — clean

`sprack/install.sh` deletes the `# Nushell integration` block (the `mkdir -p /etc/nushell` + `/etc/nushell/sprack-hooks.nu` heredoc through `NU_EOF`).
The bash `/etc/profile.d/sprack-metadata.sh` PROMPT_COMMAND hook and the POSIX helper logic (jq install, hook-bridge copy, metadata-writer gating) are untouched.
`sh -n` and `bash -n` both pass clean.
`git grep` for `sprack-hooks.nu` and `/etc/nushell` across non-doc source returns **no** remaining references — nothing else in lace source points at the deleted path (only historical `cdocs/devlogs/2026-03-26-sprack-metadata-writer.md` mentions it, which is correct as a record).

### 4. neovim `install.sh` — comment-only, behavior unchanged — clean

The entire diff for this file is a single comment line: "su - may start nushell which won't load .cargo/env" → "a non-login/non-interactive shell won't load .cargo/env".
The `. /usr/local/cargo/env 2>/dev/null || true` sourcing line and all surrounding logic are unchanged.
The new wording is in fact more accurate. Harmless.

### 5. TypeScript test fixtures — correct discrimination, suite green

The three fixture files changed (`fundamentals-scenarios.test.ts`, `user-config-merge.test.ts:218`, `user-config.test.ts`) flip `defaultShell` from `/usr/bin/nu` to `/usr/bin/bash` in exactly the tests that **assert on the default-shell value** (`expect(...defaultShell).toBe(...)`). Correct.

Fixtures the implementer **left** as nu were each inspected and are genuinely nu-as-arbitrary-example, asserting nothing about the default shell:
- `up.integration.test.ts` (~1681–1875): `nushell` is the mock third-party OCI feature that lacks the `dev.containers.metadata` annotation, used to exercise the blob-fallback path. It is deliberately chosen because the real eitsupi feature historically lacked that annotation. No shell assertion. Correctly left.
- `oci-blob-fallback.test.ts` and `oci-blob-fallback.ts` doc-comment: the eitsupi nushell ref is a representative GHCR ref-parsing example for `parseFeatureOciRef`. No shell semantics. Correctly left.
- `user-config-merge.test.ts:252,264`: the "user features go into prebuildFeatures when project has them" test uses the nushell feature ref as an arbitrary user-declared feature that should merge into prebuild. It asserts on merge behavior, not on `defaultShell` (contrast line 218 in the same file, which does assert on `defaultShell` and *was* correctly changed). Correctly left.
- `feature-metadata.test.ts`: same pattern — nushell as an OCI metadata fixture. Correctly left.

**Test run evidence** (`pnpm --filter lace test`):
```
Test Files  1 failed | 42 passed | 1 skipped (44)
     Tests  2 failed | 1081 passed | 11 skipped (1094)
```
Both failures are in `src/lib/__tests__/port-allocator.test.ts`:
- "reuses existing assignment if port is still available" — `expected 22426 to be 22430`.
- "reassigns when existing port is in use" — timeout, with `Error: listen EADDRINUSE: address already in use ::1:22430`.

`git diff --name-only main...HEAD` confirms this branch does **not** touch `port-allocator.test.ts`.
`ss -tlnp` confirms port `22430` is genuinely held on this host by `pasta.avx2` (container networking), which is within lace's `22425+` allocation range — so both failures are the same environmental root cause (a real listener on 22430), not a code defect. The first failure is a cascade of the second: with 22430 occupied, the allocator legitimately reassigns to 22426.

Re-running the three branch-changed test files in isolation: **83 passed (3 files)**.
Re-running the flagged nu-fixture files in isolation (`up.integration.test.ts`, `oci-blob-fallback.test.ts`, `feature-metadata.test.ts`): **172 passed (3 files)**.
All nushell-related fixture tests pass.

### 6. Residuals — all intentional

`git grep -nE "nushell|/usr/(local/)?bin/nu\b|eitsupi"` over non-`cdocs` source returns only test fixtures and doc-comments using nushell as an arbitrary OCI-feature example (items enumerated in §5); no load-bearing default remains.
All `cdocs/` hits are historical proposals, devlogs, and reviews — records, correctly untouched.
No committed lace source sets nu as a shell default after this branch.

## Verdict

**ACCEPT.**

Phase 4's lace-side scope is complete and correct.
Every proposal Phase 4 item is present, the JSON artifacts are valid and minimally changed, shell scripts pass syntax checks with bash parity preserved, the fixture discrimination between default-shell-value and arbitrary-OCI-reference is exactly right, and the test suite is green apart from a pre-existing environmental port flake in an untouched file.
No blocking issues; the two §1 observations are informational and require no change on this branch.

Note: this review covers the lace-side Phase 4 items only. The dotfiles README item was explicitly out of scope, and downstream propagation of the sprack edit to whelm's vendored copy is Phase 3 work, not evaluated here.

## Action Items

None blocking.

Optional (non-blocking, may be ignored):
1. [non-blocking] If a truly regenerated lock is desired for provenance, run the `devcontainer` resolver rather than hand-deleting the block — the end state is already correct, so this is discretionary.
2. [non-blocking] Separately from this migration, reconcile why `devcontainer-lock.json` lists features (`claude-code`, `neovim-homebrew`, `sshd`) that do not appear in this repo's own `.devcontainer/devcontainer.json` feature list. Pre-existing and out of scope here.

## Clarifications for the Overseer

Both are confirmations rather than blockers:

1. The `port-allocator.test.ts` failures are environmental (host port 22430 held by `pasta.avx2`) and unrelated to this branch. Confirm you are satisfied treating them as the documented flake — which option?
   - (a) Accept as-is; the flake is external and the branch does not touch the file (recommended).
   - (b) Re-run in a clean environment / after freeing 22430 before merge.
2. Lock "regeneration" was effectively a hand-edit (§1). Confirm which you prefer:
   - (a) Accept the hand-edit; end state is byte-correct (recommended).
   - (b) Require an actual resolver regeneration for provenance.

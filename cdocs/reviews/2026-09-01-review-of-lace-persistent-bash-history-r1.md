---
review_of: cdocs/proposals/2026-09-01-lace-persistent-bash-history.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-09-01T14:30:00-07:00
task_list: bash/history-persistence
type: review
state: live
status: done
tags: [fresh_agent, architecture, lace, devcontainer, source_verified, test_plan]
---

# Review: Persistent, Per-Project Bash History for Lace Devcontainers

## Summary Assessment

The proposal makes per-project bash-history persistence uniform by declaring the existing `/commandhistory` mount from a new user-level lace `bash-history` feature, tuning the dotfiles, and offering a rich tool (atuin) as an explicitly opt-in tier gated OFF by default.
It is a strong, well-grounded downstream design: all five required deliverables are present and concrete, the plain-text floor is correctly framed as the complete recommendation with atuin/stinkpot as clearly-marked optional richness, and the honest-risk treatment meets the critical-analysis convention.
Most importantly, every load-bearing lace `file:line` claim I spot-checked against current source is accurate: the mount auto-injection, feature-shortId namespacing, `resolveSource` default path, per-repo `projectId`, the postCreate ordering caveat, and the sprack profile.d precedent all hold as stated.
Verdict: **Accept (accept-with-nits)**. Findings are all non-blocking; the notable ones are an internal inconsistency in the `install.sh` sketch's default (`atuin`, not `none`) that contradicts the OFF-by-default invariant, and a broken command in an otherwise sound verification block.

## Source Verification

I independently verified the proposal's load-bearing claims against current code rather than trusting them.

Lace (`/home/mjr/code/weft/lace/main`), all confirmed accurate:
- `autoInjectMountTemplates` (`template-resolver.ts:521-549`) appends `${lace.mount(<label>)}` for every declared label not already referenced; `buildMountDeclarationsMap:290-313` keys feature mounts as `<shortId>/<mountName>`, so a `bash-history` feature declaring mount `history` yields exactly `${lace.mount(bash-history/history)}`. `extractProjectMountDeclarations:88-110` prefixes project mounts `project/`.
- `mount-resolver.ts` `resolveSource:239-325` defaults to `~/.config/lace/<projectId>/mounts/<namespace>/<labelPart>` (`:304-312`), reached because the declaration carries no `sourceMustBe`; the settings override (`:282-301`) hard-errors if the override source does not exist on disk, matching the proposal's "override must exist" caveat.
- `projectId` = bare-repo basename: `repo-clones.ts:51-55` -> `project-name.ts:13-28`, where `worktree` and `bare-root` both `return basename(classification.bareRepoRoot)`. Per-repo, shared across worktrees: confirmed, so the per-repo-not-per-worktree "confirm-not-bug" framing is factually correct.
- user.json feature enablement (`user-config-merge.ts:156-173`, `mergeUserFeatures`) and settings.json mount-source override (`settings.ts:22-24,136-137`) are as described.
- postCreate ordering caveat is real: `up.ts:868-896` injects `lace-fundamentals-init` as an object-form entry (`{ "lace-fundamentals": initCmd, ...postCreate }`), and `git-identity.sh:35-37` runs `chezmoi apply`. The devcontainer spec runs object-form postCreate entries in parallel, so a feature's postCreate has no guaranteed ordering against it. The proposal's justification for profile.d over postCreate is sound.
- The sprack profile.d precedent (`sprack/install.sh`) writes `/etc/profile.d/sprack-metadata.sh` guarded on `BASH_VERSION`, exactly the pattern the proposal reuses. The `blesh` feature (`installsAfter common-utils`, pinned prebuilt release + source fallback, `_REMOTE_USER`/`USER_HOME`) matches the described `install.sh` template, and `neovim installsAfter rust` confirms the cargo-provenance claim (base node image has no cargo unless neovim pulls rust in).

Downstream, all confirmed:
- weftwise `.devcontainer/devcontainer.json:156-157` hardcodes `source=${localEnv:HOME}/code/dev_records/weft/bash/history,target=/commandhistory,type=bind` with the comment "The restored dotfiles bashrc points HISTFILE here."
- clauthier `Dockerfile:6,40-42,60` sets `COMMAND_HISTORY_PATH`/`HISTFILE`/`PROMPT_COMMAND` and declares no host mount; the dotfiles already set `HISTFILE=/commandhistory/.bash_history` (`prompt_and_history.sh:10-12`), making the Dockerfile line redundant as claimed.
- jif and whelm declare no bash-history mount (verified: no match). Live `user.json` lists neovim/blesh/claude-code; live `settings.json` shows feature-namespaced labels (`claude-code/config`, `neovim/plugins`, `lace-fundamentals/dotfiles`), confirming the namespacing claim. `dot_blerc:1` (`history_share=1`) and `dot_blerc:34` (`ble-bind ... C-r isearch/backward`) are as cited.

## Section-by-Section Findings

### BLUF and Summary
No blocking issues.
The BLUF honestly foregrounds the plain-text floor as the complete recommendation and weighs atuin against the user's "a bit heavy" skepticism rather than defaulting to it.
Non-blocking: the BLUF runs five dense lines; it is accurate but at the edge of the "essential takeaway, not every detail" guidance. Acceptable given the proposal's cross-repo scope.

### Background
Accurate and well-sourced.
Non-blocking: the claim that weftwise's mount comment is "false" leans on the phase-3 review, but the dotfiles *do* point `HISTFILE` at `/commandhistory` when it exists, so the comment is false only because weftwise's container does not apply these dotfiles (no lace-fundamentals/chezmoi in that path). Making that reasoning explicit would strengthen the claim; as written it reads as if the dotfiles never point there, which is not the general case.

### Proposed Solution (Layers 1-3)
The layering is correct and the default/opt-in split is honored consistently.
Non-blocking (Layer 2): adding an explicit `history -a` to `PROMPT_COMMAND` while ble.sh's `history_share` is active, combined with `HISTCONTROL=...:erasedups`, should be verified not to double-write or fight ble.sh's own history flushing. ble.sh manages history internally; the interaction is benign in practice but is asserted, not verified.
Non-blocking (Layer 3): the profile.d ordering claim deserves one caveat. `atuin init bash` in `/etc/profile.d/atuin.sh` runs when `/etc/profile` is sourced, which for a login shell is *before* `~/.bashrc` sources ble.sh (last line of the interactive rc). atuin's ble.sh integration must therefore defer its C-r binding until ble.sh loads. The proposal states "atuin natively supports ble.sh so eval wires it correctly," which is probably true but is exactly the kind of load-order assumption that bit nushell-unwind. The Test Plan's live-pane C-r check is the correct mitigation; the narrative just overstates confidence.

### Per-Project Isolation Mechanism
Correct, with an accurate mermaid diagram and a well-reasoned per-repo-not-per-worktree decision.
The `WARN` that two simultaneous worktrees of one repo share a single atuin sqlite db is the right corollary to surface, and it connects cleanly to the SQLite risk section.

### Lace-Side Features
The `devcontainer-feature.json` and `install.sh` sketches mirror `blesh`/`sprack` faithfully.
Non-blocking but worth correcting before the sketch is copied: `install.sh` line `HISTORY_TOOL="${HISTORYTOOL:-atuin}"` (and `ATUIN_VERSION="${ATUINVERSION:-18.x.y}"`) defaults to installing atuin when the env var is unset, which contradicts the manifest's `"default": "none"` and the load-bearing OFF-by-default invariant. In the feature harness the declared default is always passed so `none` wins in practice, but a copy of this sketch run outside the harness silently installs a rich tool. The sketch's fallback should be `none`.
Non-blocking: `atuinVersion` default `"18.x.y"` is an unresolvable placeholder; it must become a concrete pinned tag before implementation, per the "feature refs must resolve / publish-before-use" lesson.
Non-blocking (trivial): `containerEnv` exports `ATUIN_DB_PATH`/`ATUIN_CONFIG_DIR` into every container even when `historyTool: none` and atuin is absent. Harmless (unused vars), consistent with the self-sufficiency rationale given for `HISTFILE`, but unremarked for the atuin vars.

### atuin vs stinkpot Head-to-Head
Fair and well-structured.
The call (atuin if-and-only-if opting in, on the load-bearing axis of documented `ATUIN_DB_PATH`/`ATUIN_CONFIG_DIR` redirection) is justified, and stinkpot's genuine minimalism appeal is neither dismissed nor oversold. mcfly do-not-adopt is backed by the maintainer-needed Gentoo signal. The decision-point NOTE correctly frames "opt in at all" as the primary human decision and keeps Phase 4 gated behind explicit supervisor opt-in.

### Edge Cases / Risks
Meets the critical-analysis convention: SQLite-WAL-on-mount (with the NFS caveat and the intra-repo worktree contention), C-r ownership, existing-history migration (correctly declining to auto-merge weftwise's global blob), chezmoi-never-manages-the-db, and cargo-absent-so-prebuilt-only are all treated honestly. No hand-waved risk of note.

### Test Plan / Verification Methodology
Concrete and per-phase, with the correct insistence on real interactive panes over `bash -c`.
Non-blocking: the Phase 2 host-store check `ls ~/.config/lace/$(basename "$PWD-projectid")/mounts/bash-history/history` is a broken command; `basename "$PWD-projectid"` produces garbage, not a projectId. In a section that explicitly says "Run these directly; do not rely on inspection," a non-working command undercuts the intent. The adjacent glob form (`ls ~/.config/lace/*/mounts/bash-history/history`) is correct; drop or fix the broken line.

### Implementation Phases
Phasing is sound: the lace feature (P2) cascades before per-repo downstream edits (P3), P4 is explicitly optional and gated, and each phase carries a checkable acceptance floor spanning dotfiles + lace + downstream. Matches the nushell-unwind precedent it cites.

## Conventions Compliance

Clean. No em-dashes and no emojis (scanned). Present-tense/history-agnostic framing with prior approaches confined to `NOTE`/Background. Callouts carry `author/workstream` attribution (`opus/lace-bash-history`). External references (atuin, stinkpot, ble.sh, mcfly Gentoo) use direct HTTP links; internal references use relative cdocs links. Mermaid, not ASCII. Semicolon usage is concentrated in code blocks, not prose.

## Verdict

**Accept (accept-with-nits).**
The design is technically correct where I could verify it, the required deliverables are all present and concrete, the plain-text-default / atuin-opt-in framing is honored without drift, and the risks are treated honestly.
No blocking issues. The nits below should be resolved during implementation but do not gate acceptance.

## Action Items

1. [non-blocking] Fix the `install.sh` sketch default: `HISTORY_TOOL="${HISTORYTOOL:-none}"` (not `atuin`), so the sketch matches the manifest `default: "none"` and the OFF-by-default invariant even outside the feature harness.
2. [non-blocking] Replace the `atuinVersion` placeholder `"18.x.y"` with a concrete, resolvable pinned atuin release tag before publishing the feature.
3. [non-blocking] Fix the broken Phase 2 verification command (`basename "$PWD-projectid"`); use the working glob form already present two lines below.
4. [non-blocking] Add a caveat to the Layer 3 C-r narrative that `atuin init bash` in profile.d runs before ble.sh is sourced from `~/.bashrc`, so the binding relies on atuin deferring to ble.sh's load; the live-pane C-r test is the verification of record.
5. [non-blocking] Make the weftwise "false comment" reasoning explicit: the comment is false because weftwise's container does not apply the dotfiles, not because the dotfiles never point `HISTFILE` at `/commandhistory`.
6. [non-blocking] In Phase 1/Layer 2, verify empirically that the manual `history -a` plus `erasedups` does not conflict with or double-write against ble.sh's `history_share` flushing.
7. [non-blocking] Optionally note that `containerEnv` exports the `ATUIN_*` vars unconditionally (harmless when `historyTool: none`), matching the `HISTFILE` self-sufficiency rationale.

## Clarifications for the Supervisor

These are decision points the proposal surfaces or leaves implicit; the reviewer recommends resolving them before or during implementation.

1. Rich-tool opt-in (the proposal's primary human decision):
   - (a) Stop at the plain-text floor (Phases 1-3 only). Recommended by the proposal and by this review, given the "a bit heavy" stance and that the floor already satisfies the requirement.
   - (b) Opt into atuin (Phase 4), accepting the binary, C-r rebinding, and SQLite-on-mount overhead for exit-code/duration/cwd-aware search.
   - (c) Opt into stinkpot for minimal footprint, accepting the prerequisite of first verifying its store-path redirection and exit-code capture.

2. Interactive-shell reach of profile.d (verification, not design): `/etc/profile.d/*` is sourced for login shells; confirm the container's interactive panes (tmux/exec) are login shells or otherwise source profile.d, since sprack's working precedent is the evidence the proposal leans on. Options:
   - (a) Trust the sprack precedent and verify only via the live C-r/atuin test.
   - (b) Add an explicit "profile.d is reached by interactive panes" assertion to the Phase 4 acceptance floor.

3. `~/.full_history` fate when staying at the floor (no rich tool): the proposal redirects it into the mount and keeps it as a poor-man's rich log. Confirm:
   - (a) Keep it on the mount as the floor's structured log (proposal default).
   - (b) Retire it even without atuin, treating tuned `HISTFILE` + timestamps as sufficient.

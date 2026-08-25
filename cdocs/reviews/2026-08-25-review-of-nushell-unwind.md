---
review_of: cdocs/proposals/2026-08-25-nushell-unwind.md
first_authored:
  by: "@claude-opus-4-8"
  at: 2026-08-25T14:30:00-05:00
task_list: shell/nushell-unwind
type: review
state: live
status: done
tags: [fresh_agent, migration, cross_repo, shell, safety, verification]
---

# Review: Nushell Unwind: Restore bash + ble.sh Across Dotfiles, Lace, and Downstream Repos

## Summary Assessment

The proposal reverses a nushell-as-default trial and restores bash + ble.sh across the dotfiles host, the `lace` devcontainer framework, and four consuming repos, in four ordered phases.
It is unusually well-researched: I spot-checked nearly every load-bearing claim (commit hashes, file paths, line numbers, mechanisms) against the actual repos and the great majority are accurate.
The core architectural insight, that nu reaches every container through one user-settings declaration and reaches the host through one tmux line plus a manual `chsh`, holds up, and the Phase 2-before-Phase 3 cascade is genuinely sound.
The most important findings are non-blocking: a factually wrong line reference in Phase 1, a real but inert completeness gap (whelm vendors its own copy of the sprack nu hook, contradicting the "no nu code in any consumer" claim), and a missing host rollback/safety step around the live `chsh`.

Verdict: **Accept with nits.** No blocking issues. The proposal is implementation-ready once the nits below are cleaned up, none of which change the design.

## Verification Performed

Claims verified accurate against the repos:

- Commit `742fd97` deletes `dot_bashrc`, `dot_blerc`, `dot_tmux.conf`; commit `a61ba74` moves `bash/*` into `archive/legacy/` and rewrites `dot_bashrc` to source from there. Both dated 2026-02-05, `a61ba74` is the earlier ancestor. Restoring from `742fd97^` is valid.
- `archive/legacy/` contents match the enumerated list exactly, including `bash/starship.toml` and the ble.sh installer.
- `dot_config/tmux/tmux.conf:9-11` hardcodes `set -g default-shell ~/.cargo/bin/nu` and `default-command`; `archive/legacy/tmux.conf:161` uses `set -g default-shell $SHELL`.
- `dot_config/starship.toml` `[custom.container]` uses `LACE_PROJECT_NAME` and spawns `bash --noprofile --norc`: shell-agnostic as claimed.
- The two nu host scripts are `lace/main/bin/{lace-inspect,lace-paste-image}`, both `#!/usr/bin/env nu`. `bin/lace-into` `build_exec_cmd` ends in `/bin/bash -l` (line 457).
- `lace-fundamentals/steps/shell.sh` runs `chsh` only inside `if [ -n "$DEFAULT_SHELL" ]`: the empty-clears-to-no-chsh behavior the base-image edge case depends on is real.
- `sprack/install.sh` emits a bash profile.d hook and a separate `/etc/nushell/sprack-hooks.nu` heredoc.
- `lace-fundamentals/devcontainer-feature.json:12` and `README.md:32` use `/usr/bin/nu` as the example; `neovim/install.sh:51` has the "su - may start nushell" comment; `devcontainer-lock.json:23` pins the eitsupi nushell feature; TS fixtures under `packages/lace/src/**/__tests__/` hardcode nu; `user-config-merge.ts:199` passes `defaultShell` through.
- jif `.devcontainer/devcontainer.json:73,76,112` hand-authors the nushell feature, `defaultShell`, and `SHELL` env; weftwise `:120-124` mounts `nushell-config` and `:160` removed the bash-history mount ("primary shell"); clauthier has no nushell in its devcontainer and bakes bash history in its Dockerfile.
- whelm's `.devcontainer/devcontainer.json:19-21` corroborates that `lace.local/node:24-bookworm` bakes the node login shell to nushell and that node bootstrap "chokes on `&&`". This is the independent evidence backing the base-image bake claim.
- `keybindings.nu` states it "Mirrors the ble.sh keybindings from the archived dot_blerc"; `run_once_before_30-install-carapace.sh` installs carapace "for nushell completions". Both support the "gains ported / keep carapace" reasoning.

## Section-by-Section Findings

### Phase 1: shell-init line reference is wrong (non-blocking)

The Phase 1 bullet cites "the `starship init nu` / `zoxide init nushell` generation (`dot_config/nushell/env.nu:51` and the `scripts/generated/*.nu` path)".
`env.nu:51` is actually `$env.STARSHIP_SHELL = "nu"`, not the init generation.
The real generation is `env.nu:78` (`starship init nu | save -f $cache`) and `env.nu:92` (`zoxide init nushell | save -f $cache`), with the generated dir set up at `env.nu:63-67` and sourced by `config.nu:44,47`.
The `scripts/generated/*.nu` path reference is correct; only the `:51` line number is wrong.
Also, since the constraint keeps the nu config tree intact for the retained host scripts, Phase 1 is not really "replacing" the nu init: it is adding bash init to the restored bash config while the nu generation stays.
Reword to "add `starship init bash` / `zoxide init bash` to the restored bash config" and fix the line refs to `:78`/`:92`.

### Downstream / Phase 4: whelm vendors the sprack nu hook (non-blocking, completeness)

The Background "Downstream consumers" section asserts "No nu code, scripts, or `package.json` entries exist in any consumer."
This is contradicted by whelm: `/var/home/mjr/code/apps/whelm/.devcontainer/features/sprack/install.sh:57-70` is a vendored copy of the sprack feature containing the identical `/etc/nushell/sprack-hooks.nu` nu heredoc.
It is inert (nu is de-defaulted and the hook only fires if a nu config sources it), so this is not a shell-default break.
But it means Phase 4's edit to lace's `sprack/install.sh` will not propagate to whelm's vendored copy, and the blanket "no nu code in any consumer" claim is inaccurate.
Add a NOTE acknowledging whelm's vendored sprack copy and, if pursuing full cleanup, list dropping its nu heredoc as an optional Phase 4 item (or explicitly scope it out as inert).

### Edge Cases: `devcontainer-feature.json:19` is not a defaultShell example (non-blocking)

The "stray nu references" edge case lists `lace-fundamentals/devcontainer-feature.json:12,19` as using `/usr/bin/nu` "as the `defaultShell` example".
Line 12 is the defaultShell example; line 19 is an `installsAfter` reference to `ghcr.io/eitsupi/devcontainer-features/nushell`, a different kind of dependency-ordering reference.
Minor mischaracterization: cite them distinctly so the cleanup edits the right thing (a doc example vs. an installsAfter dependency).

### Design Decisions: host chsh has no documented rollback / safety net (non-blocking, safety)

The proposal correctly flips live machine state (`chsh` on the host, editing `~/.config/lace/settings.json`) but documents no host-side rollback or ordering safeguard.
If the restored bash config errors or the ble.sh install fails after `chsh -s /usr/bin/bash` has already run, the user's new login shells land degraded.
The blast radius is genuinely small (nu stays installed and remains a valid shell, wezterm's `default_prog` is `tmux new-session` rather than the login shell, and tmux `default-shell` becomes `$SHELL`), so a full lockout is unlikely, but the proposal should still state the safe order explicitly: `chezmoi apply`, open a fresh interactive bash and confirm ble.sh loads and the prompt renders, keep the current terminal open, and only then `chsh`.
Also note that `chsh -s /usr/bin/bash` requires `/usr/bin/bash` to be listed in `/etc/shells` (it is a real binary on this host, but PATH bash resolves to the linuxbrew copy, so pin the absolute path deliberately) and add a one-line "revert with `chsh -s ~/.cargo/bin/nu` and restore the settings.json backup" rollback note.

### Verification Methodology: host block conflates non-interactive and interactive checks (non-blocking)

The host block mixes a detached `tmux new-session -d -s vt 'echo $0; sleep 1'` (non-interactive) with `shopt -q login_shell; echo "ble loaded: ${BLE_VERSION:-no}"`, which only populates `BLE_VERSION` inside an interactive ble.sh session.
`shopt -q login_shell` sets exit status but prints nothing, so the line reads as if it verifies something it does not.
Split the interactive ble.sh check into its own explicitly-interactive invocation (mirroring the container block's `bash -lic '...'`) and drop the bare `shopt -q login_shell`.
The line `STARSHIP output should still show the lace project name via LACE_PROJECT_NAME` is prose inside a code block, not a command: make it an actual assertion or move it to prose.
These are presentation nits; the intended checks are sufficient to prove success.

### Phase 2: ble.sh feature remains an unresolved fork (non-blocking, scoped)

Phase 2 leaves "author a `blesh` feature" vs. "fold into `lace-fundamentals`" as an open decision pending investigation.
For an about-to-implement proposal this is a real unspecified branch, but it is flagged as investigate-first and the acceptance check (ble.sh active in a fresh container) is outcome-based rather than mechanism-based, so either path is provable.
Acceptable as written; just be aware Phase 2 is not fully specified until that investigation lands.

### Cascade and phase ordering: sound

The dependency logic is correct. clauthier and whelm carry no local nu shell config and inherit `defaultShell` from `~/.config/lace/settings.json`, so the Phase 2 flip (setting `defaultShell` to bash explicitly, which makes `lace-fundamentals` `chsh` node to bash and override the `node:24-bookworm` bake) cascades to them for free.
jif and weftwise hardcode nu locally and require the Phase 3 hand-edits.
The blesh feature must exist in lace (Phase 2) before jif/weftwise gain ble.sh in Phase 3, which is the legitimate reason Phase 2 must precede Phase 3; the "do not reorder" instruction is slightly overstated for the shell-default aspect (jif/weftwise nu removal is independent of the lace flip) but correct for ble.sh parity.

### cdocs conventions: compliant

Frontmatter present with title, date, status, `first_authored`, type, state, tags: satisfies both the dotfiles `.claude/rules/cdocs.md` and the lace frontmatter spec.
BLUF present as a `> BLUF:` block. Sentence-per-line throughout. Code blocks are language-tagged (`mermaid`, `sh`). Zero em-dashes. Diagram uses Mermaid, not ASCII.
No convention issues.

## Verdict

**Accept with nits.**
The design is correct, the cross-repo entanglement map is accurate, and the phase ordering and cascade reasoning are sound.
All findings are non-blocking. Clean up the nits below during implementation.

## Action Items

1. [non-blocking] Fix the Phase 1 shell-init reference: `env.nu:51` is `STARSHIP_SHELL`, not the init generation; the real lines are `env.nu:78` (`starship init nu`) and `env.nu:92` (`zoxide init nushell`). Reframe as "add bash init to the restored bash config" since the nu generation stays for the retained host scripts.
2. [non-blocking] Correct the "no nu code in any consumer" claim: whelm vendors the sprack nu heredoc at `.devcontainer/features/sprack/install.sh:57-70`. Add a NOTE and either list dropping it as an optional Phase 4 item or explicitly scope it out as inert.
3. [non-blocking] In the Edge Cases stray-references list, distinguish `devcontainer-feature.json:12` (defaultShell example) from `:19` (an `installsAfter` nushell dependency, not a defaultShell example).
4. [non-blocking] Document a host safety/rollback step: apply config, validate ble.sh in a fresh interactive bash with the current terminal still open, then `chsh`; note the `/etc/shells` requirement and a `chsh -s ~/.cargo/bin/nu` + settings.json-backup revert path.
5. [non-blocking] Tidy the host verification block: give the interactive ble.sh check its own `bash -lic '...'` invocation, drop the standalone `shopt -q login_shell`, and turn the STARSHIP prose line into an actual assertion or move it out of the code block.

## Clarifications Requested (Multiple Choice)

1. whelm's vendored sprack nu hook: (a) drop it in Phase 4 for full cleanup, (b) leave it as inert and scope it out with a NOTE, or (c) track it as a separate follow-up. Recommend (b).
2. The ble.sh container feature: (a) commit to a standalone `blesh` feature now, or (b) keep the fork open and let the Phase 2 investigation decide. Recommend (b), since the acceptance check is outcome-based.

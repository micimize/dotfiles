---
review_of: cdocs/proposals/2026-03-24-lace-paste-image.md
first_authored:
  by: "@claude-opus-4-6-20250725"
  at: "2026-03-24T12:45:00-07:00"
task_list: tmux/image-paste-through
type: review
state: archived
status: done
tags: [self, architecture, edge_cases, script_correctness, ssh_bridge]
---

# Review: lace-paste-image Context-Aware Image Paste Bridge

## Summary Assessment

This proposal designs a tmux-layer script that detects clipboard images and routes them context-aware: passthrough for local panes, SCP-and-paste-path for SSH panes with lace metadata, and graceful fallback otherwise. The architecture is sound and aligns well with the existing lace pattern (verified against the actual `lace-split` script). The edge case analysis is notably thorough. The main concerns are: a subtle `set -e` / `$?` bug in the script draft, an underspecified interaction between `run-shell` latency and user-visible UX, and one design decision (always preferring image over text when both are on the clipboard) that deserves explicit callout as a trade-off rather than presenting it as unambiguously correct. Verdict: **Revise** on two blocking items, with several non-blocking suggestions.

## Section-by-Section Findings

### Frontmatter

Well-formed. `status: wip` is appropriate for a pre-review draft. Tags are descriptive. No issues.

### BLUF / Summary

Clear and accurate. The BLUF packs the three key facts (Ctrl+V unbind, local passthrough, SSH bridge via SCP) into two sentences. The third sentence about mirroring `lace-split` sets context efficiently. Good use of the pattern.

### Architecture Diagram

The ASCII flow diagram is easy to follow and covers all three branches. One minor inaccuracy: the "local pane" branch says the app "calls wl-paste directly," which is correct, but the diagram labels the first WezTerm step as "no longer intercepts" without noting that this requires the Phase 1 config change. The dependency is clear from context but could be more explicit for a reader skimming the diagram alone.

**Finding: [non-blocking]** The diagram implies WezTerm passthrough is the default state. Add a brief annotation like "(after Phase 1 config change)" to the WezTerm step.

### Script Draft (lines 97-169)

The script closely mirrors `lace-split`'s patterns (verified against `/var/home/mjr/code/weft/lace/main/bin/lace-split`). SSH detection via `pane_current_command`, metadata via `show-option -pqv`, and identical SCP options are all correct.

However, there is a bug in the SCP error handling:

```bash
scp -q \
  ...
  "$local_path" "${user:-node}@localhost:${remote_path}" 2>/dev/null

if [ $? -ne 0 ]; then
```

With `set -e` (line 98), a non-zero `scp` exit will abort the script before reaching the `if [ $? -ne 0 ]` check. The fallback logic on lines 158-162 is dead code. The fix is either to append `|| true` to the `scp` line, or to restructure as `if ! scp ...; then`.

The actual `lace-split` script does not have this problem because it does not check SCP exit codes -- it uses `exec ssh` inside `split-window`, so failures manifest as the new pane exiting.

**Finding: [blocking]** The `set -e` + `$?` check pattern is a bug. Under `set -euo pipefail`, a failed `scp` will terminate the script immediately, bypassing the fallback `send-keys C-v`. The implementation must use `if ! scp ...; then` or `scp ... || scp_failed=true` instead.

Additionally, the proposal correctly identifies the timestamp collision issue (lines 228-231) and recommends `mktemp`, but the script draft still uses raw timestamps. The Phase 2 description (line 323) says to use `mktemp`, which contradicts the draft. This is fine for a proposal (the draft is illustrative, not final), but worth noting for implementation.

**Finding: [non-blocking]** The script draft uses `date +%s` for temp file naming despite the edge cases section recommending `mktemp`. Align the draft with the recommendation, or add a comment noting the draft is illustrative.

### Script: Missing Session-Level Fallback for Metadata

The actual `lace-split` script falls back from pane-level to session-level options:

```bash
port=$(tmux show-option -pqv @lace_port 2>/dev/null)
[ -z "$port" ] && port=$(tmux show-option -qv @lace_port 2>/dev/null)
```

The `lace-paste-image` draft only checks pane-level:

```bash
port=$(tmux show-option -pqv -t "$pane_id" @lace_port 2>/dev/null)
```

If lace metadata is set at the session level (which `lace-into` may do for the initial pane), the paste bridge would miss it.

**Finding: [blocking]** Add session-level fallback for `@lace_port` and `@lace_user`, matching the `lace-split` pattern. Without this, the script may fail to detect lace SSH panes that were created by `lace-into` (which may set session-level options for the first pane).

### Data Flow Cases (lines 173-184)

All four cases are correctly described. Case 4 (SSH without lace metadata) correctly identifies the degradation behavior and why it is acceptable. Good.

### Design Decisions

All five decisions are well-reasoned and justified. The "tmux layer, not WezTerm layer" decision is particularly strong -- it maintains the existing architecture's separation of concerns and avoids putting context-aware logic in WezTerm.

The "PNG only" decision is pragmatic. One nuance worth noting: `wl-paste --type image/png` performs conversion from whatever the source format is, but if the clipboard contains only `image/jpeg` and not `image/png`, the conversion may fail on some Wayland compositors. Most compositors (including wlroots-based ones and Mutter) do handle this, but it is compositor-dependent behavior, not a Wayland protocol guarantee.

**Finding: [non-blocking]** Consider adding a note that PNG conversion from non-PNG sources is compositor-dependent. If this becomes an issue, the script could check for `image/png` specifically in the MIME list, or try PNG first with a JPEG fallback.

### Edge Cases

This section is unusually thorough for a proposal. The tmux copy mode analysis is correct: `C-v` in `copy-mode-vi` (line 78 of `tmux.conf`) takes precedence over the root table binding, so there is no conflict.

The "clipboard has both image and text" case deserves more scrutiny. The script always prefers image when any image MIME type is present. In practice, copying text from a web page often includes `image/png` (as a rendered snapshot of the selection) alongside `text/plain`. Under this design, Ctrl+V on such clipboard contents would trigger the image path, not text paste.

This is not necessarily wrong -- the user can use Ctrl+Shift+V for text -- but it is a significant behavioral change from the current "Ctrl+V always pastes text" mental model. The proposal acknowledges this but frames it as a simple fallback ("Ctrl+Shift+V still works"). For an initial self-review, this is the trade-off most likely to cause user surprise.

**Finding: [non-blocking]** The "image takes priority" heuristic may cause unexpected behavior when copying rich content (web pages, documents) that includes both text and image MIME types. Consider either:
- (a) Checking whether `text/plain` is ALSO present and preferring text in that case (only treat as image-paste when image is the sole content type).
- (b) Keeping the current design but adding a prominent note in the proposal that this is a conscious trade-off and may need tuning after real-world use.

Option (b) is probably the right call for v1 since option (a) would break the case where the user explicitly copies a screenshot from a browser (which also has `text/html`).

### UX Latency

The proposal does not discuss the latency introduced by `run-shell`. Every Ctrl+V now spawns a bash process that runs `wl-paste -l` before deciding what to do. For the common case (no image, text paste), this adds measurable delay vs. the current instant passthrough.

The `tmux run-shell` command is asynchronous by default (does not block the pane), but the `send-keys C-v` is deferred until the shell completes. For the no-image-text-paste path, the user will see a brief gap between pressing Ctrl+V and text appearing.

**Finding: [non-blocking]** Consider noting the latency trade-off. `wl-paste -l` is fast (typically <10ms) and `run-shell` overhead is small, so this is likely imperceptible. But it is worth an explicit note so the implementation can include timing validation (e.g., `time wl-paste -l` baseline measurement).

### Test Plan

Comprehensive. Covers all four routing cases plus three regression scenarios (copy mode, vim, non-tmux). The verification methodology section provides concrete commands.

One gap: the test plan does not cover the case where `wl-paste` is slow or hangs (e.g., Wayland compositor unresponsive). Since `run-shell` has no built-in timeout, a hung `wl-paste -l` would block the paste entirely with no feedback.

**Finding: [non-blocking]** Consider adding a `timeout` wrapper around `wl-paste -l` (e.g., `timeout 1 wl-paste -l`) to prevent indefinite hangs if the compositor is unresponsive. This could be a Phase 2 refinement.

### Implementation Phases

The four phases are well-ordered: WezTerm first (unblocks local paste immediately), then script, then binding, then environment propagation. Each phase has clear validation criteria.

Phase 4 (`update-environment`) is important and easy to overlook. It correctly identifies that `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` must survive reattach for `wl-paste` to work in the script after a detach/reattach cycle. Without this, the script would silently fall through to `send-keys C-v` (clean degradation, but the user would lose image paste after any tmux detach).

**Finding: [non-blocking]** Phase 4 is critical for reliability but is listed last. Consider promoting it to Phase 1 or 2, since without it the script is fragile after reattach. It is also the lowest-risk change (pure additive tmux config).

### Writing Conventions

The document follows BLUF structure, uses active voice, and keeps paragraphs short. Code blocks specify languages. One observation: the proposal uses em-dashes in a few places (the NOTE block, line 28) but generally prefers colons and periods, which is good.

The document is well-structured but long (364 lines). For a proposal, this level of detail is appropriate given the multi-component design.

### Cross-Reference with Background Report

The proposal correctly builds on the report's findings. The report identified two blockers (WezTerm intercept and SSH gap) and recommended Option A (WezTerm callback bridge). The proposal instead places the logic in tmux, which is a better architectural fit. The report's Option A is acknowledged implicitly by the "tmux layer, not WezTerm layer" design decision but could explicitly note the deviation from the report's recommendation.

**Finding: [non-blocking]** Add a brief note explaining why the proposal chose the tmux-layer approach over the report's recommended WezTerm `action_callback` approach (Option A). The reasoning is present in the design decisions section but does not reference the report's specific recommendation.

## Verdict

**Revise.** The design is architecturally sound, the edge case coverage is strong, and the implementation plan is clear. Two blocking issues must be addressed:

1. The `set -e` / `$?` bug in the script draft will cause SCP failures to abort the script instead of falling back gracefully.
2. The missing session-level metadata fallback breaks parity with `lace-split` and may cause silent failures for panes created by `lace-into`.

The non-blocking items are genuine improvements but the proposal is solid without them.

## Action Items

1. [blocking] Fix the `set -e` + `$?` bug in the SCP error handling. Use `if ! scp ...; then` or capture the exit code with `|| scp_failed=true`.
2. [blocking] Add session-level fallback for `@lace_port` and `@lace_user` metadata, matching the `lace-split` pattern: check pane-level first, then session-level.
3. [non-blocking] Add a "(after Phase 1 config change)" annotation to the architecture diagram's WezTerm step.
4. [non-blocking] Align the script draft's temp file naming with the `mktemp` recommendation, or add a comment noting the draft is illustrative.
5. [non-blocking] Note that PNG conversion from non-PNG clipboard sources is compositor-dependent behavior.
6. [non-blocking] Add explicit discussion of the "image takes priority over text" trade-off for mixed-MIME clipboards, and flag it as something to tune after real-world use.
7. [non-blocking] Note the latency characteristics of the `run-shell` + `wl-paste -l` path for the common no-image case.
8. [non-blocking] Consider adding `timeout 1` around `wl-paste -l` to guard against compositor hangs.
9. [non-blocking] Consider promoting Phase 4 (`update-environment`) earlier in the implementation order, since `wl-paste` in the script depends on it after reattach.
10. [non-blocking] Add a brief note explaining the deviation from the background report's Option A recommendation.

---
review_of: cdocs/devlogs/2026-02-11-smart-splits-adoption.md
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T23:30:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: review
state: live
status: done
tags: [fresh_agent, implementation_review, proposal_compliance, code_quality, test_plan, cross_config_ipc]
---

# Review: Smart-Splits Adoption Implementation Devlog

## Summary Assessment

This devlog documents the implementation of seamless `Ctrl+h/j/k/l` navigation between WezTerm panes and Neovim splits via smart-splits.nvim.
The implementation matches the proposal closely, with both phases completed and verified through automated test suites (42/42 Neovim headless, 17-point WezTerm 4-layer stack).
The code is clean, well-organized, and the two deviations from the proposal are properly documented with corrective detail.
The most significant findings are: (1) the devlog frontmatter is missing required fields per cdocs rules, (2) the test suite omits assertions for `<C-A-j>` and `<C-A-k>` resize keymaps, creating a gap in verification coverage, and (3) the `lazy = false` plus `keys` spec interaction has a subtle loading semantics issue that should be documented.
Verdict: **Revise** with minor fixes.

## Proposal Compliance Audit

### Phase 1: Neovim Side

**navigation.lua** matches the proposal's code block character-for-character.
All 8 keybindings (4 navigation, 4 resize) are present with the correct functions and descriptions.
The `at_edge = "stop"` option and `lazy = false` comment are both present.

**init.lua** edits are correct: the 4 old `<C-h/j/k/l>` keymaps at the former lines 83-86 are removed.
The comment at line 82-83 is updated to reference smart-splits.nvim and points to `lua/plugins/navigation.lua`.
No other lines were touched: buffer navigation, quick save, indenting, and all other keymaps remain intact.

**config_test.lua** adds smart-splits-specific assertions as specified in the proposal's test plan.
The test structure matches the proposal (plugin registration, require check, callback-based keymap assertions, old-keymap removal check).

**Compliance: PASS.**

### Phase 2: WezTerm Side

**wezterm.lua** adds the `is_nvim()`, `direction_keys`, and `split_nav()` helpers exactly as specified in the proposal.
The helpers are placed in a dedicated section with the same section comment as the proposal.
The 8 static bindings (4 `ActivatePaneDirection`, 4 `AdjustPaneSize`) are replaced with `split_nav("move", ...)` and `split_nav("resize", ...)` calls.

All unaffected bindings are preserved: `Alt+h/j/k/l` SplitPane, `Alt+n/p` tab navigation, `Alt+w` close, `Alt+c` copy mode, leader bindings, workspace switching, lace plugin, mouse bindings, copy mode customization.

**Compliance: PASS.**

### Phase 3: Cleanup and CLAUDE.md Update

The proposal lists Phase 3 as "optional": update CLAUDE.md with smart-splits documentation.
The devlog does not mention Phase 3 and no CLAUDE.md changes were made.
This is acceptable since the phase was marked optional, but the devlog should note the decision to skip it.

**Compliance: PASS (with note).**

## Section-by-Section Findings

### Frontmatter

**[blocking]** The devlog frontmatter is missing the `title` and `date` fields.
Per the project's `.claude/rules/cdocs.md`: "Every document must begin with YAML frontmatter containing at minimum: `title`, `date`, `status`."
The `first_authored.at` timestamp does not substitute for a standalone `date` field.

**[non-blocking]** The `first_authored.by` value is `"claude-opus-4-6"` without the `@` prefix.
Per the frontmatter spec, the `by` field should use the `@` prefix: `"@claude-opus-4-6"`.

### Implementation Notes

**[non-blocking]** The two deviation NOTEs are well-written and add genuine value.
The `<M-C-H>` vs `<C-M-H>` keymap encoding correction (lines 101-103) is a real finding that improves the project's collective knowledge.
The `EmitEvent` vs `action_callback` observation for `show-keys` output (lines 107-109) corrects the proposal's test plan and will save future implementors time.
Both notes follow the `NOTE(author/workstream)` callout convention.

**[non-blocking]** The "Manual verification gap" section (lines 111-113) is clear and honest about what cannot be tested.
This matches the proposal's "What Cannot Be Tested Programmatically" table and does not overclaim.

### Changes Made Table

The table lists 4 files with accurate descriptions.
Cross-referencing against the actual files:

- `navigation.lua`: described as "Created" with correct detail about `lazy = false`, `at_edge = "stop"`, and both keymap sets. Verified accurate.
- `init.lua`: described as "Edited" with removal of 4 keymaps and comment update. Verified accurate.
- `config_test.lua`: described as "Created" with 42 assertions. Verified: the file has exactly 42 test calls.
- `wezterm.lua`: described as "Edited" with helper additions and 8 binding replacements. Verified accurate.

**[non-blocking]** The table says `config_test.lua` was "Created", but the proposal references it as an existing file to "Edit" (adding smart-splits assertions to the existing suite).
The devlog's Implementation Notes section clarifies this: "Created the headless test suite from scratch."
This is a deviation from the proposal's assumption that a test file already existed, and is worth a brief NOTE callout.

### Verification Records

**Phase 1 (Neovim):** 42/42 test output is included verbatim.
Cross-referencing the test names against `config_test.lua` assertions, all 42 match.
The output shows proper structure: core settings (8), plugin loading (15), keymaps (7 including smart-splits), smart-splits specific (7), error detection (2), module availability (3).

**[blocking]** The test suite checks `<C-A-h>` and `<C-A-l>` resize keymaps but omits `<C-A-j>` and `<C-A-k>`.
The proposal's test plan only specifies `<C-A-h>` and `<C-A-l>` as examples, but the implementation has all 4 resize keymaps.
Verifying only 2 of 4 leaves a coverage gap: a typo in the `resize_down` or `resize_up` function call in `navigation.lua` would go undetected.

**Phase 2 (WezTerm):** 17-point validation output is included with layer labels.
All 4 layers are represented.
The layer 3 results confirm all 8 h/j/k/l bindings (4 Ctrl, 4 Ctrl+Alt) show as `EmitEvent`, matching the deviation note.
The layer 3 results also confirm unaffected bindings: `SplitPane` and `CopyMode` are present.
The layer 4 results confirm hot-reload, mux health, and pane topology.

**Trustworthiness assessment:** The verification records are credible.
The test output aligns with the test code, the deviation notes explain real discrepancies, and the WezTerm layer labels map to the documented validation stack.
The Neovim `EXIT: 0` confirms `cquit 0` was reached.

### Manual Verification Section

**[non-blocking]** The 5 manual verification scenarios match the proposal's test plan exactly.
No manual verification results are recorded in the devlog, which is appropriate since manual testing was deferred for the human.
The devlog could benefit from a brief note stating that these are left for the user to verify post-review.

## Code Quality of Changed Files

### `navigation.lua`

Clean, minimal, matches the proposal exactly.
The cross-reference comment to the proposal and wezterm.lua is good practice for a cross-config integration.

**[non-blocking]** The `keys` spec in combination with `lazy = false` has a subtle interaction in lazy.nvim.
When both `lazy = false` and `keys` are specified, lazy.nvim creates the keymaps via its `keys` handler, which uses `require("smart-splits")` inside each callback.
Since `lazy = false`, the plugin is also loaded at startup.
This means the plugin is loaded twice in a sense: once eagerly (setting `IS_NVIM`), and the keymaps are set up through lazy's key handler.
This works correctly in practice, but the mental model could confuse a future maintainer.
A brief code comment clarifying "keys here define the mappings; lazy = false ensures IS_NVIM user var is set at startup" would help.

### `init.lua`

The edit is clean: 4 lines removed, 2 comment lines updated.
No unintended changes to surrounding code.
The comment "Window navigation: Ctrl+H/J/K/L handled by smart-splits.nvim" with the cross-reference to `navigation.lua` is clear.

### `wezterm.lua`

The smart-splits section (lines 112-143) is well-structured and matches the proposal.
The section comment includes a cross-reference to the proposal.
The `is_nvim()` function is a clean one-liner.
The `direction_keys` bidirectional lookup table is elegant.
The `split_nav()` function correctly branches on `resize_or_move` and constructs the right mods string.

The placement of the section (between mouse bindings and keybindings) is logical: helpers before use.

The `split_nav("move", ...)` and `split_nav("resize", ...)` calls in `config.keys` are at lines 159-162 and 193-196 respectively.
The resize group is separated from the move group by the Alt split/tab/close/copy bindings, which preserves the existing organizational structure of the keybindings section.

**[non-blocking]** The keybindings section comment (lines 146-153) has been updated to note "smart-splits aware" for pane navigation and resize, which is good.

### `config_test.lua`

The test framework is clean and minimal: a `test()` wrapper with pcall, `assert_eq` and `assert_true` helpers, and a JSON results file.
The `UIEnter` trigger with `vim.wait(500)` follows the documented headless testing pattern.
The `cquit` exit with proper error code propagation is correct.

**[non-blocking]** The test file uses `io.write` for output, which routes to stderr in headless mode (as documented in MEMORY.md).
The JSON results go to `/tmp/nvim_test_results.json` via `io.open`, which is the reliable path documented in MEMORY.md.
This is good practice.

## Verdict

**Revise.**

The implementation is clean, proposal-compliant, and well-verified.
The two documented deviations (keymap encoding order, EmitEvent format) are genuine findings that add value to the project's knowledge base.
Two blocking issues need resolution: the missing frontmatter fields and the incomplete resize keymap test coverage.
Once addressed, this devlog is ready to accept.

## Action Items

1. [blocking] Add `title` and `date` fields to the devlog frontmatter. Suggested: `title: "Smart-Splits Adoption"`, `date: 2026-02-11`.
2. [blocking] Add test assertions for `<C-A-j>` (resize down) and `<C-A-k>` (resize up) in `config_test.lua` to match the existing `<C-A-h>` and `<C-A-l>` assertions. Use `<M-C-J>` and `<M-C-K>` as the lhs values per the encoding correction documented in the devlog. Re-run the test suite and update the verification output.
3. [non-blocking] Prefix the `first_authored.by` value with `@`: change `"claude-opus-4-6"` to `"@claude-opus-4-6"`.
4. [non-blocking] Add a NOTE callout in the Implementation Notes documenting that `config_test.lua` was created from scratch rather than edited (deviating from the proposal's assumption of an existing file).
5. [non-blocking] Add a brief note about Phase 3 (CLAUDE.md update) being intentionally skipped, or plan a follow-up to complete it.
6. [non-blocking] Consider adding a code comment to `navigation.lua` clarifying the `lazy = false` + `keys` interaction: the former ensures `IS_NVIM` is set at startup, the latter defines the actual keymaps.

## Questions for the Author

**Q1: Should the missing resize keymap tests block acceptance?**
- (a) Yes, add `<M-C-J>` and `<M-C-K>` assertions now and re-verify. This is the safer option since it closes a real coverage gap.
- (b) No, the existing `<M-C-H>` and `<M-C-L>` tests provide sufficient confidence. Defer `j`/`k` assertions to a test-suite-improvement pass.

**Q2: Should Phase 3 (CLAUDE.md documentation) be completed as part of this work or deferred?**
- (a) Complete it now: add a "Neovim/WezTerm Navigation" section to CLAUDE.md documenting the smart-splits pattern, no-lazy-load requirement, and mux reattach workaround.
- (b) Defer it: the proposal marks it optional, and the cross-references in `navigation.lua` and `wezterm.lua` provide sufficient documentation for now.
- (c) Create a follow-up proposal: the CLAUDE.md section deserves its own small proposal to ensure the content is reviewed.

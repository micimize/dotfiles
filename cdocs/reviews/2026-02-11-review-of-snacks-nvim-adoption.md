---
review_of: cdocs/devlogs/2026-02-11-snacks-nvim-adoption.md
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T22:30:00-05:00
task_list: neovim/snacks-migration
type: review
state: live
status: done
tags: [fresh_agent, implementation_review, keybinding_audit, proposal_compliance, code_quality]
---

# Review: snacks.nvim Adoption Implementation Devlog

## Summary Assessment

This devlog documents the implementation of the accepted proposal to replace 8 neovim plugins with `folke/snacks.nvim` across 4 phases. The implementation is thorough and follows the proposal closely, with all 4 phases completed and committed. The code is clean, well-organized, and the verification is substantive (45/45 headless checks). The most significant findings are: (1) the proposal's Phase 4 picker keybindings for `<C-j>`/`<C-k>` navigation and `<C-q>` quickfix are missing from the implementation, (2) a duplicate `<leader>ft` binding exists in both `snacks.lua` and `editor.lua`, and (3) the devlog frontmatter is missing required fields. Verdict: **Revise** -- the missing picker bindings and duplicate binding need resolution, but the core implementation is solid.

## Phase-by-Phase Compliance Audit

### Phase 1: Zero-Config Foundations -- PASS

The proposal specifies enabling `bigfile`, `quickfile`, `scope`, `words`, and `statuscolumn` with no existing file modifications. The implementation at `/var/home/mjr/code/personal/dotfiles/dot_config/nvim/lua/plugins/snacks.lua` lines 11-15 enables all 5 modules as `{ enabled = true }`. The constraint "purely additive, no existing files modified" was respected -- Phase 1 only touches `snacks.lua`.

### Phase 2: Notification, Indent, Input, Explorer Replacement -- PASS (with notes)

The proposal specifies enabling `notifier`, `indent`, `input`, `explorer`, `rename`, `toggle` in snacks.lua, plus removing 4 plugins from `ui.lua`, updating bufferline offset, cleaning up colorscheme NeoTree highlights, relocating LSP diagnostic bindings, adding the JSONL logger, and adding explorer/notification keybindings.

Verified in the implementation:
- **snacks.lua lines 18-47**: All 6 modules enabled. Notifier config matches spec: `top_down = false`, `style = "compact"`, filter function using `notif.msg` (the deviation note about field name is appropriate).
- **ui.lua**: Reduced to 3 plugins (bufferline, lualine, which-key). Neo-tree, nvim-notify, indent-blankline, dressing all removed. Bufferline offset correctly set to `snacks_layout_box` (documented deviation -- good).
- **colorscheme.lua**: NeoTree highlight overrides removed. Only gitsigns highlights remain.
- **lsp.lua lines 55-58**: `<leader>e` relocated to `ge`, `ge`/`gE` relocated to `gne`/`gpe`. Matches proposal exactly.
- **lsp.lua lines 62-75**: `:Format` command and `BufWritePre` autocmd added. Format-on-save checks `vim.b[bufnr].autoformat_disabled`.
- **init.lua lines 143-163**: JSONL logger installed in `VeryLazy` autocmd. Code matches the proposal's snippet exactly.
- **snacks.lua lines 91-95**: Explorer (`<leader>e` reveal, `<leader>E` toggle) and notification (`<leader>nh`, `<leader>nd`) keybindings present.
- **ui.lua line 73**: `<leader>n` registered as which-key "notifications" group.

The previous review's blocking items (keybinding conflicts) were resolved:
- `<leader>e` conflict: resolved by relocating diagnostic float to `ge` (option b from Q1).
- `<leader>n` collision: resolved by moving explorer toggle to `<leader>E` and keeping `<leader>n` for notifications (the approach from the proposal's revision).
- `<leader>f` format: resolved by removing it entirely and using `:Format` + format-on-save (option c from Q3).

### Phase 3: Dashboard -- PASS

The proposal specifies enabling `dashboard` with sections for header, keys, recent files, projects, and startup time. Session restore should call `require("persistence").load()`.

Verified in the implementation:
- **snacks.lua lines 50-69**: Dashboard enabled with all 5 section types. Keys include find file, grep, recent files, restore session, lazy, quit -- matching the proposal spec.
- **snacks.lua line 57**: Session restore correctly calls `require('persistence').load()`.
- The `oldfiles` source name (line 56) is used rather than `recent` -- this is a dashboard pick source name, distinct from the picker's `recent` source. Worth noting but not incorrect.

### Phase 4: Picker Migration -- PASS (with findings)

The proposal specifies enabling `picker` with `ui_select = true` and `bufdelete`, deleting `telescope.lua`, updating `editor.lua`'s todo-comments binding, removing `<leader>bd` from init.lua, adding `netrwPlugin` to disabled plugins, and porting all telescope keybindings including picker insert-mode mappings (`<C-j>`/`<C-k>`, `<Esc>`, `<C-q>`).

Verified in the implementation:
- **snacks.lua lines 72-87**: Picker enabled with `ui_select = true`, `hidden = true` for files/grep sources. `bufdelete` enabled.
- **telescope.lua**: Confirmed deleted (glob returns no results).
- **editor.lua line 57**: `<leader>ft` changed from `TodoTelescope` to `Snacks.picker.todo_comments()`.
- **init.lua line 127**: `netrwPlugin` added to disabled plugins (correct name, not `netrw`).
- **init.lua**: `<leader>bd` keymap removed (was at line 93 in the old version; no longer present).
- **snacks.lua line 82**: `<Esc>` configured for close from both insert and normal mode.

See findings below for missing picker keybindings.

## Section-by-Section Findings

### Frontmatter (Devlog)

**[blocking]** The devlog frontmatter is missing the `title` field. Per the project's `.claude/rules/cdocs.md`: "Every document must begin with YAML frontmatter containing at minimum: `title`, `date`, `status`." The `date` field is also absent (the `first_authored.at` field does not substitute for `date` per the rule). Add both fields.

**[non-blocking]** The `first_authored.at` timestamp is `2026-02-11T00:00:00-05:00` (midnight placeholder). This should reflect actual authoring time for provenance.

### Keybinding Migration Table Compliance

**[blocking]** The proposal's Phase 4 spec states: "Picker insert-mode mappings: `<C-j>`/`<C-k>` for navigation, `<Esc>` to close, `<C-q>` to send to quickfix (matching current telescope muscle memory)." Only `<Esc>` is implemented (snacks.lua line 82). The `<C-j>`/`<C-k>` picker navigation and `<C-q>` quickfix-send bindings are missing from the implementation. These are specified in the proposal to preserve telescope muscle memory and their absence is not documented as a deviation.

If snacks.picker already provides `<C-j>`/`<C-k>` as defaults, this should be documented as a "matches by default, no override needed" note. If it does not, these bindings need to be added. Either way, the `<C-q>` quickfix binding needs to be addressed or explicitly deferred.

**[blocking]** The `<leader>ft` binding is defined in two places: `snacks.lua` line 111 and `editor.lua` line 57. Both map to `Snacks.picker.todo_comments()`. While both will work (lazy.nvim merges keys from all specs), having the same binding in two files is a maintenance hazard. The proposal says to "Update `editor.lua`: change todo-comments `<leader>ft` from `TodoTelescope` to `Snacks.picker.todo_comments()`" and also lists `<leader>ft` in the snacks picker keybindings table. One of these should be removed. The binding arguably belongs in `editor.lua` alongside the todo-comments plugin spec (since it depends on that plugin being loaded), but having it only in `snacks.lua` with all the other picker bindings is also defensible. Pick one location.

### Deviations Documentation

**[non-blocking]** The deviations section documents 3 implementation notes (todo-comments integration source, explorer filetype, Esc behavior). All three are accurate and well-explained. However, it does not document the missing `<C-j>`/`<C-k>`/`<C-q>` picker bindings, which is a deviation from the proposal's Phase 4 spec.

### Verification Section

**[non-blocking]** The headless validation (45/45 PASS) is comprehensive and covers module enablement, keybinding registration, and negative checks (removed plugins not loaded). The JSONL logger verification includes a concrete sample entry. This is stronger than most devlog verification sections.

However, the validation checks "18 keybindings registered" but the proposal specifies more than 18 when counting the picker insert-mode mappings. The 18 count matches the `keys` table in `snacks.lua` (lines 89-114), confirming the picker navigation bindings were not implemented rather than implemented elsewhere.

**[non-blocking]** The "Remaining Cleanup" section correctly identifies that `:Lazy clean` is needed. The `lazy-lock.json` still references telescope, neo-tree, nvim-notify, indent-blankline, dressing, and nui -- confirmed by grep. This is expected and clearly communicated.

### Code Quality

**[non-blocking]** The `lsp.lua` format-on-save autocmd (lines 66-75) has a subtle issue: the outer `if not vim.b[bufnr].autoformat_disabled` check on line 66 means the `BufWritePre` autocmd is only created if autoformat is enabled at the time the LSP attaches. If a user starts with autoformat disabled (via the toggle) and then re-enables it, the autocmd will never have been created for that buffer. The inner check on line 70 is the actual guard. The outer check should be removed so the autocmd is always created and the inner check handles the toggle state dynamically.

**[non-blocking]** The explorer keybinding on snacks.lua line 91 passes `{ focus = true }` to `Snacks.explorer()` for the reveal binding, while line 92 calls `Snacks.explorer()` with no arguments for the toggle. This distinction is not documented in the proposal's keybinding table, which just says "Snacks.explorer()" for both. The deviation note about `<Esc>` was documented but this behavioral distinction was not. Minor, but worth a comment in the code or devlog.

**[non-blocking]** The `notif.msg` field in the filter function (snacks.lua line 33) -- the devlog's "Gotchas" section correctly flagged this as something to verify. The implementation uses `notif.msg`, which appears correct but should be validated against the installed snacks version. The filter gracefully handles nil (`notif.msg and ...`), which is good defensive coding.

### Proposal Status

**[non-blocking]** The proposal's `status` field is `implementation_wip` but with all 4 phases committed, it should be updated to `implemented` or equivalent. The `last_reviewed` on the proposal still shows the first review round with `revision_requested` status -- this should be updated to reflect the current state.

## Verdict

**Revise.**

The implementation is well-executed and closely follows the accepted proposal. All 4 phases are implemented, all major keybinding relocations are correct, all specified plugin removals are done, the verification is thorough, and the deviations are mostly documented. The three blocking findings are relatively minor to fix: add missing frontmatter fields, resolve the duplicate `<leader>ft` binding, and either implement or explicitly defer the missing picker navigation/quickfix bindings. Once these are addressed, this is ready to accept.

## Action Items

1. [blocking] Add `title` and `date` fields to the devlog frontmatter per cdocs.md rules.
2. [blocking] Implement `<C-j>`/`<C-k>` picker navigation and `<C-q>` quickfix-send bindings in the snacks picker config, or document their absence as an explicit deviation with rationale (e.g., "snacks.picker provides these by default" or "deferred to a follow-up").
3. [blocking] Remove the duplicate `<leader>ft` binding -- keep it in one location only (either `snacks.lua` or `editor.lua`, not both).
4. [non-blocking] Remove the outer `if not vim.b[bufnr].autoformat_disabled` guard in `lsp.lua` line 66 -- it prevents the `BufWritePre` autocmd from being created when autoformat starts disabled, making the toggle ineffective for that buffer.
5. [non-blocking] Update the proposal's `status` from `implementation_wip` to `implemented` and update its `last_reviewed` to reflect current state.
6. [non-blocking] Document the `{ focus = true }` distinction between `<leader>e` (reveal, focused) and `<leader>E` (toggle, unfocused) in the deviations section or as a code comment.
7. [non-blocking] Run `:Lazy clean` to remove stale plugin directories and update `lazy-lock.json` (already noted in devlog, listing here for tracking).

## Questions for the Author

**Q1: Where should the `<leader>ft` todo-comments binding live?**
- (a) In `editor.lua` only -- keeps the binding with the plugin that provides the feature.
- (b) In `snacks.lua` only -- keeps all picker bindings in one place.
- (c) Leave as-is in both files -- lazy.nvim deduplicates and it causes no runtime issue. (Not recommended due to maintenance confusion.)

**Q2: What is the status of the `<C-j>`/`<C-k>`/`<C-q>` picker bindings?**
- (a) Snacks.picker already provides these by default -- document this as a "no override needed" note.
- (b) These were intentionally deferred -- add a deviation note explaining why.
- (c) These were accidentally omitted -- implement them in the picker win config.

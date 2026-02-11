---
review_of: cdocs/proposals/2026-02-11-snacks-nvim-adoption.md
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T12:00:00-05:00
task_list: neovim/snacks-migration
type: review
state: live
status: done
tags: [fresh_agent, architecture, completeness, keybinding_conflicts, plugin_migration]
---

# Review: Adopt snacks.nvim as Core UI Layer

## Summary Assessment

This proposal replaces 8 plugins with `folke/snacks.nvim` and adds several new capabilities (dashboard, bigfile, quickfile, scope, words, statuscolumn, explorer, bufdelete, toggle) while keeping the LSP, git, editor, and statusline/bufferline stacks untouched.
The document is thorough: it inventories the current config accurately, maps every keybinding to its replacement, phases the work sensibly, and identifies non-obvious edge cases (array merging, plenary dependency, bufferline offset filetype).
The most important findings are two keybinding conflicts that will break existing functionality if not resolved before implementation, a missing consideration around the `<leader>f` LSP format binding being shadowed by the which-key group, and a handful of frontmatter issues.
Verdict: **Revise** - the keybinding conflicts are blocking, and the frontmatter needs correction, but the proposal's architecture and phasing are sound.

## Section-by-Section Findings

### Frontmatter

**[blocking]** The `first_authored.by` field is `"claude-opus-4-6"` but the frontmatter spec requires an `@` prefix (e.g., `@claude-opus-4-6`).

**[blocking]** The frontmatter is missing the `title` field.
The `.claude/rules/cdocs.md` project rule states every document must have `title` in its frontmatter.
NOTE(opus/review): The frontmatter-spec.md from the plugin does not list `title` as a required field, but the project-local cdocs.md rule does.
The safest path is to add it since the project rule is authoritative for this repo.

**[non-blocking]** The `at` timestamp `2026-02-11T00:00:00-05:00` uses midnight, which is a placeholder rather than an actual authoring time.
This is cosmetic but worth fixing for provenance.

### BLUF

Well-structured.
Leads with the concrete trade (8 out, 1 in, 4 new capabilities), names the phases, calls out what stays unchanged, and mentions the JSONL logger.
No issues.

### Objective

Clear and well-motivated.
Correctly ties back to the UX research report's three friction points.
The ecosystem-direction argument (LazyVim default, AstroNvim v5 adoption) is relevant context.

### Background: Current Plugin Inventory

**[non-blocking]** The table references `ui.lua:141-157` for nvim-notify.
These line numbers are accurate against the current file (lines 141-157).
Good attention to detail; the line references will help the implementer.

**[non-blocking]** The table says plenary.nvim's remaining consumer after telescope/neo-tree removal would be zero.
This is incorrect: `todo-comments.nvim` in `editor.lua:51` lists `"nvim-lua/plenary.nvim"` as a dependency.
The proposal does address this in the "Edge Cases" section (plenary dependency), so it is not a gap in thinking, just an inconsistency in the table's "no remaining consumers" claim.
Suggest rewording the table entry to say "Reduced to single consumer (todo-comments)" instead of "no remaining consumers."

### What snacks.nvim Is

Accurate characterization.
The metatable lazy-loading claim and `priority = 1000` detail are correct based on how folke's module system works.

### Architecture

**[non-blocking]** The proposal says `init.lua` should add `netrw` to the disabled plugins list.
Looking at the current `init.lua:129-133`, the `disabled_plugins` list already has five entries but not `netrw` or `netrwPlugin`.
The correct name for the disabled plugin is `netrwPlugin` (not `netrw`), since the `rtp.disabled_plugins` table takes the plugin file basename without extension, and the actual file is `netrwPlugin.vim`.
This should be corrected in the proposal to avoid a silent no-op at implementation time.

### Module Adoption Map

**[non-blocking]** The `scope` module provides treesitter-based `ii`/`ai` text objects.
The treesitter.lua file shows that `nvim-treesitter-textobjects` is currently commented out with a TODO about API compatibility.
The proposal should note that `snacks.scope` effectively replaces the need for `nvim-treesitter-textobjects` for the scope text object use case, resolving that TODO.

**[non-blocking]** The `statuscolumn` module will render git signs in the status column.
The current `gitsigns.nvim` config (`git.lua:8-13`) renders its own signs with custom characters.
The proposal should clarify how `snacks.statuscolumn` and `gitsigns.nvim` coexist: does statuscolumn consume gitsigns data, or do they compete for the sign column?
In practice, `snacks.statuscolumn` reads from the sign column (consuming whatever signs other plugins place), so they are complementary.
But this deserves a sentence in the proposal.

**[non-blocking]** The "Modules to Skip" section lists `terminal` with "no current terminal plugin; not requested."
Worth noting that `snacks.terminal` is often used for a lazygit integration, and since the proposal already skips `lazygit`, skipping `terminal` is consistent.
No action needed; this is just confirmation the reasoning holds.

### JSONL Notify Logger

**[non-blocking]** The code uses `vim.fn.stdpath("log")` for the log path.
The comment in the proposal says `~/.local/state/nvim/notify.jsonl`.
`vim.fn.stdpath("log")` actually resolves to `~/.local/state/nvim` on XDG-compliant systems, but it could differ on non-Linux platforms.
Since this is a chezmoi dotfiles repo that may be used on macOS as well, the proposal should note this is XDG-dependent, or just say "the path returned by `vim.fn.stdpath('log')`" rather than hardcoding the expected location.

**[non-blocking]** The logger opens and closes the file on every `vim.notify` call.
For high-frequency notification scenarios (e.g., LSP progress during a large project scan), this could be slow.
A buffered approach (write every N notifications or flush on a timer) would be more robust, but this is an optimization concern for later, not a blocker for the proposal.

### Keybinding Migration

**[blocking]** The `<leader>e` binding conflicts.
The proposal maps `<leader>e` to `Snacks.explorer()` (opens at current file), but `lsp.lua:59` already maps `<leader>e` to `vim.diagnostic.open_float` (show diagnostic float) in the `LspAttach` autocmd.
The LSP binding is buffer-local (set in the autocmd callback with `buffer = bufnr`), so it will take precedence over the global snacks explorer binding whenever an LSP is attached.
This means `<leader>e` will open the diagnostic float in LSP-attached buffers and the explorer in non-LSP buffers, which is confusing.
Resolution options:
- (a) Move the explorer-reveal binding to a different key (e.g., `<leader>E` or keep only `<leader>n` with a reveal variant like `<leader>N`)
- (b) Move the diagnostic float binding to a different key (e.g., `<leader>cd` for "code diagnostic")
- (c) Remove the explorer-reveal binding entirely and just use `<leader>n` for toggle (the explorer can be configured to auto-reveal the current file)

**[blocking]** The `<leader>n` / notification keybinding namespace collision.
The proposal uses `<leader>n` for the explorer toggle and `<leader>nh`/`<leader>nd` for notification history/dismiss.
This creates a timeout conflict: pressing `<leader>n` will wait for `timeoutlen` (currently 300ms in `init.lua:67`) before triggering the explorer, because which-key sees `<leader>nh` and `<leader>nd` as possible continuations.
This means every `<leader>n` press will have a noticeable 300ms delay.
The proposal itself mentions in Phase 2: "Add which-key group for notifications under a different prefix (since `<leader>n` is now explorer)" but then proceeds to use `<leader>nh` and `<leader>nd` anyway, which is self-contradictory.
Resolution: move notification bindings to a prefix that does not collide with `<leader>n`, such as `<leader>sn` (snacks notifications) or `<leader>un` (ui notifications).

**[non-blocking]** The `<leader>f` which-key group conflict.
In `lsp.lua:54`, `<leader>f` is mapped to `vim.lsp.buf.format` (format buffer) as a buffer-local binding.
In `ui.lua:111`, `<leader>f` is registered as the "find" which-key group.
These coexist today because the which-key group registration is a label, not a mapping, and the buffer-local LSP format binding takes precedence.
But this means the "find" group hint never appears when an LSP is attached (pressing `<leader>f` immediately formats instead of showing the which-key popup for `ff`, `fg`, `fb`, etc.).
This is a pre-existing issue, not introduced by the proposal, but the proposal should acknowledge it since it is migrating the entire `<leader>f*` finder namespace.
Consider suggesting a fix: move LSP format to `<leader>cf` (code format) to free up `<leader>f` for the find group.

**[non-blocking]** The `<leader>gs` binding.
The proposal maps `<leader>gs` to `Snacks.picker.git_status`, but `git.lua` does not have a `<leader>gs` binding (git status in fugitive is `<leader>gg`).
The current `telescope.lua:74` does map `<leader>gs` to `telescope.builtin.git_status`, so the migration is correct.
However, the Phase 4 constraints say "Do not change git plugin keybindings (`<leader>gg`, `<leader>gb`, etc.)."
The `<leader>gs` binding is currently a telescope binding, not a fugitive binding, so migrating it is correct per the proposal's own logic.
Just noting this is consistent; no action needed.

### Important Design Decisions

The decisions are well-reasoned.
The single-file rationale is sound (multiple lazy.nvim specs for the same plugin is an anti-pattern for readability).
The neo-tree replacement rationale correctly leverages the "config hasn't been used" context.
The telescope replacement argument about avoiding dual-finder confusion is practical.

### Edge Cases

**[blocking]** The `bufferline offset filetype` edge case identifies the need to change from `neo-tree` to the snacks explorer filetype.
The proposal says "Verify the correct filetype string via `:set ft?` when the explorer is open (likely `snacks_explorer` or similar)."
This is an implementation-time verification, which is fine for a proposal.
However, the proposal should explicitly note that this is a Phase 2 task (when explorer is enabled), not Phase 4.
Currently the bufferline offset change is listed in Phase 2's changes, so this is consistent.
Downgrading to non-blocking since the Phase 2 changes list does cover it.

**[non-blocking]** The `plenary.nvim` edge case is well-identified.
The proposal correctly notes that todo-comments lists plenary as a dependency and suggests verifying at implementation time.
In practice, `todo-comments.nvim` does require plenary (it uses `plenary.job` for ripgrep calls), so plenary should be kept as a todo-comments dependency.

**[non-blocking]** Missing edge case: the `colorscheme.lua` file sets NeoTree-specific highlight groups (`NeoTreeGitAdded`, `NeoTreeGitModified`, `NeoTreeGitUntracked`, `NeoTreeGitDeleted`).
After removing neo-tree, these highlight groups become dead code.
The proposal should note that `colorscheme.lua` needs cleanup to remove the NeoTree highlight overrides, and optionally add equivalent highlights for snacks.explorer if it uses different highlight groups.

### Test Plan

**[non-blocking]** The test plan is reasonable but lacks a regression check for the JSONL logger under error conditions.
What happens when the log file's parent directory does not exist?
`vim.fn.stdpath("log")` should always exist, but a defensive `vim.fn.mkdir(vim.fn.stdpath("log"), "p")` call before the first write would be safer.
This is an implementation detail more than a proposal concern.

**[non-blocking]** The test plan does not mention verifying that `vim.ui.select` (used by LSP code actions, for example) works correctly with the snacks picker's `ui_select` after dressing.nvim is removed.
This is an important user-facing behavior: `<leader>ca` (code action) uses `vim.ui.select` under the hood.
Add a test step to Phase 4 verifying that code actions still present a picker float.

### Implementation Phases

**[non-blocking]** Phase 1 enables `statuscolumn`, which renders git signs, fold indicators, and line numbers.
The current config has `signcolumn = "yes"` in `init.lua:46`.
The proposal should note whether `snacks.statuscolumn` replaces the built-in signcolumn or layers on top.
In practice, `snacks.statuscolumn` replaces the built-in `statuscolumn` option entirely (it sets `vim.o.statuscolumn` to a custom function).
The `signcolumn = "yes"` setting may become redundant or conflict.
This is not blocking since statuscolumn is a zero-config module and any visual issues are immediately apparent.

**[non-blocking]** Phase 3 (Dashboard) references "session restore action should call persistence.nvim's `load()` function."
The current persistence.nvim config (`editor.lua:65`) uses `event = "BufReadPre"` for lazy loading.
If the dashboard is shown on startup (no file argument), `BufReadPre` never fires, so persistence.nvim will not be loaded when the dashboard's session-restore button is pressed.
The dashboard action will need to explicitly `require("persistence").load()` which will trigger lazy.nvim to load the plugin on demand (since lazy.nvim intercepts `require` calls for managed plugins).
This should work, but the proposal should note that the dashboard session-restore action depends on lazy.nvim's `require`-based auto-loading, not the `BufReadPre` event.

**[non-blocking]** Phase 4 says to enable `bufdelete` module and remap `<leader>bd`.
The current `<leader>bd` binding is in `init.lua:93`, not in any plugin file.
The proposal's "Modified files" section in Architecture does not list `init.lua` for the `<leader>bd` change (it only mentions JSONL logger and netrw disabling).
The `init.lua` keymap line should be removed when the snacks.lua keybinding for `<leader>bd` is added, or it will shadow the snacks version.

## Missed Opportunities

**[non-blocking]** The proposal does not discuss `snacks.rename`, which provides LSP-aware file rename (updates imports when a file is renamed in the explorer).
Since the proposal adopts `snacks.explorer`, enabling `snacks.rename` would be a natural complement.
This is a zero-config module.

**[non-blocking]** The proposal does not discuss `snacks.git`, which provides a `Snacks.git.blame_line()` utility.
This overlaps with gitsigns.nvim's blame, but mentioning the skip decision would be consistent with the "Modules to Skip" section's thoroughness.

**[non-blocking]** The `snacks.notifier` filter function in the BLUF and the notification design decision uses pattern matching on `notif.msg`.
The actual snacks.notifier filter function receives a notification object.
The proposal should verify the correct field name (it may be `notif.msg` or `notif.message` depending on snacks version).
Checking the snacks source at implementation time is sufficient.

## Verdict

**Revise.**

The proposal is well-researched and architecturally sound.
The phased approach is the right strategy, and the keybinding migration table is thorough.
However, two keybinding conflicts (`<leader>e` diagnostic vs. explorer, `<leader>n` timeout due to `<leader>nh`/`<leader>nd` continuations) will cause real usability problems if not resolved before implementation.
The frontmatter also needs correction per project rules.

Resolve the blocking items and this is ready to accept.

## Action Items

1. [blocking] Fix frontmatter: add `@` prefix to `first_authored.by`, add `title` field.
2. [blocking] Resolve `<leader>e` conflict between `Snacks.explorer()` (proposed) and `vim.diagnostic.open_float` (existing in `lsp.lua:59`). Pick one of the three resolution options outlined in the findings.
3. [blocking] Resolve `<leader>n` / `<leader>nh` / `<leader>nd` namespace collision causing 300ms delay on explorer toggle. Move notification bindings to a non-conflicting prefix.
4. [non-blocking] Correct the `netrw` disabled plugin name to `netrwPlugin` in the Architecture section.
5. [non-blocking] Fix plenary.nvim table entry: change "no remaining consumers" to "reduced to single consumer (todo-comments)."
6. [non-blocking] Add a note about NeoTree highlight group cleanup in `colorscheme.lua` after neo-tree removal.
7. [non-blocking] Add `vim.ui.select` verification (code actions via `<leader>ca`) to Phase 4 test criteria.
8. [non-blocking] Note that `init.lua:93` (`<leader>bd` keymap) must be removed when snacks.bufdelete takes over in Phase 4, and add `init.lua` to the Architecture "Modified files" list for this change.
9. [non-blocking] Consider enabling `snacks.rename` alongside `snacks.explorer` for LSP-aware file renames.
10. [non-blocking] Acknowledge the pre-existing `<leader>f` conflict (LSP format vs. find group) and consider recommending a fix as part of this migration.

## Questions for the Author

The following questions surfaced during review.
Each has a recommended default; select the option that matches your preference or suggest an alternative.

**Q1: How should the `<leader>e` conflict be resolved?**
- (a) Move explorer-reveal to `<leader>E` (keep `<leader>e` for diagnostic float) -- **recommended**
- (b) Move diagnostic float to `<leader>cd` and keep `<leader>e` for explorer
- (c) Drop the explorer-reveal binding entirely; configure snacks.explorer to auto-reveal on toggle

**Q2: Where should notification keybindings live?**
- (a) `<leader>sn` prefix (`<leader>snh` for history, `<leader>snd` for dismiss) -- snacks namespace -- **recommended**
- (b) `<leader>un` prefix (`<leader>unh`, `<leader>und`) -- ui namespace
- (c) Use standalone bindings with no shared prefix (e.g., `<leader>nh` becomes `<leader>Nh`, `<leader>nd` becomes `<leader>Nd`)

**Q3: Should `<leader>f` (LSP format) be relocated as part of this migration?**
- (a) Yes, move to `<leader>cf` (code format) so `<leader>f` group works for finders -- **recommended**
- (b) No, leave the conflict as-is; it predates this proposal and can be fixed separately
- (c) Remove `<leader>f` format entirely; use `:Format` command or format-on-save instead

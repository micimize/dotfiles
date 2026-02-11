---
title: "Adopt snacks.nvim as Core UI Layer"
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T00:00:00-05:00
task_list: neovim/snacks-migration
type: proposal
state: live
status: implementation_wip
tags: [neovim, snacks-nvim, plugin-migration, ui, notifications, dashboard, picker, keybindings]
last_reviewed:
  status: revision_requested
  by: "@claude-opus-4-6"
  at: 2026-02-11T12:00:00-05:00
  round: 1
---

# Adopt snacks.nvim as Core UI Layer

> BLUF: Replace 8 plugins (nvim-notify, indent-blankline, dressing.nvim, telescope.nvim, telescope-fzf-native, neo-tree, plenary.nvim, nui.nvim) with `folke/snacks.nvim` and add 5 previously absent capabilities (dashboard, bigfile handling, fast file rendering, buffer deletion, LSP-aware file rename). Adopt in 4 phases: zero-config wins first, then notification/indent/explorer replacements, then the dashboard, and finally the picker migration (largest change). Reorganize diagnostic bindings around `ge` (float), `gne`/`gpe` (next/prev), replace `<leader>f` format with a `:Format` command and format-on-save autocmd, freeing `<leader>e`/`<leader>E` for the explorer and `<leader>f` for finders; `<leader>n` becomes the notifications namespace. Keep lualine, bufferline, which-key, and the entire LSP/editor/git stack unchanged -- snacks has no equivalents for these. Pair snacks.notifier with a `vim.notify` JSONL file logger from the [UX research report](../reports/2026-02-11-neovim-transition-ux-research.md) to solve the "errors disappear before I can read them" problem.

## Objective

Consolidate the neovim UI layer around `folke/snacks.nvim`, reducing plugin count and gaining capabilities that address the three friction points identified in the UX research report: ephemeral errors, invasive toasts, and a bare landing page. The broader goal is to align with the direction the ecosystem is headed -- snacks.nvim is now the default UI layer in LazyVim and is rapidly replacing the standalone plugins this config currently uses.

## Background

### Current Plugin Inventory (UI-relevant)

| Plugin | Role | File | snacks equivalent? |
|---|---|---|---|
| nvim-notify | Toast notifications | `ui.lua:141-157` | **Yes** -- `snacks.notifier` |
| indent-blankline.nvim | Indent guides | `ui.lua:119-131` | **Yes** -- `snacks.indent` |
| dressing.nvim | Better `vim.ui.select`/`vim.ui.input` | `ui.lua:133-138` | **Yes** -- `snacks.input` + `snacks.picker` (ui_select) |
| telescope.nvim | Fuzzy finder | `telescope.lua` (81 lines) | **Yes** -- `snacks.picker` |
| telescope-fzf-native | FZF algorithm for telescope | `telescope.lua:8-14` | **Yes** -- built into picker |
| neo-tree.nvim | File explorer | `ui.lua:4-42` | **Yes** -- `snacks.explorer` |
| plenary.nvim | Utility library | telescope/neo-tree dep | **Reduced** -- single remaining consumer (todo-comments) |
| nui.nvim | UI component library | neo-tree dep | **Removed** -- no remaining consumers |
| bufferline.nvim | Buffer tab bar | `ui.lua:44-71` | **No** -- snacks has no bufferline |
| lualine.nvim | Statusline | `ui.lua:74-93` | **No** -- snacks has no statusline |
| which-key.nvim | Keybinding hints | `ui.lua:96-117` | **No** -- complementary via `snacks.toggle` |

### What snacks.nvim Is

A modular plugin collection by folke (same author as lazy.nvim, which-key, flash.nvim). Each module is internally lazy-loaded via metatables -- despite the plugin loading eagerly at `priority = 1000`, individual modules only initialize when their trigger event fires or when first accessed. As of late 2025, LazyVim ships snacks as its core UI dependency, and AstroNvim v5 adopted it as well.

### Reference Material

- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) -- source and module docs
- [UX Research Report](../reports/2026-02-11-neovim-transition-ux-research.md) -- findings on notification/logging/dashboard needs
- [Integrating Snacks.nvim (Andrew Courter, LevelUp)](https://levelup.gitconnected.com/integrating-snacks-nvim-in-your-neovim-configuration-0b341b41580c) -- gradual adoption approach (paywalled, key thesis: adopt incrementally, most impactful modules first)
- [Why I'm Moving from Telescope to Snacks Picker (linkarzu)](https://linkarzu.com/posts/neovim/snacks-picker/) -- telescope-to-picker migration walkthrough

## Proposed Solution

### Architecture

Add a single `lua/plugins/snacks.lua` file containing the `folke/snacks.nvim` plugin spec. Remove replaced plugins from their current files. Modify `init.lua` to add the JSONL notify logger after plugin setup.

**New file:** `lua/plugins/snacks.lua` -- all snacks configuration in one place.

**Modified files:**
- `lua/plugins/ui.lua` -- remove nvim-notify, indent-blankline, dressing.nvim, neo-tree
- `lua/plugins/telescope.lua` -- remove entirely (replaced by snacks.picker)
- `lua/plugins/editor.lua` -- update todo-comments `<leader>ft` binding (was `TodoTelescope`, becomes `Snacks.picker.todo_comments`)
- `lua/plugins/lsp.lua` -- relocate `<leader>e` diagnostic float → `ge`, `ge`/`gE` next/prev → `gne`/`gpe`, replace `<leader>f` format with `:Format` command + `BufWritePre` format-on-save autocmd, add `<leader>tf` toggle for auto-format
- `lua/plugins/colorscheme.lua` -- remove NeoTree-specific highlight group overrides (dead code after neo-tree removal)
- `init.lua` -- add JSONL notify logger, add `netrwPlugin` to disabled plugins list, remove `<leader>bd` keymap (moved to snacks.lua)

**Unchanged files:** `git.lua`, `treesitter.lua`

### Module Adoption Map

#### Modules to Enable

| Module | What it does | Replaces | Config needed? |
|---|---|---|---|
| `notifier` | Toast notifications with history | nvim-notify | Yes -- bottom-anchored, compact style, filter function |
| `indent` | Indent guides with animated scope | indent-blankline.nvim | Minimal -- char and scope settings |
| `input` | Better `vim.ui.input` | dressing.nvim | No |
| `picker` | Fuzzy finder with 40+ sources | telescope.nvim + fzf-native | Yes -- keybindings, layout, hidden files |
| `dashboard` | Startup screen | *(none -- new capability)* | Yes -- sections, session integration |
| `bigfile` | Disables heavy features for large files | *(none -- new capability)* | No |
| `quickfile` | Renders files before plugins finish loading | *(none -- new capability)* | No |
| `bufdelete` | Delete buffers without disrupting layout | *(none -- improves `<leader>bd`)* | No |
| `scope` | Treesitter scope text objects (`ii`/`ai`) | *(replaces need for nvim-treesitter-textobjects scope feature)* | No |
| `words` | Auto-highlight LSP references | *(none -- new capability)* | Minimal |
| `toggle` | Toggle keymaps with which-key integration | *(none -- new capability)* | Minimal |
| `statuscolumn` | Pretty status column with signs, folds, git | *(none -- new capability)* | Minimal |
| `explorer` | File explorer sidebar | neo-tree.nvim (+ plenary, nui.nvim) | Yes -- keybindings, hidden files |
| `rename` | LSP-aware file rename | *(none -- new capability)* | No -- complements explorer |

#### Modules to Skip

| Module | Why skip |
|---|---|
| `scroll` | Smooth scrolling is polarizing; not a current pain point |
| `lazygit` | No indication user uses lazygit |
| `image` | WezTerm has limited support (no inline rendering) |
| `zen` / `dim` | Not a current pain point; can add later |
| `terminal` | No current terminal plugin; not requested |
| `git` | gitsigns.nvim already covers blame; no added value |
| `gh` | GitHub CLI integration; tangential to current goals |

### JSONL Notify Logger

The notify logger from the research report pairs with snacks.notifier. It wraps `vim.notify` to write JSONL to `vim.fn.stdpath("log") .. "/notify.jsonl"` (typically `~/.local/state/nvim/notify.jsonl` on XDG-compliant Linux; varies on macOS) before passing through to whatever visual backend is active. This must be set up in `init.lua` via a `VeryLazy` autocmd so it runs after snacks.notifier has replaced `vim.notify`:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local log_path = vim.fn.stdpath("log") .. "/notify.jsonl"
    local visual_notify = vim.notify
    vim.notify = function(msg, level, opts)
      local file = io.open(log_path, "a")
      if file then
        local ok, entry = pcall(vim.json.encode, {
          t = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          l = level or 2,
          m = msg,
          s = opts and opts.title or nil,
        })
        if ok then file:write(entry .. "\n") end
        file:close()
      end
      return visual_notify(msg, level, opts)
    end
  end,
})
```

### Keybinding Migration

All existing keybindings transfer to snacks equivalents. Two LSP bindings are relocated to resolve namespace conflicts (see Design Decisions below).

| Current binding | Current plugin | New binding | New implementation |
|---|---|---|---|
| `<C-Space>` | `telescope.builtin.find_files` | `<C-Space>` | `Snacks.picker.files` |
| `<C-S-Space>` | `telescope.builtin.commands` | `<C-S-Space>` | `Snacks.picker.commands` |
| `<C-s>` | `telescope.builtin.find_files` | `<C-s>` | `Snacks.picker.files` |
| `<leader>ff` | `telescope.builtin.find_files` | `<leader>ff` | `Snacks.picker.files` |
| `<leader>fg` | `telescope.builtin.live_grep` | `<leader>fg` | `Snacks.picker.grep` |
| `<leader>fb` | `telescope.builtin.buffers` | `<leader>fb` | `Snacks.picker.buffers` |
| `<leader>fh` | `telescope.builtin.help_tags` | `<leader>fh` | `Snacks.picker.help` |
| `<leader>fr` | `telescope.builtin.oldfiles` | `<leader>fr` | `Snacks.picker.recent` |
| `<leader>fc` | `telescope.builtin.commands` | `<leader>fc` | `Snacks.picker.commands` |
| `<leader>fs` | `telescope.builtin.lsp_document_symbols` | `<leader>fs` | `Snacks.picker.lsp_symbols` |
| `<leader>fS` | `telescope.builtin.lsp_workspace_symbols` | `<leader>fS` | `Snacks.picker.lsp_workspace_symbols` |
| `<leader>gc` | `telescope.builtin.git_commits` | `<leader>gc` | `Snacks.picker.git_log` |
| `<leader>gs` | `telescope.builtin.git_status` | `<leader>gs` | `Snacks.picker.git_status` |
| `<leader>fw` | `telescope.builtin.grep_string` | `<leader>fw` | `Snacks.picker.grep_word` |
| `<leader>ft` | `TodoTelescope` | `<leader>ft` | `Snacks.picker.todo_comments` |
| `<leader>bd` | `:bdelete` (init.lua) | `<leader>bd` | `Snacks.bufdelete()` |
| `<leader>e` | `Neotree reveal` | `<leader>e` | `Snacks.explorer()` (reveal current file) |
| `<leader>n` | `Neotree toggle` | **`<leader>E`** | `Snacks.explorer()` (unfocused toggle) |
| `<leader>e` | `vim.diagnostic.open_float` (lsp.lua) | **`ge`** | `vim.diagnostic.open_float` (relocated, "go error") |
| `ge` | `vim.diagnostic.goto_next` (lsp.lua) | **`gne`** | `vim.diagnostic.goto_next` (relocated, "go next error") |
| `gE` | `vim.diagnostic.goto_prev` (lsp.lua) | **`gpe`** | `vim.diagnostic.goto_prev` (relocated, "go prev error") |
| `<leader>f` | `vim.lsp.buf.format` (lsp.lua) | **removed** | `:Format` command + format-on-save autocmd |
| *(new)* | -- | `<leader>nh` | `Snacks.notifier.show_history()` |
| *(new)* | -- | `<leader>nd` | `Snacks.notifier.hide()` |

## Important Design Decisions

### Decision: Single `snacks.lua` File vs Distributed Config

**Decision:** All snacks configuration in one `lua/plugins/snacks.lua` file.

**Why:** snacks.nvim is a single plugin with a single `opts` table. Splitting its config across files (notifier in `ui.lua`, picker in a separate file) would mean multiple lazy.nvim specs for the same plugin that get merged -- this works but is harder to reason about. A single file mirrors how the plugin is structured and makes it easy to see the full snacks surface area at a glance.

### Decision: Replace neo-tree With snacks.explorer

**Decision:** Remove neo-tree.nvim (and its dependencies plenary.nvim, nui.nvim) in favor of `snacks.explorer` + `snacks.rename`.

**Why:** The neovim config hasn't been used in production -- there's no attachment to neo-tree's specific features or keymaps. snacks.explorer covers the core file-browsing workflow (open, create, delete, move, copy, toggle hidden) and eliminates 3 plugins (neo-tree, plenary, nui.nvim). `<leader>e` transfers directly (reveal); `<leader>n` (toggle) moves to `<leader>E` to free the `<leader>n` namespace for notifications. snacks.explorer also integrates naturally with snacks.picker for file searching within the tree. `snacks.rename` complements the explorer by notifying LSP servers when files are renamed (updating imports automatically).

### Decision: Reorganize Diagnostic Bindings Around `ge`

**Decision:** Move `vim.diagnostic.open_float` from `<leader>e` to `ge` ("go error"). Move next/prev diagnostic from `ge`/`gE` to `gne`/`gpe` ("go next/prev error").

**Why:** `<leader>e` is needed for `Snacks.explorer()` (reveal current file). The existing LSP binding in `lsp.lua:59` is buffer-local and would silently shadow the global explorer binding in any buffer with an attached language server. `ge` for the diagnostic float is the most intuitive mapping ("go error" to see the error detail). The previous `ge`/`gE` next/prev navigation moves to `gne`/`gpe`, which follows the config's `g`-prefix convention and is self-documenting.

### Decision: Replace `<leader>f` Format With `:Format` Command and Format-on-Save

**Decision:** Remove the `<leader>f` format keybinding. Add a `:Format` user command and a `BufWritePre` autocmd for automatic format-on-save.

**Why:** `<leader>f` is the which-key group prefix for all finder bindings (`<leader>ff`, `<leader>fg`, `<leader>fb`, etc.). The current LSP format binding on `<leader>f` is buffer-local and shadows the entire find group in LSP-attached buffers -- pressing `<leader>f` triggers format immediately instead of showing the which-key popup. Replacing the keybinding with format-on-save is the better UX anyway: formatting should happen automatically, and the `:Format` command is available for the rare manual invocation. A `<leader>tf` toggle binding (via `snacks.toggle`) allows disabling auto-format per-buffer when needed.

### Decision: Explorer on `<leader>e`/`<leader>E`, Notifications on `<leader>n`

**Decision:** `<leader>e` reveals the explorer at the current file (focused), `<leader>E` toggles the explorer (unfocused). `<leader>n` becomes the notifications namespace: `<leader>nh` (history), `<leader>nd` (dismiss).

**Why:** `<leader>e` for explorer-reveal matches the existing neo-tree binding and is intuitive ("e for explorer"). `<leader>E` for the unfocused toggle avoids the namespace collision with notifications. `<leader>n` for notifications is memorable ("n for notifications") and the `nh`/`nd` suffixes are self-explanatory.

### Decision: Keep lualine and bufferline

**Decision:** Keep both statusline and bufferline plugins unchanged.

**Why:** snacks.nvim has no statusline module and no bufferline/tabline module. The `statuscolumn` module handles the *sign column* (gutter), not the statusline. These plugins remain necessary.

### Decision: Replace telescope.nvim With snacks.picker

**Decision:** Replace telescope entirely rather than keeping both.

**Why:** Running both creates confusion about which finder is active for each binding. snacks.picker has a `telescope` layout preset that mimics the familiar UI, built-in frecency boosting, and native `ui_select` support (replacing the dressing.nvim half that handles `vim.ui.select`). The migration is the largest single change in this proposal, which is why it's the final phase.

### Decision: Bottom-Anchored, Compact Notifications With Deprecation Filtering

**Decision:** Configure snacks.notifier with `top_down = false`, `style = "compact"`, and a filter function that suppresses known noisy deprecation toasts.

**Why:** The user's primary complaint is invasive upper-right toasts that vanish before content can be read. Bottom-anchored notifications are less disruptive (they don't cover code). Compact style reduces visual weight. The filter suppresses the treesitter/mason deprecation warnings that are the most common noise source. Filtered messages still hit the JSONL log and can be reviewed via `Snacks.notifier.show_history()`.

### Decision: JSONL Logger Wraps vim.notify After Plugin Setup

**Decision:** The file logger intercepts `vim.notify` via a `VeryLazy` autocmd, capturing the reference to snacks.notifier's replacement and wrapping it.

**Why:** snacks.notifier replaces `vim.notify` during its setup. The logger must run *after* this replacement so it captures the snacks-backed function as `visual_notify`. The `User VeryLazy` event fires after all lazy-loaded plugins initialize, guaranteeing correct ordering. This means the call chain is: `vim.notify` → JSONL write → snacks.notifier → visual toast.

## Edge Cases / Challenging Scenarios

### statuscolumn and gitsigns Coexistence

`snacks.statuscolumn` replaces the built-in `statuscolumn` option entirely (it sets `vim.o.statuscolumn` to a custom function). It reads from whatever signs other plugins place in the sign column, so it is complementary to `gitsigns.nvim` -- not competing. The `signcolumn = "yes"` setting in `init.lua:46` may become redundant once statuscolumn is active, but it causes no harm and can be cleaned up later.

### NeoTree Highlight Group Cleanup

`colorscheme.lua` sets NeoTree-specific highlight groups (`NeoTreeGitAdded`, `NeoTreeGitModified`, etc.). After removing neo-tree, these become dead code. Remove them in Phase 2 when neo-tree is removed, and optionally add equivalent snacks.explorer highlights if needed (verify at implementation time whether snacks.explorer uses different highlight groups or inherits from standard groups).

### todo-comments Integration

`todo-comments.nvim` currently uses `<leader>ft` mapped to `TodoTelescope`. snacks.picker has a built-in `todo_comments` source that works with the same underlying plugin. The binding changes from a command string to a function call. If todo-comments.nvim is not loaded when the picker is invoked, snacks shows an informative error rather than silently failing.

### plenary.nvim Dependency

Both telescope and neo-tree depend on `plenary.nvim`. With both removed, the only remaining consumer is todo-comments.nvim, which lists plenary as a dependency. Verify at implementation time whether todo-comments actually requires plenary at runtime -- if so, keep it as a todo-comments dependency rather than a top-level plugin. If not, remove it entirely.

### Config Array Merging Gotcha

snacks.nvim replaces array-like tables entirely rather than merging them. If a `keys` table is specified in the plugin spec, it replaces the module's default keys, not appends. All keybindings must be explicitly listed in the spec.

### Picker `hidden` and `ignored` Files

Telescope is currently configured with `hidden = true` for `find_files` and `--hidden` for `live_grep`. snacks.picker equivalent: set `hidden = true` in the picker source config. Verify `.gitignore`d files are still excluded (snacks respects `.gitignore` by default even with `hidden = true`).

### bufferline Offset for snacks.explorer

The bufferline config currently has an offset for the neo-tree sidebar filetype. This must be updated to use the snacks explorer filetype instead. Verify the correct filetype string via `:set ft?` when the explorer is open (likely `snacks_explorer` or similar).

### lazy-lock.json Churn

Removing 8 plugins and adding 1 will produce a large diff in `lazy-lock.json`. This is expected and unavoidable.

## Test Plan

Each phase has its own verification steps. The overarching validation approach:

1. **Before each phase:** Record baseline key behavior (open nvim, check notifications work, check finder works, check indent guides render).
2. **After each phase:** Verify the same behaviors work with the new implementation.
3. **`:checkhealth snacks`** after every phase to verify module health.
4. **Tail the JSONL log** (`~/.local/state/nvim/notify.jsonl`) to confirm logging works.
5. **Open nvim with no arguments** to verify dashboard renders (Phase 3).
6. **Open a large file** (>1.5MB) to verify bigfile module disables heavy features (Phase 1).
7. **Trigger `vim.ui.select`** via `<leader>ca` (code action) in an LSP-attached buffer to verify picker handles it (Phase 4).
8. **Verify `<leader>f` group** shows which-key popup in LSP-attached buffers (no longer shadowed by format binding) (Phase 2).
9. **Verify format-on-save** triggers when saving a file with an LSP attached, and `<leader>tf` disables it (Phase 2).

## Implementation Phases

### Phase 1: Zero-Config Foundations

**Goal:** Add snacks.nvim with modules that require no configuration and conflict with nothing.

**Changes:**
- Create `lua/plugins/snacks.lua` with the plugin spec
- Enable: `bigfile`, `quickfile`, `scope`, `words`, `statuscolumn`
- No plugins removed in this phase

**Success criteria:**
- `:checkhealth snacks` passes
- Opening a >1.5MB file shows the bigfile notification and disables treesitter/LSP for that buffer
- `ii`/`ai` text objects select the current scope
- LSP references auto-highlight when cursor rests on a symbol
- Status column shows fold indicators and git signs

**Constraints:** Do not modify any existing plugin config. snacks.lua is purely additive.

### Phase 2: Notification, Indent, Input, and Explorer Replacement

**Goal:** Replace nvim-notify, indent-blankline, dressing.nvim, and neo-tree with snacks equivalents. Add the JSONL notify logger. Fix keybinding namespace conflicts.

**Changes:**
- Enable in snacks.lua: `notifier` (bottom-anchored, compact, filtered), `indent`, `input`, `explorer`, `rename`, `toggle`
- Remove from `ui.lua`: nvim-notify spec, indent-blankline spec, dressing.nvim spec, neo-tree spec (and its plenary/nui.nvim dependencies)
- Update `ui.lua`: bufferline offset filetype from `neo-tree` to snacks explorer filetype
- Update `colorscheme.lua`: remove NeoTree-specific highlight group overrides
- Update `lsp.lua`: relocate `<leader>e` → `ge` (diagnostic float), `ge`/`gE` → `gne`/`gpe` (next/prev diagnostic), remove `<leader>f` (format), add `:Format` command + `BufWritePre` format-on-save autocmd + `<leader>tf` toggle for auto-format
- Add to `init.lua`: JSONL notify logger (`VeryLazy` autocmd)
- Add keybindings: `<leader>nh` (notification history), `<leader>nd` (dismiss notifications)
- Remap `<leader>e` to explorer reveal, `<leader>E` to explorer toggle (was `<leader>n` in neo-tree)
- Add which-key group: `<leader>n` → "notifications"
- Configure toggles for diagnostics, inlay hints, treesitter, words

**Success criteria:**
- `<leader>E` toggles the file explorer sidebar
- `<leader>e` opens the explorer at the current file's location (even in LSP-attached buffers)
- `ge` opens diagnostic float (relocated from `<leader>e`), `gne`/`gpe` navigate next/prev diagnostic
- Saving a buffer auto-formats it via LSP; `:Format` works for manual invocation
- `<leader>tf` toggles auto-format on/off for the current buffer
- Explorer shows hidden files, responds to `h`/`l` for collapse/expand
- Notifications appear at the bottom of the screen in compact style
- `<leader>nh` opens notification history showing past notifications
- Known deprecation toasts (treesitter rewrite, etc.) are suppressed visually but appear in the JSONL log
- `vim.fn.stdpath("log") .. "/notify.jsonl"` contains JSON entries for every `vim.notify` call
- Indent guides render with scope highlighting
- `vim.ui.input` prompts use the snacks float instead of the cmdline

**Constraints:** Do not touch telescope, picker, or any finder bindings yet.

### Phase 3: Dashboard

**Goal:** Add a startup screen that surfaces recent files, projects, and session restore.

**Changes:**
- Enable in snacks.lua: `dashboard` with sections for header, quick-action keys, recent files, projects, and startup time
- Dashboard keys should include: find file, live grep, recent files, restore session, lazy plugin manager, quit
- Session restore action should call `require("persistence").load()` -- this triggers lazy.nvim's `require`-based auto-loading since persistence.nvim's `BufReadPre` event won't fire on the dashboard (no file buffer)

**Success criteria:**
- `nvim` with no arguments shows the dashboard
- Dashboard displays recent files and projects
- Pressing the session-restore key restores the last session for the current directory
- Dashboard disappears when opening a file or buffer
- Dashboard does not interfere with `nvim somefile.lua` (direct file open)

**Constraints:** Do not change persistence.nvim config. The dashboard calls into it, not the other way around.

### Phase 4: Picker Migration (Telescope Replacement)

**Goal:** Replace telescope.nvim and telescope-fzf-native with snacks.picker. This is the largest change and should be done as a standalone commit.

**Changes:**
- Enable in snacks.lua: `picker` with layout, hidden files, frecency, `ui_select = true`, `bufdelete`
- Port all keybindings from `telescope.lua` to snacks.picker equivalents (see Keybinding Migration table)
- Delete `lua/plugins/telescope.lua` entirely
- Update `editor.lua`: change todo-comments `<leader>ft` from `TodoTelescope` to `Snacks.picker.todo_comments()`
- Update `init.lua`: remove `<leader>bd` keymap (line 93, replaced by snacks.bufdelete in snacks.lua), add `netrwPlugin` to lazy.nvim `disabled_plugins` (the actual plugin filename is `netrwPlugin.vim`; using `netrw` would be a silent no-op)
- Picker insert-mode mappings: `<C-j>`/`<C-k>` for navigation, `<Esc>` to close, `<C-q>` to send to quickfix (matching current telescope muscle memory)

**Success criteria:**
- All keybindings in the migration table work and produce equivalent results
- `<C-Space>` opens file finder with hidden files visible
- `<C-S-Space>` opens command palette
- `<leader>fg` opens live grep with hidden file search
- `<leader>ft` opens todo-comments picker
- `vim.ui.select` uses snacks picker float -- verify with `<leader>ca` (code action) in an LSP-attached buffer
- `<leader>bd` closes buffer without disrupting window layout
- No telescope references remain in any config file
- `:checkhealth snacks` still passes

**Constraints:**
- Do not change any LSP keybindings (`gd`, `gr`, etc.) -- these use `vim.lsp.buf` directly, not telescope (the `<leader>e`/`<leader>f` relocations were already done in Phase 2)
- Do not change git plugin keybindings (`<leader>gg`, `<leader>gb`, etc.) -- these use fugitive/diffview directly
- Preserve `<C-j>`/`<C-k>` navigation in picker insert mode to match current telescope muscle memory

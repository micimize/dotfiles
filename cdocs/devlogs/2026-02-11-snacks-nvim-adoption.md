---
title: "snacks.nvim Adoption Implementation"
date: 2026-02-11
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T00:00:00-05:00
task_list: neovim/snacks-migration
type: devlog
state: live
status: review_ready
tags: [neovim, snacks-nvim, plugin-migration, handoff]
last_reviewed:
  status: revision_requested
  by: "@claude-opus-4-6"
  at: 2026-02-11T22:30:00-05:00
  round: 1
---

# snacks.nvim Adoption: Handoff Devlog

## Objective

Implement the accepted proposal at `cdocs/proposals/2026-02-11-snacks-nvim-adoption.md` -- replace 8 neovim plugins with `folke/snacks.nvim`, add a JSONL notify logger, set up format-on-save, and reorganize keybindings to resolve namespace conflicts. 4 phases, each independently committable.

## Key Context

- This is a **chezmoi-managed dotfiles repo**. Edit source files under `dot_config/nvim/`, then `chezmoi apply` to deploy.
- The neovim config has **never been used in production** -- no attachment to any current plugin or binding.
- The proposal went through research, drafting, review (with blocking findings), and revision. All blocking items are resolved.

## Essential Reading

Read these before starting implementation:

1. **The proposal** (authoritative): `cdocs/proposals/2026-02-11-snacks-nvim-adoption.md`
   - Module adoption map, keybinding migration table, design decisions, edge cases, phase-by-phase changes and success criteria
2. **The research report** (background): `cdocs/reports/2026-02-11-neovim-transition-ux-research.md`
   - JSONL logger snippet, notification filter patterns, dashboard section config
3. **The review** (resolved issues): `cdocs/reviews/2026-02-11-snacks-nvim-adoption-review.md`
   - Documents the keybinding conflicts that were found and how they were resolved

## Current Config Layout

```
dot_config/nvim/
  init.lua              -- bootstrap, core settings, basic keymaps, lazy.nvim setup
  lua/plugins/
    ui.lua              -- neo-tree, bufferline, lualine, which-key, indent-blankline, dressing, nvim-notify
    telescope.lua       -- telescope + fzf-native (entire file deleted in Phase 4)
    editor.lua          -- autopairs, surround, comment, better-escape, flash, todo-comments, persistence
    lsp.lua             -- mason, lspconfig, nvim-cmp (diagnostic/format bindings modified in Phase 2)
    git.lua             -- gitsigns, fugitive, diffview (unchanged)
    colorscheme.lua     -- solarized + NeoTree highlights (NeoTree highlights removed in Phase 2)
    treesitter.lua      -- (unchanged)
```

## Plan

Follow the 4 phases exactly as specified in the proposal. Each phase is one commit.

### Phase 1: Zero-Config Foundations
- Create `lua/plugins/snacks.lua` with `bigfile`, `quickfile`, `scope`, `words`, `statuscolumn`
- Purely additive -- no existing files modified
- Verify: `:checkhealth snacks`, `ii`/`ai` text objects, LSP reference highlighting

### Phase 2: Notification, Indent, Input, Explorer Replacement
- Biggest phase. Enable `notifier`, `indent`, `input`, `explorer`, `rename`, `toggle` in snacks.lua
- Remove from `ui.lua`: nvim-notify, indent-blankline, dressing, neo-tree (and deps)
- Update `ui.lua`: bufferline offset filetype for snacks explorer
- Update `colorscheme.lua`: remove NeoTree highlight overrides
- Update `lsp.lua`: `<leader>e` → `ge`, `ge`/`gE` → `gne`/`gpe`, remove `<leader>f` format, add `:Format` + format-on-save + `<leader>tf` toggle
- Add to `init.lua`: JSONL notify logger (VeryLazy autocmd)
- Add keybindings: `<leader>e` explorer reveal, `<leader>E` explorer toggle, `<leader>nh` history, `<leader>nd` dismiss

### Phase 3: Dashboard
- Enable `dashboard` in snacks.lua with sections: header, keys, recent_files, projects, startup
- Session restore calls `require("persistence").load()` (lazy.nvim auto-loads it)

### Phase 4: Picker Migration
- Enable `picker` (with `ui_select = true`) and `bufdelete` in snacks.lua
- Delete `telescope.lua` entirely
- Update `editor.lua`: todo-comments `<leader>ft` → `Snacks.picker.todo_comments()`
- Update `init.lua`: remove `<leader>bd` keymap (line 93), add `netrwPlugin` to disabled_plugins
- Port all telescope keybindings to snacks.picker equivalents per the migration table

## Testing Approach

Each phase verified before committing:
1. `:checkhealth snacks`
2. Exercise the keybindings listed in that phase's success criteria
3. Check JSONL log exists and has entries (Phase 2+)
4. Open nvim with no args to verify dashboard (Phase 3)
5. Verify `vim.ui.select` via `<leader>ca` code action (Phase 4)

## Gotchas to Watch For

- **snacks array merging**: `keys` tables in the plugin spec _replace_ defaults, not append. List all bindings explicitly.
- **Picker hidden files**: set `hidden = true` in picker config to match current telescope behavior.
- **`netrwPlugin`** not `netrw` in `disabled_plugins` -- the wrong name is a silent no-op.
- **todo-comments needs plenary** at runtime -- keep plenary as its dependency, don't remove it entirely.
- **Notifier filter field**: verify whether it's `notif.msg` or `notif.message` in the snacks version you install.
- **Explorer filetype for bufferline offset**: check via `:set ft?` when explorer is open.

## Changes Made

| File | Description |
|------|-------------|
| `dot_config/nvim/lua/plugins/snacks.lua` | **Created** -- all snacks.nvim config: 14 modules, 18 keybindings, toggle integrations |
| `dot_config/nvim/lua/plugins/ui.lua` | Removed neo-tree, nvim-notify, indent-blankline, dressing; updated bufferline offset to `snacks_layout_box`; added `<leader>n` notifications which-key group |
| `dot_config/nvim/lua/plugins/colorscheme.lua` | Removed NeoTree highlight overrides (dead code) |
| `dot_config/nvim/lua/plugins/lsp.lua` | Relocated `<leader>e` → `ge`, `ge`/`gE` → `gne`/`gpe`; replaced `<leader>f` format with `:Format` command + `BufWritePre` autocmd; fixed stale telescope comment |
| `dot_config/nvim/lua/plugins/editor.lua` | Changed todo-comments `<leader>ft` from `TodoTelescope` to `Snacks.picker.todo_comments()` |
| `dot_config/nvim/lua/plugins/telescope.lua` | **Deleted** -- replaced entirely by snacks.picker |
| `dot_config/nvim/init.lua` | Added JSONL notify logger (VeryLazy autocmd); removed `<leader>bd` keymap; added `netrwPlugin` to disabled_plugins |

## Deviations from Proposal

> NOTE(opus/implementation): The proposal stated `Snacks.picker.todo_comments` is a built-in snacks source. It is not -- it is registered by `todo-comments.nvim` itself when it detects snacks.picker is available (via `lua/todo-comments/snacks.lua`). The binding works correctly, but the integration is provided by todo-comments, not snacks.

> NOTE(opus/implementation): The explorer filetype for bufferline offset is `snacks_layout_box` (verified at runtime via headless nvim), not `snacks_explorer` as might be expected.

> NOTE(opus/implementation): The `Esc` key in the picker was configured to close from both insert and normal mode (`["<Esc>"] = { "close", mode = { "n", "i" } }`), matching the current telescope behavior where `<Esc>` always closes.

> NOTE(opus/implementation): The proposal specified explicit `<C-j>`/`<C-k>` navigation and `<C-q>` quickfix bindings for the picker. These are **not explicitly configured** because snacks.picker's defaults already include them (`defaults.lua` lines 251-255: `<c-j>` = list_down, `<c-k>` = list_up, `<c-q>` = qflist). Adding them would be redundant. Verified in snacks source.

## Verification

### Headless Validation (45/45 PASS)

Comprehensive validation script (`/tmp/nvim_final_validate.lua`) run via `nvim --headless`:

```
PASS: Snacks global
PASS: Config loaded
PASS: P1: bigfile, quickfile, scope, words, statuscolumn (5/5)
PASS: P2: notifier, indent, input, explorer, rename, toggle (6/6)
PASS: P2: notifier.top_down=false, style=compact, filter function (3/3)
PASS: P3: dashboard, dashboard.sections (2/2)
PASS: P4: picker, picker.ui_select, bufdelete (3/3)
PASS: All 18 keybindings registered (18/18)
PASS: nvim-notify, neo-tree, dressing, telescope, indent-blankline NOT loaded (5/5)
PASS: telescope.lua removed from deployed config (1/1)
```

### JSONL Logger Verified

```json
{"t":"2026-02-11T21:03:57Z","m":"test log entry","l":2,"s":"test"}
```

Written to `~/.local/state/nvim/notify.jsonl`.

### Remaining Cleanup (User Action Required)

- Run `:Lazy clean` to remove unused telescope.nvim, telescope-fzf-native.nvim, nvim-notify, indent-blankline.nvim, dressing.nvim, neo-tree.nvim, nui.nvim plugin directories
- `lazy-lock.json` will update automatically after `:Lazy clean`

### Commits

| Hash | Phase | Description |
|------|-------|-------------|
| `5822cac` | 1 | feat(nvim): add snacks.nvim with zero-config foundations |
| `8c9eb5b` | 2 | feat(nvim): replace notify, indent, dressing, neo-tree with snacks |
| `44e7f1c` | 3 | feat(nvim): add snacks dashboard with recent files and projects |
| `fa82b51` | 4 | feat(nvim): replace telescope with snacks.picker, add bufdelete |

---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-11T00:00:00-05:00
task_list: neovim/snacks-migration
type: devlog
state: live
status: wip
tags: [neovim, snacks-nvim, plugin-migration, handoff]
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
| *(implementation pending)* | |

## Verification

*(to be filled during implementation)*

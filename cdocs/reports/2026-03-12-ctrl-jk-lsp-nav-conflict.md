---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-03-12T00:00:00-04:00
task_list: wezterm/keybinding-conflicts
type: report
state: live
status: wip
tags: [analysis, keybindings, lsp, smart-splits, wezterm, neovim]
---

# Ctrl+J/K LSP vs Smart-Splits Navigation Conflict

> BLUF: Buffer-local LSP keymaps set on `LspAttach` override global smart-splits
> keymaps, causing `<C-k>` to fire `textDocument/signatureHelp` instead of pane
> navigation in LSP-attached buffers. JSON LSP doesn't support this method,
> producing a visible error. The fix is to remove `<C-k>` from the LSP keymap
> (it conflicts with an architectural navigation binding) and add a detection
> mechanism for future conflicts.

## Context / Background

The dotfiles configure seamless Ctrl+H/J/K/L navigation across WezTerm panes and
Neovim splits via two coordinated systems:

1. **WezTerm side** (`dot_config/wezterm/wezterm.lua:255-281`): A `split_nav()`
   callback detects whether the active pane is Neovim (via the `IS_NVIM` user
   variable). If so, it forwards the raw keystroke via `SendKey`; otherwise, it
   handles pane navigation directly.

2. **Neovim side** (`dot_config/nvim/lua/plugins/navigation.lua:28-32`):
   `smart-splits.nvim` binds `<C-h/j/k/l>` globally in `{ "n", "i", "t" }` modes.
   At Neovim's split edges, it fires an async `wezterm cli activate-pane-direction`
   to hand off to WezTerm.

This architecture is documented in
`cdocs/proposals/2026-02-11-smart-splits-adoption.md` and intentionally treats
Ctrl+H/J/K/L as **reserved infrastructure keys** that should never be overridden.

## Key Findings

### The conflict: buffer-local beats global

- **LSP config** (`dot_config/nvim/lua/plugins/lsp.lua:37,49`) sets `<C-k>` to
  `vim.lsp.buf.signature_help` via the `LspAttach` autocmd. The mapping uses
  `{ buffer = bufnr }`, making it **buffer-local**.

- **Smart-splits** (`navigation.lua:31`) sets `<C-k>` to
  `smart-splits.move_cursor_up()` via lazy.nvim's `keys` table. This creates a
  **global** mapping.

- In Neovim's keymap resolution order, **buffer-local mappings always win** over
  global mappings, regardless of when they were set.

- Result: In any buffer with an attached LSP server, pressing `<C-k>` fires
  `signature_help` instead of split/pane navigation.

### Why the error only appears in JSON files

The `textDocument/signatureHelp` method is designed for function-call contexts
(showing parameter names/types as you type). Most LSP servers implement it but
return empty results silently when outside a function call. The `jsonls` server
does not implement the method at all, returning an explicit
`MethodNotFound` error that Neovim surfaces to the user.

Other LSP servers (lua_ls, ts_ls) likely have the same `<C-k>` conflict but
silently return empty signature help without an error, masking the broken
navigation.

### `<C-j>` is not affected

Only `<C-k>` has a conflicting LSP binding (`signature_help`). There is no
`<C-j>` binding in the LSP keymap block. If the user observes `<C-j>` issues,
they may stem from a different source (e.g., nvim-cmp insert-mode mappings or
Neovim's default `<C-j>` = `<NL>` behavior).

### The full keypress chain (Ctrl+K in a JSON buffer)

```
Terminal: User presses Ctrl+K
    │
    ▼
WezTerm: split_nav callback
    │ is_nvim(pane) == true → SendKey { key="k", mods="CTRL" }
    │
    ▼
Neovim: keymap resolution for <C-k> in normal mode
    │ 1. Buffer-local: LSP signature_help ← WINS (buffer-local > global)
    │ 2. Global: smart-splits.move_cursor_up() ← never reached
    │
    ▼
LSP: vim.lsp.buf.signature_help()
    │ Sends textDocument/signatureHelp to jsonls
    │
    ▼
jsonls: MethodNotFound → error displayed to user
```

### Scope of impact

| LSP Server | `<C-k>` behavior | Visible error? |
|------------|-------------------|----------------|
| jsonls     | signatureHelp → MethodNotFound | Yes |
| lua_ls     | signatureHelp → empty result | No (silent, but navigation still broken) |
| ts_ls      | signatureHelp → may return data | No (but navigation still broken) |
| cssls      | signatureHelp → likely empty | No (but navigation still broken) |
| html       | signatureHelp → likely empty | No (but navigation still broken) |
| No LSP     | smart-splits works correctly | N/A |

**Navigation via `<C-k>` is broken in every LSP-attached buffer**, not just JSON.
JSON is simply the only filetype where the error is visible.

## Analysis

### Why this wasn't caught earlier

1. **Test gap**: The existing config test (`dot_config/nvim/test/config_test.lua:127-141`)
   validates that `<C-k>` has a callback in normal mode, but doesn't check *which*
   callback. After LSP attaches, the test would still pass — it just finds the LSP
   callback instead of the smart-splits one.

2. **Silent failures**: In non-JSON filetypes, the signature_help call returns
   empty/no-op results without error, so the user doesn't notice that navigation
   is actually broken — they just think they're already at the edge.

3. **Timing**: LSP attaches asynchronously after the buffer loads. The smart-splits
   binding exists when the buffer first opens, then gets shadowed moments later.

### The broader pattern

This is an instance of a general problem: **infrastructure keybindings** (navigation,
window management) can be silently overridden by **feature keybindings** (LSP, plugin
actions) when the feature uses buffer-local mappings. Neovim provides no warning
when a buffer-local mapping shadows a global one.

Reserved infrastructure keys in this config:
- `<C-h>` — navigate left
- `<C-j>` — navigate down
- `<C-k>` — navigate up (currently broken by LSP)
- `<C-l>` — navigate right
- `<C-A-h/j/k/l>` — resize splits/panes

## Recommendations

1. **Immediate fix**: Remove `<C-k>` → `signature_help` from the LSP keymap in
   `lsp.lua`. Rebind signature help to an uncontested key (e.g., `<leader>sh` or
   `gk`).

2. **Detection mechanism**: Add a validation check (either in the existing config
   test suite or as a startup autocmd) that verifies `<C-h/j/k/l>` resolve to
   smart-splits callbacks in all modes, even after LSP attaches. This catches
   future conflicts from new plugins or LSP config changes.

3. **Document reserved keys**: Add a comment block or config-level constant listing
   the reserved infrastructure keys, so future keymap additions can check against it.

See the companion proposal for implementation details.

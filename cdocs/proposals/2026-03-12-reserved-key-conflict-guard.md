---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-03-12T00:00:00-04:00
task_list: neovim/keybinding-integrity
type: proposal
state: live
status: review_ready
tags: [keybindings, lsp, smart-splits, neovim, navigation, testing]
---

# Guard Infrastructure Keybindings Against Silent Override

> BLUF: The LSP `LspAttach` autocmd sets a buffer-local `<C-k>` → `signature_help`
> mapping that silently overrides the global smart-splits `<C-k>` navigation binding
> in every LSP-attached buffer. Fix by (1) removing the conflicting LSP binding and
> rebinding signature help to `gK`, and (2) adding a startup guard that detects when
> any reserved infrastructure key is shadowed by a buffer-local mapping. See
> `cdocs/reports/2026-03-12-ctrl-jk-lsp-nav-conflict.md` for the full analysis.

## Objective

Ensure that the Ctrl+H/J/K/L navigation keys — which form the core of the
WezTerm/Neovim seamless pane navigation system — cannot be silently overridden by
LSP, plugin, or filetype-specific buffer-local mappings. Provide a detection
mechanism that warns about conflicts rather than requiring manual discovery.

## Background

The smart-splits integration (see `cdocs/proposals/2026-02-11-smart-splits-adoption.md`)
reserves `<C-h/j/k/l>` and `<C-A-h/j/k/l>` as infrastructure keys for cross-pane
navigation. These are set as global mappings in `navigation.lua`.

The LSP configuration in `lsp.lua` sets `<C-k>` → `vim.lsp.buf.signature_help` as
a buffer-local mapping via `LspAttach`. Neovim always resolves buffer-local mappings
before global ones, so the LSP binding silently wins in any buffer with an active
language server.

This has been broken since the smart-splits adoption but was only noticed in JSON
files, where `jsonls` returns an explicit `MethodNotFound` error for
`textDocument/signatureHelp`. In other filetypes (Lua, TypeScript, CSS, HTML), the
same conflict exists but produces no visible error — navigation silently fails.

## Proposed Solution

### Part 1: Fix the immediate conflict

Remove `<C-k>` → `signature_help` from the LSP keymap block in `lsp.lua` and rebind
it to `gK`. This follows the existing convention of `K` for hover documentation (`K`
is uppercase-k for "look up"), making `gK` a natural "go to signature" complement.

### Part 2: Reserved key guard

Add an `LspAttach` hook (or extend the existing one) that checks whether any reserved
infrastructure key has been shadowed by a buffer-local mapping. If a conflict is
detected, emit a `vim.notify` warning at `WARN` level identifying the conflicting
key and its new binding.

This runs on every `LspAttach` event, catching conflicts from:
- Direct LSP keymaps (like the current `<C-k>` issue)
- Plugin `ftplugin` files that set buffer-local mappings
- User `after/ftplugin` overrides

```lua
-- Reserved infrastructure keys that must not be overridden
local RESERVED_KEYS = { "<C-h>", "<C-j>", "<C-k>", "<C-l>" }

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.schedule(function()
      for _, key in ipairs(RESERVED_KEYS) do
        local maps = vim.api.nvim_buf_get_keymap(args.buf, "n")
        for _, m in ipairs(maps) do
          if m.lhs:upper() == key:sub(2, -2):upper()
            or m.lhs == vim.api.nvim_replace_termcodes(key, true, true, true) then
            vim.notify(
              ("Reserved key %s overridden in buf %d: %s"):format(
                key, args.buf, m.desc or m.rhs or "callback"
              ),
              vim.log.levels.WARN
            )
          end
        end
      end
    end)
  end,
})
```

### Part 3: Extend config tests

Add a test case to `dot_config/nvim/test/config_test.lua` that verifies the
smart-splits callback is the active handler for `<C-h/j/k/l>` in normal mode,
even after LSP would have attached. This catches regressions at config-validation
time rather than at runtime.

## Important Design Decisions

### Rebind signature help to `gK` (not `<leader>k` or `<leader>sh`)

**Decision:** Use `gK` as the new signature help binding.

**Why:** Neovim's `K` is already bound to hover documentation. Signature help is a
closely related "look up" action — `gK` reads as "go to signature" (parallel to `gd`
for "go to definition"). It's a single-chord binding that doesn't consume `<leader>`
namespace, and `gK` has no conflicting default binding in Neovim.

### Warn at runtime rather than block

**Decision:** The guard emits `vim.notify` warnings rather than forcibly removing
conflicting mappings.

**Why:** Forcibly deleting buffer-local mappings could break legitimate plugin behavior
in unexpected ways. A warning gives the user (or an agent reviewing logs) the
information to act without side effects. The warning approach is also safe for plugins
that intentionally override navigation in specific contexts (e.g., Snacks picker already
rebinds `<C-j/k>` in its own floating windows — that's fine because those are special
buffers, not regular editing buffers).

### Guard runs on `LspAttach`, not `BufEnter`

**Decision:** Hook the guard to `LspAttach` rather than `BufEnter` or `BufReadPost`.

**Why:** The most likely source of infrastructure key conflicts is LSP keymaps
(buffer-local mappings set in `LspAttach` callbacks). Running the check on
`LspAttach` ensures it fires after the conflicting mapping is set. A `BufEnter`
hook would fire too early (before LSP attaches) and miss the conflict. Using
`vim.schedule` inside the callback ensures all `LspAttach` handlers have completed
before the check runs.

## Edge Cases / Challenging Scenarios

### Snacks picker and other floating windows

Snacks picker intentionally rebinds `<C-j/k>` in its input/list windows. The guard
should not warn about these because they're floating windows with special filetypes,
not regular editing buffers. The `vim.schedule` approach handles this naturally —
Snacks picker buffers don't trigger `LspAttach` events, so the guard never fires for
them.

### Multiple LSP servers on one buffer

Some buffers may have multiple LSP servers attached (e.g., `ts_ls` + `eslint`). Each
`LspAttach` fires the guard. The guard should be idempotent — warning twice about the
same conflict is acceptable (and arguably useful since it confirms the issue persists).

### Future plugins that legitimately need `<C-k>`

If a future plugin genuinely needs `<C-k>` buffer-locally (e.g., a specialized
terminal mode), the warning surfaces the conflict immediately. The user can then
decide whether to add an exception or rebind the plugin.

## Implementation Phases

### Phase 1: Fix the LSP keybinding conflict

**Files:** `dot_config/nvim/lua/plugins/lsp.lua`

1. Change line 49 from `map("<C-k>", vim.lsp.buf.signature_help, "Signature help")`
   to `map("gK", vim.lsp.buf.signature_help, "Signature help")`.
2. Validate with `ls-fonts` parse check and deploy via `chezmoi apply --force`.
3. Verify in a running Neovim instance:
   - Open a JSON file, confirm `<C-k>` navigates up (smart-splits).
   - Confirm `gK` shows signature help (or empty result in JSON).
   - Open a Lua file, confirm `gK` shows signature documentation.

### Phase 2: Add the reserved key guard

**Files:** `dot_config/nvim/lua/plugins/navigation.lua`

1. Add the `RESERVED_KEYS` constant and `LspAttach` guard autocmd to the
   smart-splits `config` function (co-located with the `IS_NVIM` setup and
   `FocusFromEdge` command, since it's part of the same navigation infrastructure).
2. The guard checks `nvim_buf_get_keymap` for buffer-local mappings that shadow
   reserved keys.
3. Deploy and verify: temporarily add a buffer-local `<C-k>` binding in
   `after/ftplugin/lua.lua`, open a Lua file, confirm the warning appears, then
   remove the test binding.

### Phase 3: Extend config tests

**Files:** `dot_config/nvim/test/config_test.lua`

1. Add a test that opens a buffer, simulates LSP attachment (or checks post-attach
   state), and verifies `<C-h/j/k/l>` resolve to smart-splits callbacks.
2. The test should verify the callback's `desc` field contains "split/pane" to
   distinguish smart-splits from other callbacks.

> NOTE: Headless testing of LSP attach behavior is limited — LSP servers don't
> start in headless mode. The test can verify that the global smart-splits bindings
> exist and that no static buffer-local overrides are set, but it cannot simulate
> the full `LspAttach` flow. The runtime guard (Phase 2) covers that gap.

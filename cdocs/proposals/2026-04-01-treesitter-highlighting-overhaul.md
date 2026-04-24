---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-04-01T12:30:00-07:00
task_list: nvim/syntax-highlighting
type: proposal
state: live
status: wip
tags: [neovim, treesitter, catppuccin, syntax-highlighting]
---

# Comprehensive Treesitter Highlighting Overhaul

> BLUF: Replace the manual treesitter parser list and `FileType` autocmd with `ts-install.nvim`, which restores `auto_install` and `ensure_install` behavior removed from the nvim-treesitter main branch rewrite.
> This gives VSCode-like "open any file and get highlighting" behavior.
> Additionally, clean up stale solarized.nvim artifacts still on the runtimepath, which may be contributing to query conflicts.
> Two files change: `treesitter.lua` (rewrite) and `init.lua` (one-time lazy clean command).

## Summary

The current treesitter config has three compounding issues:
- A fixed parser list installed asynchronously, racing with `vim.treesitter.start()` on first launch.
- No auto-install for languages outside the explicit list.
- Stale solarized.nvim `after/queries/` files still loaded on the runtimepath after the theme switch.

`ts-install.nvim` (by lewis6991, author of gitsigns) is a lightweight plugin purpose-built to fill the gap left by the nvim-treesitter main branch rewrite.
It handles parser installation, auto-install on FileType, and highlighting enablement in one config block.

> NOTE(opus/syntax-highlighting): See `cdocs/reports/2026-04-01-syntax-highlighting-improvements.md` for the full analysis that preceded this proposal.

## Objective

Make neovim syntax highlighting work reliably for any filetype without manual parser management.
Specific requirements:
- TypeScript/TSX/JSX files highlight imports, types, JSX tags, and all language constructs.
- JSON/JSONC files highlight keys, values, and structure.
- SCSS files highlight variables, mixins, nesting, and interpolation.
- Any other filetype auto-installs its treesitter parser on first open.

## Background

The nvim-treesitter plugin was rewritten in 2025 (main branch).
The rewrite removed `auto_install`, `ensure_installed`, and `highlight = { enable = true }` config options.
Users must now call `vim.treesitter.start()` manually and manage parser installation through `require("nvim-treesitter").install()`.

Our current config attempts this with:
1. `require("nvim-treesitter").install(parsers)` called in `vim.schedule()` (async, non-blocking).
2. A `FileType` autocmd that calls `pcall(vim.treesitter.start)` for every filetype.

This approach has a race condition: on first launch (or after adding new parsers), the FileType autocmd fires before the async install completes, `vim.treesitter.start()` fails silently inside `pcall`, and the buffer gets no highlighting until the file is reopened.

Additionally, `solarized.nvim` was removed from the plugin config but lazy.nvim does not auto-delete plugin directories.
The stale plugin's `after/queries/{tsx,javascript,css,scss,lua}/highlights.scm` files remain on the runtimepath and are loaded by neovim's query resolution.

## Proposed Solution

### 1. Add ts-install.nvim

Replace the manual install/autocmd approach with `ts-install.nvim`:

```lua
{
  "lewis6991/ts-install.nvim",
  opts = {
    auto_install = true,
    ensure_install = {
      "bash", "c", "css", "scss", "diff", "dockerfile",
      "html", "javascript", "jsdoc", "json", "jsonc",
      "lua", "luadoc", "luap", "markdown", "markdown_inline",
      "printf", "python", "query", "regex", "rust",
      "toml", "tsx", "typescript", "vim", "vimdoc", "xml", "yaml",
    },
  },
}
```

`ts-install.nvim` handles:
- Pre-installing the `ensure_install` list at startup (skipping already-installed parsers).
- Auto-installing any missing parser when a file of that type is opened.
- Calling `vim.treesitter.start()` after successful install.

### 2. Simplify nvim-treesitter config

nvim-treesitter remains as a dependency (it provides parser compilation infrastructure and query files) but no longer needs custom config beyond incremental selection keymaps:

```lua
{
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").setup({})

    -- Incremental selection keymaps (preserved)
    vim.keymap.set("n", "s", function() ... end)
    vim.keymap.set("x", "s", function() ... end)
    vim.keymap.set("x", "S", function() ... end)
  end,
}
```

### 3. Clean solarized.nvim artifacts

Run `:Lazy clean` on first launch to remove the stale solarized.nvim directory and its `after/queries/` files from the runtimepath.

## Important Design Decisions

**ts-install.nvim over DIY auto-install**: A FileType autocmd that calls `install():wait()` blocks the UI during compilation.
ts-install.nvim handles this asynchronously with a callback that enables highlighting after install completes.
It is maintained by lewis6991 (gitsigns author), lightweight (~300 lines), and purpose-built for this exact gap.

**Expanded parser list**: The `ensure_install` list matches LazyVim's baseline (23 parsers) plus our additions for the web stack (`scss`, `jsonc`, `dockerfile`).
`auto_install = true` covers everything else on demand.

**Keeping nvim-treesitter as a dependency**: ts-install.nvim does not replace nvim-treesitter.
It uses nvim-treesitter's compilation infrastructure and query files.
Both plugins are needed.

## Edge Cases / Challenging Scenarios

**First launch with no parsers compiled**: ts-install.nvim's `ensure_install` runs synchronously on first launch (blocking, but only once).
Subsequent launches are instant since parsers are already compiled.

**No C compiler available**: Parser compilation requires a C compiler (`cc`, `gcc`, or `zig`).
If unavailable, ts-install.nvim logs an error.
This is standard for any treesitter setup.

**Stale parser .so files from old nvim-treesitter master branch**: Parsers compiled by the old master branch live in a different directory than main branch parsers.
Conflicting parser versions on the runtimepath could cause crashes.
The `:Lazy clean` step and a manual check of `nvim_get_runtime_file('parser', v:true)` addresses this.

## Test Plan

1. **TypeScript highlighting**: Open a `.ts` file, verify `import`, `export`, `const`, `interface`, type annotations are all distinctly highlighted.
2. **TSX highlighting**: Open a `.tsx` file, verify JSX tags (`<Component>`, `<div>`), attributes, and embedded expressions are highlighted.
3. **JSON highlighting**: Open a `.json` file, verify keys, string values, numbers, booleans, and null are highlighted.
4. **SCSS highlighting**: Open a `.scss` file, verify `$variables`, `@mixin`, `@include`, `&` parent selector, and nesting are highlighted.
5. **Auto-install**: Open a filetype not in `ensure_install` (e.g., `.go`, `.zig`), verify the parser auto-installs and highlighting appears.
6. **No regressions**: Verify Lua, Markdown, Bash, Python, Rust files still highlight correctly.

## Verification Methodology

After `chezmoi apply --force`, open neovim and verify:

```vim
:checkhealth vim.treesitter    " Should show parsers are available
:Inspect                       " On a keyword in a .ts file, should show treesitter highlight groups
:echo nvim_get_runtime_file('parser', v:true)  " Should NOT include solarized paths
```

For each test file, use `:Inspect` on various tokens to confirm treesitter capture groups are active (e.g., `@keyword.import` on `import`, `@tag` on JSX elements, `@variable` on SCSS `$vars`).

## Implementation Phases

### Phase 1: Clean stale artifacts

1. Remove solarized.nvim from lazy.nvim's plugin directory:
   ```sh
   rm -rf ~/.local/share/nvim/lazy/solarized.nvim
   ```
2. Verify no stale parser `.so` files conflict:
   ```vim
   :echo nvim_get_runtime_file('parser', v:true)
   ```

### Phase 2: Rewrite treesitter.lua

Replace the full contents of `dot_config/nvim/lua/plugins/treesitter.lua` with:
- `ts-install.nvim` spec with `auto_install = true` and the expanded `ensure_install` list.
- `nvim-treesitter` spec simplified to just `setup({})` and incremental selection keymaps.
- Remove the manual `install()` call and the `FileType` autocmd.

### Phase 3: Deploy and verify

1. `chezmoi apply --force`
2. Open neovim (first launch will compile any missing parsers).
3. Run through the test plan above.
4. Verify `:Inspect` shows treesitter groups on TypeScript/TSX/JSON/SCSS files.

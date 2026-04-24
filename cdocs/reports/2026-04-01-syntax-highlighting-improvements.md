---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-04-01T12:00:00-07:00
task_list: nvim/syntax-highlighting
type: report
state: live
status: wip
tags: [analysis, neovim, treesitter, catppuccin, scss, typescript]
---

# Syntax Highlighting Improvements for TypeScript/React/SCSS

> BLUF: TypeScript/React/SCSS files appear poorly highlighted due to three compounding issues: (1) neovim uses solarized while the terminal stack has moved to catppuccin mocha, creating palette mismatch, (2) SCSS files lack a dedicated treesitter parser and fall back to the `css` parser which can't highlight SCSS-specific syntax, and (3) JSDoc/TSDoc comments in TypeScript lack semantic highlighting.
> Recommended changes: switch neovim to catppuccin, add `scss` and `jsdoc` treesitter parsers, and add `regex` for inline regex highlighting.

## Context / Background

The user reports that files in a TypeScript/React/SCSS project don't seem well highlighted.
The terminal (tmux) has recently switched to catppuccin mocha theme, but neovim still uses solarized.nvim with custom slate background overrides.

Current neovim highlighting stack:
- **Theme**: `solarized.nvim` with custom backgrounds (#232323, #282828, #1c1c1c), italic comments, bold keywords.
- **Treesitter parsers**: typescript, tsx, javascript, lua, vim, vimdoc, html, css, json, jsonc, yaml, markdown, markdown_inline, bash, rust, python.
- **LSP servers**: ts_ls, lua_ls, cssls, html, jsonls.

## Key Findings

### 1. Theme Mismatch (High Impact)

tmux status bar uses catppuccin mocha palette.
Neovim uses solarized with custom slate backgrounds.
This creates visible inconsistency: the editor content uses solarized accent colors (green, yellow, blue, cyan) while surrounding UI uses catppuccin's pastel palette (mauve, peach, sky, lavender).

catppuccin.nvim provides:
- Native treesitter highlight group support (including TSX/JSX-specific groups).
- Built-in integrations for all installed plugins: gitsigns, bufferline, lualine, nvim-cmp, mason, which-key, flash, indent-blankline, snacks.
- Mocha flavor matches the tmux configuration exactly.

### 2. Missing SCSS Treesitter Parser (High Impact)

The `scss` treesitter parser is not installed.
SCSS files get the `scss` filetype from neovim's default detection, but treesitter falls back to the `css` parser.

SCSS-specific syntax that the `css` parser cannot highlight:
- `$variable` declarations and references.
- `@mixin`, `@include`, `@use`, `@forward`, `@extend` directives.
- `&` parent selector in nested rules.
- `#{$variable}` interpolation.
- Nested rule blocks (CSS parser expects flat structure).

### 3. Missing JSDoc/TSDoc Parser (Medium Impact)

The `jsdoc` treesitter parser provides semantic highlighting for documentation comments in TypeScript/JavaScript:
- `@param`, `@returns`, `@type`, `@template` tags highlighted as keywords.
- Type annotations within `{curly braces}` highlighted as types.
- Parameter names highlighted distinctly from description text.

Without it, JSDoc blocks render as uniform comment color.

### 4. Missing Regex Parser (Low Impact)

The `regex` treesitter parser enables syntax highlighting inside regex literals in JavaScript/TypeScript.
Character classes, quantifiers, groups, and anchors get distinct colors.
Low priority but improves readability of complex regex patterns.

### 5. LSP Coverage is Adequate

`cssls` (vscode-css-languageservice) does handle `.scss` files: it provides completions, hover, and diagnostics for SCSS.
The highlighting gaps are treesitter-level, not LSP-level.
A dedicated SCSS language server (`somesass_ls`) could be added later for richer SCSS goto-definition and `@use` namespace resolution, but this is not blocking.

## Recommendations

### Implement Now

1. **Replace solarized.nvim with catppuccin.nvim** (mocha flavor).
   Carry forward: italic comments, bold keywords, custom gitsigns colors (map to catppuccin equivalents).
   Update lazy.nvim `install.colorscheme` fallback.
   Update `vim.cmd.colorscheme()` call.

2. **Add `scss` treesitter parser** to the install list.

3. **Add `jsdoc` treesitter parser** to the install list.

4. **Add `regex` treesitter parser** to the install list.

### Consider Later

- `somesass_ls` for richer SCSS language intelligence (goto-definition across `@use` namespaces, `$variable` rename across files).
- `tailwindcss` LSP if the project uses Tailwind CSS (color previews, class completion).
- `nvim-ts-autotag` for auto-closing/renaming JSX/HTML tags (treesitter-based).

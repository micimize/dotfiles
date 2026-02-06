# mjr dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/). Config for nushell, neovim, wezterm, supporting tools.

The repo lives at `~/code/personal/dotfiles/`. Chezmoi maps files from here to `$HOME` using its naming conventions (`dot_bashrc` -> `~/.bashrc`, `dot_config/` -> `~/.config/`, etc.). There are no chezmoi templates -- everything is plain copies.

## Chezmoi
```bash
# install
brew install chezmoi

# init
chezmoi init --source ~/code/personal/dotfiles

# List all files chezmoi would manage
chezmoi managed

# Show a diff of what chezmoi would change on your system
chezmoi diff

# apply 
chezmoi apply -v
```

- `run_once_before_10-install-starship.sh`: [starship](https://starship.rs/) promptline (during apply)
- `run_once_before_30-install-carapace.sh`: [carapace](https://carapace-sh.github.io/) fzf-like for nushell (during apply)
- `.chezmoiignore` ignores old or not-yet-migrated paths (ncluding `firefox` and `tridactyl`)

## WezTerm + Nushell + Neovim orientation

Config: `~/.config/wezterm/wezterm.lua`

**Leader key: `Alt+Z`** (1 second timeout).

Key bindings (modeled after old tmux workflow):

| Action | Keys |
|---|---|
| Navigate panes | `Ctrl+H/J/K/L` |
| Create splits | `Alt+H/J/K/L` |
| Resize panes | `Ctrl+Alt+H/J/K/L` |
| Next/prev tab | `Alt+N` / `Alt+P` |
| New tab | `Alt+Shift+N` |
| Close pane | `Alt+W` |
| Copy mode | `Alt+C` |
| Zoom pane toggle | `Leader, Z` |
| Command palette | `Leader, :` |
| Reload config | `Leader, R` |
| Workspace switcher | `Leader, S` |
| Quick workspaces | `Leader, 1/2/3` (main/feature/scratch) |
| Lace project picker | `Leader, W` |

The **lace plugin** (`lace.wezterm`) discovers running devcontainers and lets you SSH into them via the project picker (`Leader, W`). It scans Docker for containers with SSH ports in the 22425-22499 range.

`default_prog` is set to nushell (`~/.cargo/bin/nu`), so new tabs and panes open nushell by default.

Appearance: Solarized Dark, JetBrains Mono 12pt, tab bar at bottom, 95% opacity.

### Nushell

Nushell is the primary interactive shell. Bash is still available and used for scripting (shebangs, CI, chezmoi run_once scripts, etc.), but day-to-day terminal work happens in nushell.

Config lives in `~/.config/nushell/`:
- `env.nu` -- loaded first (PATH, env vars, starship/carapace init)
- `config.nu` -- loaded second (settings, then sources the `scripts/` directory)

**Vi mode is on.** Press `Escape` for normal mode, `i` for insert. The cursor changes shape: line in insert, block in normal. `Ctrl+R` opens reverse history search in either mode.

Prompt indicators: `: ` in insert mode, `> ` in normal mode.

#### How nushell differs from bash

This is the part that trips you up after months away:

- **`ls` returns a table**, not text. You can sort, filter, and select columns: `ls | sort-by modified | last 5`
- **`open` reads files as structured data.** `open foo.json` gives you a nushell record, not a wall of text. Works for JSON, TOML, YAML, CSV, and more.
- **Pipes pass structured data**, not byte streams. `ls | where size > 1mb` works because `size` is a typed column, not a string.
- **`help <command>`** works for any builtin. `help ls`, `help open`, `help str`, etc.
- **External commands** still work as expected. Prefix with `^` to force the external version: `^ls`, `^grep`.
- **`nu -c "command"`** does NOT load config files. If you need aliases or PATH additions in a one-liner, be aware of this.

#### Aliases

Defined in `~/.config/nushell/scripts/aliases.nu`:

| Alias | What it does |
|---|---|
| `vim` | Runs `nvim` |
| `:q` | Exit the shell (vi habit) |
| `crm`, `cmv`, `ccp` | "Careful" rm/mv/cp -- external commands with `-i` (interactive) |
| `lse`, `lle`, `lsd` | External `ls` variants with color (for when you want classic output) |
| `duf`, `duh` | Disk usage (`df -h`, `du -h -c`) |

#### Utility commands

Defined in `~/.config/nushell/scripts/utils.nu`:

| Command | What it does |
|---|---|
| `showip` | Print your public IP (via checkip.amazonaws.com) |
| `extract <file>` | Universal archive extraction (tar, gz, bz2, zip, rar, 7z) |
| `ssh-del <line>` | Delete a line from `~/.ssh/known_hosts` by line number |
| `searchjobs <pattern>` | Search running processes (`ps \| where name =~ pattern`) |
| `colors-256` | Preview terminal 256-color palette |
| `git-track-all` | Track all remote git branches locally |
| `docker-clean` | Remove stopped containers and dangling images |

#### History

History is stored in SQLite (not a flat file), shared across sessions, up to 1M entries. This means you can query it with nushell's structured data tools:

```nu
history | where command =~ "docker" | last 10
```

There is also a `~/.full_history` plain-text log (written by a pre_execution hook) that records every command with timestamp, hostname, and working directory. This survives even if nushell's SQLite history is reset.

#### Completions

Carapace provides tab completions for external commands (git, docker, cargo, etc.). It bridges completions from zsh, fish, bash, and inshellisense. Just type a command and press `Tab`.

#### Exercises to try

After a fresh apply, open a wezterm tab and try these to verify things work:

```nu
# Five largest files in the current directory
ls | sort-by size | reverse | first 5

# Read starship config as structured data
open ~/.config/starship.toml

# Search your command history
history | where command =~ "git" | last 5

# System info as a nushell record
sys host

# HTTP built-in (no curl needed)
http get https://api.github.com/zen
```

### Neovim

Config: `~/.config/nvim/` (source: `dot_config/nvim/`). Uses lazy.nvim for plugin management (`init.lua` + `lua/plugins/`). The `vim` alias points to `nvim`, and `$EDITOR` / `$VISUAL` are both set to `nvim`.

**Leader key: `Space`** (300ms timeout). Press `Space` and wait -- which-key will pop up a hint panel showing available next keys and their descriptions.

Appearance: Solarized Dark, relative line numbers, indent guides, bufferline (tab-like bar at top showing open buffers), lualine statusbar at bottom showing mode/branch/diagnostics/filename.

#### Finding things

The VSCode equivalent of `Ctrl+P` (quick open) and `Ctrl+Shift+F` (search across files) is Telescope. Inside any Telescope picker, use `Ctrl+J/K` to move up/down, `Enter` to select, `Esc` to close, and `Ctrl+Q` to send results to the quickfix list.

| Action | Keys | VSCode equivalent |
|---|---|---|
| Find file by name | `Ctrl+Space` or `Space f f` | `Ctrl+P` |
| Live grep (search file contents) | `Space f g` | `Ctrl+Shift+F` |
| Grep word under cursor | `Space f w` | right-click "Find All References" |
| Open buffers (open files) | `Space f b` | tab switcher |
| Recent files | `Space f r` | recent files list |
| Command palette | `Ctrl+Shift+Space` or `Space f c` | `Ctrl+Shift+P` |
| Help tags | `Space f h` | -- |
| Find TODOs | `Space f t` | -- |
| Document symbols | `Space f s` | `Ctrl+Shift+O` |
| Workspace symbols | `Space f S` | `Ctrl+T` |

#### File explorer

Neo-tree provides a sidebar file tree (left side, 35 columns wide). It follows the current file and shows hidden files and git status.

| Action | Keys |
|---|---|
| Toggle file explorer | `Space n` |
| Reveal current file in explorer | `Space e` |

Inside the neo-tree window: `l` or `o` to open, `h` to collapse, `s` to open in a vertical split. Standard filesystem operations (create, rename, delete) are available from the neo-tree menu.

#### Code navigation (LSP)

LSP servers are auto-installed by Mason. Configured out of the box: TypeScript/JavaScript (`ts_ls`), Lua (`lua_ls`), CSS, HTML, JSON. Add more via `:Mason`.

| Action | Keys | VSCode equivalent |
|---|---|---|
| Go to definition | `g d` | `F12` or `Ctrl+Click` |
| Go to declaration | `g D` | -- |
| Find references | `g r` | `Shift+F12` |
| Go to implementation | `g i` | `Ctrl+F12` |
| Go to type definition | `g t` | -- |
| Hover documentation | `K` | mouse hover |
| Signature help | `Ctrl+K` | parameter hints |
| Rename symbol | `Space r n` | `F2` |
| Code action (quickfix/refactor) | `Space c a` | `Ctrl+.` |
| Format buffer | `Space f` | `Shift+Alt+F` |

#### Diagnostics

Errors, warnings, and hints appear inline and in the gutter (sign column). The statusbar also shows diagnostic counts.

| Action | Keys |
|---|---|
| Next diagnostic | `g e` |
| Previous diagnostic | `g E` |
| Show diagnostic float | `Space e` |
| Send diagnostics to location list | `Space q` |

#### Completion

nvim-cmp provides autocompletion from LSP, snippets (LuaSnip), buffer words, and file paths.

| Action | Keys |
|---|---|
| Trigger/next completion item | `Tab` |
| Next item | `Ctrl+N` or `Tab` |
| Previous item | `Ctrl+P` |
| Confirm selection | `Enter` |
| Dismiss completion | `Ctrl+E` |

`Tab` is context-aware: it inserts a literal tab at the start of a line or after whitespace, and triggers completion otherwise.

#### Git

Gitsigns shows added/changed/deleted lines in the gutter and line numbers. Fugitive provides full git porcelain. Diffview gives a VSCode-like side-by-side diff.

| Action | Keys |
|---|---|
| Next changed hunk | `] h` |
| Previous changed hunk | `[ h` |
| Stage hunk | `Space h s` |
| Reset hunk | `Space h r` |
| Stage entire buffer | `Space h S` |
| Undo stage hunk | `Space h u` |
| Reset entire buffer | `Space h R` |
| Preview hunk (inline diff) | `Space h p` |
| Blame current line | `Space h b` |
| Diff current file | `Space h d` |
| Toggle inline blame | `Space t b` |
| Toggle deleted lines | `Space t d` |
| Git status (fugitive) | `Space g g` |
| Git blame (full file) | `Space g b` |
| Git log | `Space g l` |
| Git commits (telescope) | `Space g c` |
| Git status (telescope) | `Space g s` |
| Diff view (all changes) | `Space g d` |
| File history | `Space g h` |

#### Buffers and windows

Buffers are neovim's equivalent of open files. The bufferline at the top shows them as tabs. Windows are splits within the current view.

| Action | Keys |
|---|---|
| Next buffer | `Ctrl+N` |
| Previous buffer | `Ctrl+P` |
| Close buffer | `Space b d` |
| Pin buffer | `Space b p` |
| Close unpinned buffers | `Space b P` |
| Move to left/down/up/right window | `Ctrl+H/J/K/L` |
| Vertical split | `:vs` |
| Horizontal split | `:sp` |
| Save | `Space w` |

Note: `Ctrl+N/P` means different things depending on context -- in normal mode they switch buffers, inside a completion menu they navigate the list.

#### Editing helpers

| Action | Keys |
|---|---|
| Comment line/selection | `gcc` (line) / `gc` (visual) |
| Surround add | `ys{motion}{char}` (e.g., `ysiw"` to surround word with quotes) |
| Surround change | `cs{old}{new}` (e.g., `cs"'` to change double to single quotes) |
| Surround delete | `ds{char}` (e.g., `ds"` to remove surrounding quotes) |
| Move lines up/down | `J` / `K` in visual mode |
| Better indenting | `<` / `>` in visual mode (stays in visual) |
| Yank entire file | `y p` |
| Expand selection (treesitter) | `s` then `s` to grow, `S` to shrink |
| Flash treesitter select | `S` in normal mode |
| Clear search highlight | `Esc` |
| Exit insert mode | `jk` or `jj` |

#### Sessions

Persistence auto-saves your session (open buffers, window layout, tabs) and can restore it later.

| Action | Keys |
|---|---|
| Restore session (current dir) | `Space q s` |
| Restore last session | `Space q l` |
| Stop saving session | `Space q d` |

#### Quick orientation checklist

If you just landed here from VSCode, try these in order:

1. Open a project directory: `nvim .`
2. Toggle the file tree: `Space n`
3. Find a file by name: `Ctrl+Space` and start typing
4. Search across all files: `Space f g` and type a pattern
5. Jump to a symbol definition: cursor on a symbol, press `g d`
6. See what changed in git: `Space g g` (fugitive status) or `Space g d` (diff view)
7. Press `Space` and wait to see what else is available via which-key


---

## Legacy notes

### mac OS migration (todo or discard)

- `chsh -s /bin/bash` on macOS
- iTerm theme: `macos/iterm_solarized.json`
- Karabiner settings: `macos/karabiner.json`

These are in the repo but excluded by `.chezmoiignore`. They predate the current Linux+nushell+wezterm setup.

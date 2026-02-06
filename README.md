# mjr dotfiles

Personal dotfiles managed by [chezmoi](https://www.chezmoi.io/). Config for nushell, bash, wezterm, starship, and supporting tools.

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

## WezTerm + Nushell + Starship orientation

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

Config: `~/.config/nvim/` (source: `dot_config/nvim/`). Uses lazy.nvim for plugin management (`init.lua` + `lua/` directory). The `vim` alias points to `nvim`, and `$EDITOR` / `$VISUAL` are both set to `nvim`.

### Starship

Config: `~/.config/starship.toml`

Starship is the prompt for both bash and nushell. It shows: time (MM-DD HH:MM), a custom shortened path, git branch, git status, and background job count. The color scheme is Solarized Dark to match wezterm.

Installed by the `run_once_before_10-install-starship.sh` script via `cargo install starship --locked`.

---

## Legacy notes

### mac OS migration (todo or discard)

- `chsh -s /bin/bash` on macOS
- iTerm theme: `macos/iterm_solarized.json`
- Karabiner settings: `macos/karabiner.json`

These are in the repo but excluded by `.chezmoiignore`. They predate the current Linux+nushell+wezterm setup.

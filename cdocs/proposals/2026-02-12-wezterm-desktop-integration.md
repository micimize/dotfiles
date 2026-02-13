---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-12T12:00:00-06:00
task_list: dotfiles/wezterm
type: proposal
state: live
status: implemented
tags: [wezterm, kde, desktop-integration, chezmoi]
last_reviewed:
  status: accepted
  by: "@claude-opus-4-6"
  at: 2026-02-12T21:30:00-06:00
  round: 2
---

# Register WezTerm as a Native KDE Desktop Application

> BLUF: Homebrew-installed WezTerm ships as a bare binary with no desktop integration.
> Create a chezmoi-managed `.desktop` file, install the custom lavender SVG icon into
> the freedesktop icon hierarchy, and set WezTerm as the KDE default terminal — so that
> WezTerm appears in KRunner, the KDE app launcher, task switcher, and is used whenever
> KDE or other apps launch "the terminal." Four chezmoi source artifacts handle everything:
> the icon asset, the `.desktop` entry, the icon symlink into `~/.local/share/icons/`,
> and a `run_once_` script that calls `kwriteconfig6` to set the default.

## Objective

Make WezTerm the default terminal and fully integrated into KDE — discoverable and
launchable through KRunner, the application menu, and used automatically by any app or
shortcut that opens "the terminal." Use the project's custom lavender icon throughout,
without requiring any system-level package installation or root access.

## Background

**Current state:** WezTerm is installed via Homebrew on ublue Aurora (Fedora Atomic /
KDE Plasma 6.5). The Homebrew formula ships only the `wezterm` binary at
`/home/linuxbrew/.linuxbrew/bin/wezterm` — no `.desktop` file, no icon, no AppStream
metadata. The binary is on `$PATH` but invisible to KDE's application infrastructure.

**KDE's terminal discovery:** KDE Plasma uses the `TerminalEmulator` category in
`.desktop` files to populate its "default terminal" selector in System Settings. KRunner
indexes `.desktop` files from `$XDG_DATA_DIRS` paths, which includes
`~/.local/share/applications/`. The current default terminal is Ptyxis (GNOME's
container-oriented terminal, shipped as Aurora's default).

**Icon requirements:** KDE/freedesktop icon lookup checks
`~/.local/share/icons/hicolor/scalable/apps/` for user-installed SVG icons. The icon name
in the `.desktop` file must match the filename (without extension) in the icon directory.
The project already has a custom `wezterm_lavender.svg` (87KB, 1273x1273 SVG) at the
repo root.

**WezTerm's WM_CLASS:** Upstream WezTerm sets `StartupWMClass=org.wezfurlong.wezterm`.
This is what KDE uses to associate running windows with their `.desktop` entry for
taskbar grouping, window rules, and the task switcher icon.

**Reference `.desktop` files examined:**
- Upstream WezTerm: minimal, uses `org.wezfurlong.wezterm` as icon name and WM class
- Konsole (`org.kde.konsole.desktop`): includes desktop actions for New Window / New Tab
- Ptyxis (`org.gnome.Ptyxis.desktop`): includes `X-KDE-AuthorizeAction=shell_access`

## Proposed Solution

### Files to create/move

| Chezmoi source path | Deployed path | Purpose |
|---|---|---|
| `dot_config/wezterm/assets/wezterm_lavender.svg` | `~/.config/wezterm/assets/wezterm_lavender.svg` | Icon source asset |
| `dot_local/share/applications/org.wezfurlong.wezterm.desktop` | `~/.local/share/applications/org.wezfurlong.wezterm.desktop` | Desktop entry |
| `dot_local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg` | `~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg` | Icon in freedesktop hierarchy (symlink to the asset) |
| `run_once_after_10-set-wezterm-default-terminal.sh` | *(executed once by chezmoi)* | Sets KDE default terminal, rebuilds icon/desktop caches |

> NOTE: The icon in the freedesktop hierarchy should be a chezmoi `symlink_` to the
> canonical copy under `~/.config/wezterm/assets/`, avoiding file duplication. Chezmoi
> supports this via `symlink_dot_local/...` source naming.

### `.desktop` file content

```ini
[Desktop Entry]
Name=WezTerm
GenericName=Terminal
Comment=GPU-accelerated terminal emulator
Keywords=shell;prompt;command;commandline;cmd;cli;terminal;console;wezterm;
Icon=org.wezfurlong.wezterm
StartupWMClass=org.wezfurlong.wezterm
TryExec=/home/linuxbrew/.linuxbrew/bin/wezterm
Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start
Type=Application
Categories=System;TerminalEmulator;Utility;
Terminal=false
StartupNotify=true
X-KDE-AuthorizeAction=shell_access
Actions=new-window;new-tab;

[Desktop Action new-window]
Name=New Window
Exec=/home/linuxbrew/.linuxbrew/bin/wezterm start
Icon=window-new

[Desktop Action new-tab]
Name=New Tab
Exec=/home/linuxbrew/.linuxbrew/bin/wezterm cli spawn
Icon=tab-new
```

Key design points:
- `TryExec` and `Exec` use absolute Homebrew paths because KDE launches `.desktop`
  entries via `systemd`/`kstart`, which do not source interactive shell profiles where
  Homebrew adds itself to `$PATH`. Confirmed: `wezterm` does not resolve in a minimal
  `PATH` environment. The absolute path is guaranteed to work; the entry still hides
  gracefully via `TryExec` if WezTerm is uninstalled.
- `Exec` omits `--cwd` entirely, letting WezTerm default to `$HOME`. When launched from
  KRunner or the app menu, the working directory is undefined, so `--cwd .` would resolve
  to an unpredictable location.
- `StartupWMClass=org.wezfurlong.wezterm` matches WezTerm's actual X11/Wayland
  app-id for proper taskbar association
- `X-KDE-AuthorizeAction=shell_access` follows KDE convention for terminal emulators
  (seen in both Konsole and Ptyxis)
- Desktop actions for New Window and New Tab provide right-click taskbar actions

### Default terminal `run_once_` script

KDE stores the default terminal in `~/.config/kdeglobals` under the `[General]` group
via two keys: `TerminalApplication` (the binary name) and `TerminalService` (the
`.desktop` file name). The system default on Aurora is `kde-ptyxis` /
`org.gnome.Ptyxis.desktop`, set in `/usr/share/kde-settings/.../kdeglobals`.

A chezmoi `run_once_after_` script overrides this at the user level and rebuilds
desktop caches:

```sh
#!/bin/sh
set -e

# Set WezTerm as the default KDE terminal emulator
if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    echo "kwriteconfig6 not found, skipping default terminal setup"
    exit 0
fi

kwriteconfig6 --file kdeglobals --group General --key TerminalApplication /home/linuxbrew/.linuxbrew/bin/wezterm
kwriteconfig6 --file kdeglobals --group General --key TerminalService org.wezfurlong.wezterm.desktop

# Rebuild desktop and icon caches so KRunner and the app menu pick up changes immediately
update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true
```

This approach is correct because:
- `kwriteconfig6` is the canonical way to write KDE config: it handles file locking and
  notifies running KDE components of the change
- `~/.config/kdeglobals` is a volatile file that KDE itself modifies (color schemes,
  fonts, etc.), so chezmoi must not manage it as a regular file
- `run_once_` ensures the script runs exactly once per machine, not on every `chezmoi apply`
- If the user later changes the default terminal via System Settings, their choice is
  preserved (the `run_once_` will not re-run)
- The `command -v` guard and `|| true` on cache commands ensure the script is safe on
  non-KDE systems where the same dotfiles might be applied

### Chezmoi directory scaffolding

The repo currently has no `dot_local/` tree. This proposal introduces it with the
minimum required structure:

```
dot_local/
  share/
    applications/
      org.wezfurlong.wezterm.desktop
    icons/
      hicolor/
        scalable/
          apps/
            symlink_org.wezfurlong.wezterm.svg  (-> ~/.config/wezterm/assets/wezterm_lavender.svg)
run_once_after_10-set-wezterm-default-terminal.sh
```

## Important Design Decisions

### Icon name: `org.wezfurlong.wezterm` (not `wezterm_lavender`)

**Decision:** Name the icon `org.wezfurlong.wezterm.svg` in the freedesktop hierarchy,
matching the upstream app-id convention.

**Why:** KDE resolves icons by the `Icon=` value in the `.desktop` file. Using the
upstream reverse-DNS name means the `.desktop` file works with both our custom icon and
any future system-packaged WezTerm icon (ours wins because `~/.local/share/icons` takes
precedence over `/usr/share/icons`). It also means the taskbar icon resolves correctly
for WezTerm windows even without the `.desktop` file loaded.

### Symlink (not copy) for the icon in the freedesktop hierarchy

**Decision:** Use a chezmoi symlink from the freedesktop icon path back to the canonical
copy under `~/.config/wezterm/assets/`.

**Why:** Single source of truth. Updating the icon means editing one file. The symlink
also makes it clear to future readers that the freedesktop icon is derived from the
WezTerm asset, not an independent file.

### Move icon into `dot_config/wezterm/assets/` (not leave at repo root)

**Decision:** Move `wezterm_lavender.svg` from the repo root into
`dot_config/wezterm/assets/wezterm_lavender.svg`.

**Why:** The repo root is not deployed by chezmoi. Assets that need to be deployed must
live under a chezmoi-managed path. Grouping it under `wezterm/assets/` keeps the icon
co-located with the WezTerm config it belongs to. The original filename is preserved so
we can add other icon variants in the future.

### Set the default via `run_once_` script (not chezmoi-managed `kdeglobals`)

**Decision:** Use a chezmoi `run_once_` script that calls `kwriteconfig6` rather than
managing `~/.config/kdeglobals` as a chezmoi template.

**Why:** `kdeglobals` is actively written to by KDE itself (theme changes, font settings,
animation speed, etc.). Managing it as a chezmoi file would cause conflicts on every
`chezmoi apply` after any System Settings change. The `run_once_` approach writes the
terminal preference exactly once, then gets out of the way — any subsequent user changes
via System Settings are preserved.

## Edge Cases / Challenging Scenarios

**Homebrew not on PATH in desktop sessions:** KDE launches `.desktop` entries via
`systemd`/`kstart`, which do not source interactive shell profiles where Homebrew adds
itself to `$PATH`. Confirmed: `wezterm` does not resolve in a minimal `PATH` environment
(tested via `env -i PATH="/usr/local/bin:..." sh -c 'which wezterm'`).

- *Resolution:* The `.desktop` file uses absolute Homebrew paths
  (`/home/linuxbrew/.linuxbrew/bin/wezterm`) in both `Exec` and `TryExec`. This is less
  portable if Homebrew relocates, but guaranteed to work on the current system. If
  Homebrew moves in the future, the `.desktop` file is a single chezmoi-managed file
  that can be updated.

**Icon cache not updated:** KDE caches icons aggressively. After initial deployment, the
icon may not appear until the cache is rebuilt.

- *Resolution:* The `run_once_after_` script calls `gtk-update-icon-cache` and
  `update-desktop-database` after setting the default terminal, so all desktop
  integration happens in one shot.

**WezTerm uninstalled:** If the user removes WezTerm via `brew uninstall`, the `.desktop`
file and icon remain as orphans. `TryExec` prevents KDE from showing the entry, so this
is cosmetically benign but leaves dead files.

- *Mitigation:* Acceptable. The files are small and inert. Document that `chezmoi forget`
  can clean them up if desired.

**New Tab action requires running mux:** `wezterm cli spawn` connects to a running WezTerm
mux server. If no WezTerm instance is running, the New Tab action will fail.

- *Mitigation:* Acceptable. This matches Konsole's behavior (its New Tab action also
  requires a running instance). Users will naturally use "New Window" when no instance
  is running.

## Test Plan

**Icon resolution:**
```sh
# Verify icon symlink and file exist:
readlink ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
file -L ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
# Expected: SVG Scalable Vector Graphics image
```

**Desktop entry validation:**
```sh
desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop
```

**KRunner discovery:**
```sh
# Restart KRunner to pick up new .desktop files:
kquitapp6 krunner && kstart6 krunner
# Then type "wezterm" in KRunner — it should appear as a launchable app with the icon
```

**Default terminal setting:**
```sh
# Verify kdeglobals was updated:
kreadconfig6 --file kdeglobals --group General --key TerminalApplication
# Expected: /home/linuxbrew/.linuxbrew/bin/wezterm
kreadconfig6 --file kdeglobals --group General --key TerminalService
# Expected: org.wezfurlong.wezterm.desktop
```

**Taskbar icon association:**
- Launch WezTerm from KRunner or the app menu
- Verify the taskbar shows the lavender icon (not a generic terminal icon)
- Right-click the taskbar entry — "New Window" and "New Tab" actions should appear

**Default terminal behavior:**
- In Dolphin, right-click a folder → "Open Terminal Here": should launch a standalone
  WezTerm window in that directory

> NOTE: Dolphin's F4 embedded terminal panel uses KParts, which requires a VTE-compatible
> terminal. WezTerm does not support KParts embedding, so F4 will continue to use the
> KParts-compatible terminal (typically Konsole). This is expected and not a defect.

## Implementation Phases

### Phase 1: Move and register the icon asset

1. Create `dot_config/wezterm/assets/` directory
2. Move `wezterm_lavender.svg` from repo root to `dot_config/wezterm/assets/wezterm_lavender.svg`
3. Remove the original file from the repo root (stage the `git mv`)
4. `chezmoi apply --force` to deploy the asset
5. Verify: `ls ~/.config/wezterm/assets/wezterm_lavender.svg`

### Phase 2: Create the freedesktop icon symlink

1. Create chezmoi source for the symlink:
   `dot_local/share/icons/hicolor/scalable/apps/symlink_org.wezfurlong.wezterm.svg`
   containing the target path `../../../../../../.config/wezterm/assets/wezterm_lavender.svg`
   (relative symlink from `~/.local/share/icons/hicolor/scalable/apps/` to
   `~/.config/wezterm/assets/`)

   > NOTE: Chezmoi symlink targets should use relative paths to stay portable across
   > home directory locations. The relative path from
   > `~/.local/share/icons/hicolor/scalable/apps/` back to `~/.config/wezterm/assets/`
   > traverses 6 levels up to `~` (`.local`, `share`, `icons`, `hicolor`, `scalable`,
   > `apps`), then down into `.config/wezterm/assets/`.

2. `chezmoi apply --force`
3. Verify: `readlink ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg`
4. Rebuild icon cache: `gtk-update-icon-cache ~/.local/share/icons/hicolor/`

### Phase 3: Create the `.desktop` file

1. Create `dot_local/share/applications/org.wezfurlong.wezterm.desktop` with the content
   specified in the Proposed Solution
2. `chezmoi apply --force`
3. Validate: `desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop`
4. Update desktop database: `update-desktop-database ~/.local/share/applications/`

### Phase 4: Set WezTerm as the default terminal and rebuild caches

1. Create `run_once_after_10-set-wezterm-default-terminal.sh` at the chezmoi source root
   with the script from the Proposed Solution (includes `set -e`, `command -v` guard,
   `kwriteconfig6` calls, and cache rebuilds)
2. `chezmoi apply --force` (this executes the run_once script)
3. Verify: `kreadconfig6 --file kdeglobals --group General --key TerminalApplication`
   → should return `/home/linuxbrew/.linuxbrew/bin/wezterm`
4. Verify: `kreadconfig6 --file kdeglobals --group General --key TerminalService`
   → should return `org.wezfurlong.wezterm.desktop`

### Phase 5: Integration verification

1. Restart KRunner (`kquitapp6 krunner && kstart6 krunner`)
2. Search "wezterm" in KRunner — confirm it appears with the lavender icon
3. Launch WezTerm from KRunner — confirm it opens
4. Verify taskbar shows the lavender icon for the running WezTerm window
5. Right-click taskbar icon — verify "New Window" and "New Tab" actions appear
6. In Dolphin, right-click a folder → "Open Terminal Here" — should launch WezTerm
7. Commit all changes

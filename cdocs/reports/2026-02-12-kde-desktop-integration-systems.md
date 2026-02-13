---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-12T18:30:00-06:00
task_list: dotfiles/wezterm
type: report
state: live
status: done
tags: [explainer, kde, freedesktop, desktop-integration, chezmoi]
related: cdocs/proposals/2026-02-12-wezterm-desktop-integration.md
---

# KDE Desktop Integration Systems Explainer

> BLUF: Registering a Homebrew-installed application as a native KDE citizen touches four
> independent systems: `.desktop` files, the freedesktop icon theme, KDE's default terminal
> config, and chezmoi as the delivery mechanism. This report explains each system and why
> the proposal makes the choices it does, as a reference companion to the proposal.

## Context

The WezTerm desktop integration proposal (linked above) introduces several freedesktop
and KDE concepts. This report captures the explanations produced during the proposal
authoring session for future reference.

## `.desktop` Files (the core of everything)

This is the freedesktop.org standard that all Linux desktops use. A `.desktop` file is
essentially a registry entry that says "here's an application, here's how to launch it,
here's its icon, here's what category it belongs to." Without one, an application is
invisible to the desktop — it's just a binary you can run from a shell.

KDE, GNOME, and every other desktop environment scan specific directories for these files.
`~/.local/share/applications/` is the per-user location. Drop a valid `.desktop` file
there and the app shows up in menus, search, etc.

The `TryExec` field is a nice safety mechanism: KDE checks if that binary exists before
showing the entry. If you uninstall WezTerm, the entry vanishes automatically.

The reason we use absolute paths (`/home/linuxbrew/.linuxbrew/bin/wezterm`) instead of
just `wezterm` is that KDE doesn't launch apps through your shell. It uses `systemd` or
its own launcher, which has a minimal `$PATH` that doesn't include Homebrew's directory.
The app literally wouldn't be found.

## Freedesktop Icon Theme

KDE looks up icons by name, not by file path. When the `.desktop` file says
`Icon=org.wezfurlong.wezterm`, KDE searches through a hierarchy of icon theme directories
for a file named `org.wezfurlong.wezterm.svg` (or `.png`). The standard location for
user-installed scalable icons is `~/.local/share/icons/hicolor/scalable/apps/`.

KDE also uses this same icon lookup to match running windows to their icons via
`StartupWMClass`. So even the taskbar icon depends on this being set up correctly.

The icon cache (`gtk-update-icon-cache`) is a performance optimization that KDE reads
instead of scanning the filesystem every time. After adding a new icon, you need to
rebuild it or the icon won't appear until the next login.

## KDE's Default Terminal Setting

KDE stores "which terminal should 'Open Terminal Here' use?" in `~/.config/kdeglobals`
under two keys:

- `TerminalApplication`: the binary path (used by Dolphin's right-click → Open Terminal Here)
- `TerminalService`: the `.desktop` file name (used by KDE's internal service resolution)

The system-wide default on Aurora sets these to `kde-ptyxis` / `org.gnome.Ptyxis.desktop`.
Writing to the user-level `kdeglobals` overrides that. We use `kwriteconfig6` (KDE's own
config writer) instead of editing the file directly because KDE has its own file locking
and change-notification system — writing with a text editor could race with KDE or miss
notifying running components.

## Chezmoi's Role

Chezmoi is just the delivery mechanism. It deploys files from the dotfiles repo to the
right places in `~`. The interesting part is the `run_once_` script: chezmoi tracks which
scripts it has already executed (by hashing the script content), so the `kwriteconfig6`
calls and cache rebuilds happen exactly once on initial deployment, then never again —
even on subsequent `chezmoi apply` runs. This means if you later change your default
terminal through System Settings, chezmoi won't fight you.

## Symlink Level Count

A relative symlink uses `../` to navigate "up" directories before going back down. The
"level count" is how many `../` steps you need.

The symlink lives at:
```
~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
```

It needs to point to:
```
~/.config/wezterm/assets/wezterm_lavender.svg
```

Both paths share `~/` as their common ancestor. So the symlink has to climb out of 6
nested directories to get back to `~`:

```
apps/        → ../      (1)
scalable/    → ../      (2)
hicolor/     → ../      (3)
icons/       → ../      (4)
share/       → ../      (5)
.local/      → ../      (6)
```

Then descend into `.config/wezterm/assets/wezterm_lavender.svg`.

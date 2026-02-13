---
first_authored:
  by: "@claude-opus-4-6"
  at: 2026-02-12T18:45:00-06:00
task_list: dotfiles/wezterm
type: devlog
state: live
status: done
tags: [wezterm, kde, desktop-integration, chezmoi, handoff]
last_reviewed:
  status: accepted
  by: "@claude-opus-4-6"
  at: 2026-02-12T23:00:00-06:00
  round: 3
related:
  - cdocs/proposals/2026-02-12-wezterm-desktop-integration.md
  - cdocs/reports/2026-02-12-kde-desktop-integration-systems.md
  - cdocs/reviews/2026-02-12-review-of-wezterm-desktop-integration.md
---

# WezTerm KDE Desktop Integration: Devlog

## Objective

Implement the accepted proposal to register Homebrew-installed WezTerm as a native KDE
desktop application with the custom lavender icon and set it as the default terminal.

## Key References

- **Proposal** (the source of truth for what to build):
  `cdocs/proposals/2026-02-12-wezterm-desktop-integration.md`
- **Systems explainer** (background on `.desktop` files, icon themes, `kdeglobals`, chezmoi):
  `cdocs/reports/2026-02-12-kde-desktop-integration-systems.md`
- **Review** (completed round 1, all findings incorporated into proposal):
  `cdocs/reviews/2026-02-12-review-of-wezterm-desktop-integration.md`

## Plan

The proposal defines 5 phases. Follow them in order:

1. **Move and register the icon asset** — `git mv` the SVG into `dot_config/wezterm/assets/`
2. **Create the freedesktop icon symlink** — chezmoi `symlink_` with 6-level relative path
3. **Create the `.desktop` file** — absolute Homebrew paths, validate with `desktop-file-validate`
4. **Set default terminal + rebuild caches** — `run_once_after_10-` script
5. **Integration verification** — KRunner, taskbar, Dolphin "Open Terminal Here"

Each phase has explicit verify steps in the proposal. Do not skip them.

## Testing Approach

Each phase is verified independently before moving to the next. The proposal specifies
the exact verification commands. Key validations:

- `file -L` on the icon symlink to confirm it resolves to an SVG
- `desktop-file-validate` on the `.desktop` file
- `kreadconfig6` to confirm default terminal was set
- KRunner restart + manual search to confirm discoverability
- Dolphin right-click → "Open Terminal Here" to confirm default terminal behavior

> NOTE: Dolphin's F4 embedded terminal uses KParts (Konsole only). WezTerm will not
> appear there. This is expected, not a defect. See the proposal's test plan for details.

## Implementation Notes

### Phase 1: Move icon asset

SVG was untracked (not git-managed), so `git mv` failed. Used plain `mv` + `git add` instead.
Deployed to `~/.config/wezterm/assets/wezterm_lavender.svg` (86,945 bytes, valid SVG). Commit `fe86842`.

### Phase 2: Freedesktop icon symlink

Created chezmoi `symlink_` source containing 6-level relative path:
`../../../../../../.config/wezterm/assets/wezterm_lavender.svg`

`gtk-update-icon-cache` failed: "No theme index file" — the user-level `~/.local/share/icons/hicolor/`
has no `index.theme`. This is harmless on KDE Plasma, which resolves icons by scanning the directory
hierarchy directly. The `run_once_` script guards this with `|| true`. Commit `087357e`.

### Phase 3: .desktop file

Created exact content from proposal. `desktop-file-validate` passes with one hint about dual main
categories (`System` + `Utility`). This matches Konsole's pattern and is cosmetic. Desktop database
updated via `update-desktop-database`. Commit `1ca059b`.

**Mid-implementation review** (after Phase 3): Accept verdict, no blocking issues. Three non-blocking
items: stale repo-root SVG (already removed by `mv`), devlog updates (this section), icon cache docs
(noted above in Phase 2).

### Phase 4: Default terminal + caches

Created `run_once_after_10-set-wezterm-default-terminal.sh` with exact content from proposal.
`chezmoi apply` executed it successfully. Both `kdeglobals` keys confirmed set. Commit `1a2ae8c`.

### Phase 5: Integration verification

All CLI-verifiable checks pass. KRunner restarted via `kquitapp6 krunner` + `krunner --daemon`
(`kstart6` not available on this system — deviation from proposal, functionally equivalent).

**Manual testing required by user:**
- Search "wezterm" in KRunner — confirm lavender icon and launchability
- Launch WezTerm — verify taskbar shows lavender icon
- Right-click taskbar icon — verify "New Window" / "New Tab" actions
- Dolphin right-click folder → "Open Terminal Here" — should launch WezTerm

## Changes Made

| File | Description |
|------|-------------|
| `dot_config/wezterm/assets/wezterm_lavender.svg` | Icon asset moved from repo root |
| `dot_local/share/icons/hicolor/scalable/apps/symlink_org.wezfurlong.wezterm.svg` | Freedesktop icon symlink |
| `dot_local/share/applications/org.wezfurlong.wezterm.desktop` | Desktop entry for KDE |
| `run_once_after_10-set-wezterm-default-terminal.sh` | Set default terminal + rebuild caches |

## Verification

### Phase 1
```
$ ls ~/.config/wezterm/assets/wezterm_lavender.svg
/home/mjr/.config/wezterm/assets/wezterm_lavender.svg (86945 bytes)
$ file ~/.config/wezterm/assets/wezterm_lavender.svg
SVG Scalable Vector Graphics image, ASCII text, with very long lines (56335)
```

### Phase 2
```
$ readlink ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
../../../../../../.config/wezterm/assets/wezterm_lavender.svg
$ file -L ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
SVG Scalable Vector Graphics image, ASCII text, with very long lines (56335)
```

### Phase 3
```
$ desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop
hint: value "System;TerminalEmulator;Utility;" ... contains more than one main category
(hint only, not an error)
```

### Phase 4
```
$ kreadconfig6 --file kdeglobals --group General --key TerminalApplication
/home/linuxbrew/.linuxbrew/bin/wezterm
$ kreadconfig6 --file kdeglobals --group General --key TerminalService
org.wezfurlong.wezterm.desktop
```

### Phase 5
```
$ readlink ~/.local/share/icons/hicolor/scalable/apps/org.wezfurlong.wezterm.svg
../../../../../../.config/wezterm/assets/wezterm_lavender.svg  ✓
$ desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop
(hint only, passes)  ✓
$ kreadconfig6 --file kdeglobals --group General --key TerminalApplication
/home/linuxbrew/.linuxbrew/bin/wezterm  ✓
$ kreadconfig6 --file kdeglobals --group General --key TerminalService
org.wezfurlong.wezterm.desktop  ✓

Manual testing: pending user verification (KRunner, taskbar icon, Dolphin)
```

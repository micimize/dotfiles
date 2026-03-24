---
first_authored:
  by: "@claude-opus-4-6-20250725"
  at: 2026-03-24T12:00:00-07:00
task_list: tmux/image-paste-through
type: report
state: archived
status: done
tags: [tmux, clipboard, wayland, claude-code, wezterm, ssh, investigation]
---

> BLUF: There are two independent blockers preventing image paste into Claude Code.
> (1) WezTerm's default `Ctrl+V -> PasteFrom 'Clipboard'` intercepts the keypress before Claude Code sees it, sending text-only data.
> (2) Over SSH, even if the keypress reaches Claude Code, `wl-paste` on the remote host cannot reach the local Wayland compositor.
> Problem 1 is fixable with a WezTerm keybinding change.
> Problem 2 requires a bridge mechanism: either a WezTerm callback that saves the image locally and uploads it, or OSC 52 extensions that don't yet exist in the ecosystem.

## Context

Pasting images from the system clipboard into Claude Code running inside tmux, often through an SSH session in WezTerm.
Confirmed: text paste works, image paste does not.
Confirmed: `wl-paste --type image/png` works locally inside tmux (1190 bytes returned).
Confirmed: pasting an image into Claude Code in a non-WezTerm terminal inside tmux works.

## How Claude Code Image Paste Works

Claude Code does **not** use terminal escape sequences for image paste.
When it detects a Ctrl+V keypress (via Ink/React terminal framework), it:

1. Runs `wl-paste -l` (Wayland) or `xclip -selection clipboard -t TARGETS -o` (X11) to detect image MIME types.
2. If an image type is found (`image/png`, `image/jpeg`, etc.), reads binary data via `wl-paste --type image/png`.
3. Processes with `sharp` (resize/compress to 800KB max), base64 encodes, attaches to conversation.

This is a **subprocess-based mechanism**.
Claude Code needs two things: the raw Ctrl+V keypress as a trigger, and a working `wl-paste` (or `xclip`) in the pane's environment.

## Problem 1: WezTerm Intercepts Ctrl+V

WezTerm's **default** keybindings include:

```lua
{ key = 'V', mods = 'CTRL', action = act.PasteFrom 'Clipboard' }
{ key = 'V', mods = 'SHIFT|CTRL', action = act.PasteFrom 'Clipboard' }
```

`PasteFrom 'Clipboard'` is **text-only**: it extracts text from the clipboard and sends it via bracketed paste.
If the clipboard contains only image data, this silently does nothing.
In either case, Claude Code never sees the raw Ctrl+V keypress, so its image detection handler never fires.

The current WezTerm config (`dot_config/wezterm/wezterm.lua`) has no custom key bindings.
The interception comes from WezTerm's built-in defaults.

**Fix:** Override Ctrl+V to pass through to the application:

```lua
config.keys = {
  -- Let Ctrl+V pass through so apps (Claude Code) can handle image paste directly.
  -- Text paste still available via Ctrl+Shift+V or Shift+Insert.
  { key = 'v', mods = 'CTRL', action = wezterm.action.SendKey { key = 'v', mods = 'CTRL' } },
}
```

NOTE(opus/tmux-image-paste): Alternatively, use `action = wezterm.action.DisableDefaultAssignment` to unbind without explicitly sending.
`SendKey` is more explicit about intent: we want the app to receive Ctrl+V.

**Trade-off:** Ctrl+V no longer pastes text in WezTerm.
Ctrl+Shift+V and Shift+Insert still paste text (WezTerm defaults).
This is acceptable since the config is "dumb terminal mode" with tmux handling everything.

Reference: [wezterm/wezterm#7272](https://github.com/wezterm/wezterm/issues/7272) confirmed this is the root cause for multiple users.

## Problem 2: SSH Breaks the `wl-paste` Path

When Claude Code runs on a remote host over SSH:

```
Local machine                         Remote machine (SSH)
┌─────────────┐                      ┌──────────────────────┐
│ WezTerm     │                      │ tmux                 │
│             │ ── SSH tunnel ──►    │  ┌──────────────────┐│
│ Wayland     │                      │  │ Claude Code      ││
│ compositor  │                      │  │                  ││
│ (clipboard) │  ✗ no path ✗         │  │ wl-paste → FAIL  ││
│             │                      │  │ (no compositor)  ││
└─────────────┘                      │  └──────────────────┘│
                                     └──────────────────────┘
```

`wl-paste` on the remote host has no `WAYLAND_DISPLAY` socket to connect to.
The clipboard lives on the local machine; the application lives on the remote machine.
No standard terminal protocol bridges this gap for images.

### Options for SSH Image Paste

**Option A: WezTerm `action_callback` bridge (most practical today)**

A WezTerm Lua callback bound to a key (e.g., Ctrl+V) that:
1. Detects image data on the local clipboard via `wl-paste -l`
2. Saves image to a local temp file via `wl-paste --type image/png > /tmp/clipboard.png`
3. Uploads to the remote host via `scp` or `wezterm cli` mechanisms
4. Pastes the remote file path into the pane via `pane:send_paste(remote_path)`

Claude Code accepts image file paths as input, so pasting a path like `/tmp/clipboard.png` works.

WARN(opus/tmux-image-paste): This approach requires detecting whether the active pane is a local or SSH session, and knowing the remote host/user for SCP.
The existing `lace-split` infrastructure already tracks per-pane SSH metadata (`@lace_port`, `@lace_user`), which could be leveraged.

**Option B: WezTerm PR #7621 (native, not yet merged)**

PR [wezterm/wezterm#7621](https://github.com/wezterm/wezterm/pull/7621) proposes built-in config options:
- `image_paste_local_path`: temp file path for local image saves
- `ssh_image_paste_remote_path`: remote path for SCP upload

This would handle the local-save-upload-paste flow natively.
Status: proposed, not yet merged.

**Option C: OSC 52 with image MIME type extension**

Kitty has `OSC 5252` which adds MIME type metadata to clipboard operations.
Neither WezTerm nor tmux support this yet.
If adopted, an inner application could request `image/png` from the outer terminal's clipboard.

**Option D: Manual workaround**

Save screenshot to file, transfer via `scp`, use Claude Code's `/image` command or drag-and-drop.
Functional but high-friction.

## tmux Considerations (Secondary)

tmux is not in the data path for either clipboard reads or keypresses (it forwards both).
However, two config improvements are still worthwhile:

### `update-environment` gap

The current list is missing `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`.
These are needed by `wl-paste`/`wl-copy` for local sessions.
After compositor restart or session reattach, stale values break clipboard access.

```sh
set -ga update-environment WAYLAND_DISPLAY
set -ga update-environment XDG_RUNTIME_DIR
```

### `allow-passthrough` persistence

Currently enabled at runtime but not in the config file.
Needed for image *display* (kitty graphics protocol, `wezterm imgcat --tmux-passthrough`), not paste.

```sh
set -g allow-passthrough on
```

## Recommendations

### Immediate (fixes local image paste)

1. Add WezTerm keybinding override to pass Ctrl+V through to applications.
2. Add `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` to tmux `update-environment`.
3. Persist `allow-passthrough on` in tmux config.

### Near-term (fixes SSH image paste)

4. Implement a WezTerm `action_callback` that bridges clipboard images over SSH.
   This could integrate with the existing lace per-pane SSH metadata.
   Alternatively, wait for WezTerm PR #7621 to land.

### Verification

```sh
# After WezTerm config change, verify Ctrl+V is no longer intercepted:
wezterm show-keys --lua | grep "'V'.*CTRL"
# Should NOT show PasteFrom for plain Ctrl+V

# After tmux config change:
tmux show-options -g update-environment | grep WAYLAND

# Test: copy an image, press Ctrl+V in Claude Code
# Local: should work immediately
# SSH: requires Option A/B above
```

## Related Issues

- [wezterm#7272](https://github.com/wezterm/wezterm/issues/7272): Pasting images (root cause confirmation)
- [wezterm#7621](https://github.com/wezterm/wezterm/pull/7621): Native image paste + SSH upload PR
- [claude-code#834](https://github.com/anthropics/claude-code/issues/834): Image paste support
- [claude-code#1361](https://github.com/anthropics/claude-code/issues/1361): Image paste issues
- [wezterm#4531](https://github.com/wezterm/wezterm/issues/4531): Kitty image protocol through tmux

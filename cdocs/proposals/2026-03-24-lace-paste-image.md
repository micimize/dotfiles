---
first_authored:
  by: "@claude-opus-4-6-20250725"
  at: 2026-03-24T12:30:00-07:00
task_list: tmux/image-paste-through
type: proposal
state: archived
status: implementation_accepted
tags: [tmux, clipboard, ssh, lace, wezterm, claude-code]
last_reviewed:
  status: revision_requested
  by: "@claude-opus-4-6-20250725"
  at: "2026-03-24T12:45:00-07:00"
  round: 1
---

# lace-paste-image: Context-Aware Image Paste Bridge

> BLUF: A new `lace-paste-image` script, bound to Ctrl+V in tmux, detects clipboard images and routes them context-aware: local panes pass through to the app (which calls `wl-paste` directly), SSH panes save the image locally, SCP it to the remote host using lace per-pane metadata, and paste the remote path as text.
> Requires one WezTerm config change: unbind Ctrl+V from `PasteFrom` so the keypress reaches tmux.
> Mirrors the existing `lace-split` pattern: same SSH detection, same metadata, same SCP options.

## Summary

The report at `cdocs/reports/2026-03-24-tmux-image-paste-through.md` identified two blockers for image paste into Claude Code through tmux:
1. WezTerm intercepts Ctrl+V before it reaches the application.
2. Over SSH, `wl-paste` on the remote host cannot reach the local Wayland compositor.

This proposal solves both by placing the routing logic at the tmux layer, matching the existing lace architecture where tmux is the "smart context-aware" layer and WezTerm is a dumb renderer.

> NOTE(opus/tmux-image-paste): Claude Code accepts image file paths as text input and detects them automatically.
> Pasting a path like `/tmp/lace-clipboard-1711302600.png` into the input triggers image attachment.
> This is the same mechanism the [tmux-paste-image](https://github.com/jkhas8/tmux-paste-image) plugin and WezTerm PR [#7621](https://github.com/wezterm/wezterm/pull/7621) use.

## Objective

Enable pasting clipboard images into terminal applications (primarily Claude Code) running in any tmux pane: local or SSH'd into a lace container.
The UX should be transparent: Ctrl+V just works regardless of context.

## Background

**How image paste works in Claude Code:**
Claude Code handles Ctrl+V by spawning `wl-paste -l` to detect image MIME types, then `wl-paste --type image/png` to read binary data.
This subprocess connects directly to the Wayland compositor, bypassing terminal I/O entirely.

**The SSH gap:**
Over SSH, the Wayland compositor is on the local machine but Claude Code runs remotely.
`wl-paste` on the remote host fails because there is no `$WAYLAND_DISPLAY` socket.
No standard terminal protocol (OSC 52, bracketed paste) supports image MIME types.

**Existing lace infrastructure:**
`lace-split` already solves the analogous "context-aware routing" problem for pane splits.
It checks `pane_current_command` for `ssh`, reads `@lace_port`/`@lace_user`/`@lace_workspace`, and constructs SSH/SCP commands with the lace SSH key and connection pooling.
`lace-paste-image` reuses all of this.

## Proposed Solution

### Architecture

```
Ctrl+V pressed in WezTerm
    │
    ▼ (WezTerm passes through, no longer intercepts)
tmux root binding: C-v → run-shell 'lace-paste-image #{pane_id}'
    │
    ├─ no image on clipboard?
    │   └─ send-keys C-v → app handles text paste normally
    │
    ├─ image + local pane?
    │   └─ send-keys C-v → app calls wl-paste directly
    │
    └─ image + SSH pane (lace metadata present)?
        ├─ wl-paste --type image/png > /tmp/lace-clipboard-XXXX.png
        ├─ scp -P $port /tmp/lace-clipboard-XXXX.png ${user}@localhost:/tmp/
        └─ send-keys "/tmp/lace-clipboard-XXXX.png" → app detects image path
```

### Components

**1. WezTerm config change** (`dot_config/wezterm/wezterm.lua`)

Override the default Ctrl+V binding so the keypress passes through to tmux:

```lua
config.keys = {
  { key = 'v', mods = 'CTRL', action = wezterm.action.SendKey { key = 'v', mods = 'CTRL' } },
}
```

Text paste remains available via Ctrl+Shift+V and Shift+Insert (WezTerm defaults).
This fits the config's stated "dumb terminal mode" philosophy.

**2. tmux binding** (`dot_config/tmux/tmux.conf`)

```tmux
bind -n C-v run-shell 'nu -c "lace-paste-image #{pane_id}"'
```

> NOTE(opus/tmux-image-paste): `run-shell` uses `/bin/sh`.
> Invoking `nu -c` avoids requiring a bash wrapper.
> Unlike the other lace scripts (bash), this uses nushell for legibility.

**3. `lace-paste-image` script** (new file in lace bin directory, Nushell)

> NOTE(opus/tmux-image-paste): Nushell for legibility, matching `lace-inspect`.
> tmux `run-shell` executes via `/bin/sh`, so the tmux binding invokes `nu lace-paste-image` explicitly.

```nu
#!/usr/bin/env nu

# Context-aware image paste: bridges clipboard images over SSH via SCP.
# Local panes: passes Ctrl+V through (app calls wl-paste directly).
# SSH panes with lace metadata: saves image locally, SCPs to remote, pastes path.
def main [pane_id: string] {
  let passthrough = { tmux send-keys -t $pane_id C-v }

  # Check clipboard for image MIME types (1s timeout guards against hung compositor)
  let mime_types = try { ^timeout 1s wl-paste -l | lines } catch { [] }
  let has_image = ($mime_types | any {|m| $m =~ '^image/(png|jpeg|gif|webp|bmp)$' })

  if not $has_image {
    do $passthrough
    return
  }

  # Detect whether pane is SSH'd into a lace container
  let current_cmd = (tmux display-message -t $pane_id -p '#{pane_current_command}' | str trim)

  if $current_cmd != "ssh" {
    do $passthrough  # local pane: app handles wl-paste directly
    return
  }

  # Read lace metadata (pane-level first, session-level fallback)
  let port = (lace-option $pane_id "@lace_port")
  let user = (lace-option $pane_id "@lace_user" | default "node")

  if ($port | is-empty) {
    do $passthrough  # no lace metadata: can't bridge
    return
  }

  # Save clipboard image to local temp file
  let local_path = $"/tmp/lace-clipboard-($pane_id)-((date now | format date '%s')).png"
  try { ^wl-paste --type image/png out> $local_path } catch {
    rm -f $local_path
    do $passthrough
    return
  }

  if not ($local_path | path exists) or (ls $local_path | get size.0) == 0 {
    rm -f $local_path
    do $passthrough
    return
  }

  # SCP to remote container (reuses lace SSH config and connection pool)
  let remote_path = $"/tmp/(($local_path | path basename))"
  let ssh_opts = [
    -o $"IdentityFile=($env.HOME)/.config/lace/ssh/id_ed25519"
    -o "IdentitiesOnly=yes"
    -o $"UserKnownHostsFile=($env.HOME)/.ssh/lace_known_hosts"
    -o "StrictHostKeyChecking=no"
    -o "ControlMaster=auto"
    -o $"ControlPath=($env.HOME)/.ssh/lace-ctrl-%C"
    -o "ControlPersist=600"
  ]

  let scp_result = try {
    ^scp -q ...$ssh_opts -P $port $local_path $"($user)@localhost:($remote_path)"
    true
  } catch { false }

  rm -f $local_path

  if not $scp_result {
    do $passthrough
    return
  }

  # Paste remote path as text: Claude Code detects image paths automatically
  tmux send-keys -t $pane_id $remote_path
}

# Read a tmux option: pane-level first, session-level fallback
def lace-option [pane_id: string, option: string] -> string {
  let pane_val = try {
    tmux show-option -pqv -t $pane_id $option | str trim
  } catch { "" }
  if ($pane_val | is-not-empty) { return $pane_val }

  try { tmux show-option -qv -t $pane_id $option | str trim } catch { "" }
}
```

### Data Flow for Each Case

**Case 1: No image on clipboard**
Ctrl+V → tmux → `lace-paste-image` detects no image → `send-keys C-v` → app receives Ctrl+V → app does its own text paste handling.

**Case 2: Image, local pane**
Ctrl+V → tmux → `lace-paste-image` detects image + local → `send-keys C-v` → app receives Ctrl+V → app calls `wl-paste --type image/png` → image attached.

**Case 3: Image, SSH pane with lace metadata**
Ctrl+V → tmux → `lace-paste-image` detects image + SSH → saves image locally → SCPs to remote → `send-keys "/tmp/lace-clipboard-XXXX.png"` → app detects image path → image attached.

**Case 4: Image, SSH pane without lace metadata**
Ctrl+V → tmux → `lace-paste-image` detects image + SSH + no `@lace_port` → `send-keys C-v` → app receives Ctrl+V → app tries `wl-paste` (fails on remote) → no image pasted.
This is the correct degradation: we can't bridge without connection metadata.

## Important Design Decisions

**tmux layer, not WezTerm layer.**
WezTerm's stated role in this config is "dumb rendering terminal."
All context-aware routing lives in tmux via lace scripts.
This is terminal-emulator agnostic: switching from WezTerm to another terminal only requires ensuring Ctrl+V passes through.

**Reuse lace SSH config exactly.**
Same SSH key, known hosts, control socket, and user defaults as `lace-split`.
The SCP uses the existing connection pool (`ControlPath`), so the transfer is near-instant for established sessions.

**Graceful degradation at every step.**
If any detection or transfer step fails, the script falls back to `send-keys C-v`.
The worst case is "image paste doesn't work over SSH" which is the current behavior.
Text paste is never broken.

**Image path as text, not Ctrl+V on remote.**
Sending Ctrl+V to an SSH pane would trigger Claude Code's image paste handler on the remote side, where `wl-paste` fails.
Sending the file path as text lets Claude Code's path detection handle it.

**Timestamp-based temp file naming.**
Simple, avoids collisions for rapid pastes, easy to glob for cleanup.
Both local and remote use the same path for traceability.

**PNG only for the bridge.**
`wl-paste --type image/png` converts most clipboard image types to PNG.
This simplifies the SCP path (single known extension) and Claude Code's detection.

## Edge Cases / Challenging Scenarios

**Clipboard has both image and text.**
Wayland clipboards can have multiple MIME types simultaneously (e.g., copying an image in a browser also sets text/html and text/plain).
The script checks for image MIME types first.
If an image type is present and the pane is SSH, it takes the image bridge path.
If the pane is local, Ctrl+V passes through regardless: Claude Code's own handler makes the image-vs-text decision.
This means the image-priority heuristic only applies to SSH panes where we must choose proactively.
If the user wanted text in an SSH pane when image is also present, Ctrl+Shift+V (WezTerm text paste) still works.

> NOTE(opus/tmux-image-paste): This is a conscious trade-off.
> The alternative (always pass through, never bridge) would mean SSH image paste never works.
> The escape hatch (Ctrl+Shift+V for text) is always available.

**Large images.**
`wl-paste` streams the full image; SCP transfers it.
Claude Code compresses images to 800KB max internally, so large originals are handled downstream.
No size limit needed in the script.

**Rapid successive pastes.**
Timestamp resolution is 1 second.
Two pastes within the same second would collide.
Mitigation: use `mktemp` pattern (`lace-clipboard-XXXXXX.png`) instead of raw timestamp.
This is a minor refinement for the implementation.

**Non-lace SSH panes.**
Panes SSH'd manually (not via lace-into) won't have `@lace_port` metadata.
The script correctly falls back to `send-keys C-v`.
A future enhancement could detect SSH target from the process args, but this is out of scope.

**tmux copy mode.**
When in copy mode, tmux intercepts C-v for `rectangle-toggle` (vi mode).
`lace-paste-image` only fires in the root key table, not copy-mode-vi.
No conflict.

**Temp file cleanup.**
Local temp files are removed immediately after SCP.
Remote temp files accumulate in `/tmp/` and are cleaned by the OS tmpfiles timer.
An optional cleanup sweep (e.g., remove `lace-clipboard-*` older than 24 hours) could be added to `lace-disconnect-pane` or as a periodic tmux hook.

**wl-paste not installed.**
Script requires `wl-paste`.
If absent, the `wl-paste -l` call fails, `mime_types` is empty, and we fall through to `send-keys C-v`.
Degradation is clean.

## Test Plan

**Unit tests (manual verification):**

1. **No image, local pane:** Copy text to clipboard, press Ctrl+V in Claude Code. Text paste should work normally.
2. **Image, local pane:** Copy screenshot, press Ctrl+V in Claude Code. Image should attach.
3. **Image, SSH pane (lace):** Copy screenshot, Ctrl+V in a lace-into session running Claude Code. Remote path should appear, Claude Code should detect the image.
4. **Image, SSH pane (no lace):** Copy screenshot, Ctrl+V in a manual SSH pane. Falls back to passthrough (image paste fails gracefully).
5. **No image, SSH pane:** Copy text, Ctrl+V in SSH pane. Text paste works normally.
6. **Ctrl+Shift+V still works:** Text paste via Ctrl+Shift+V should work in all contexts (handled by WezTerm, never touches the tmux binding).

**Verify no regressions:**

7. **tmux copy mode:** Enter copy mode (Alt+C), press Ctrl+V. Should toggle rectangle select, not trigger `lace-paste-image`.
8. **vim in pane:** Ctrl+V in normal vim (local). Should enter visual block mode as expected.
9. **Non-tmux context:** WezTerm without tmux (if ever used). Ctrl+V passes through to the shell.

## Verification Methodology

```bash
# Verify WezTerm no longer intercepts Ctrl+V:
wezterm show-keys --lua | grep "'v'.*CTRL" | grep -v SHIFT
# Should show SendKey, not PasteFrom

# Verify tmux binding exists:
tmux list-keys | grep "C-v"
# Should show: bind-key -T root C-v run-shell 'lace-paste-image ...'

# Verify script is on PATH:
which lace-paste-image

# Verify clipboard detection works:
wl-paste -l | grep image  # after copying a screenshot

# Verify SCP works to a lace container:
# In a lace-into session, check @lace_port:
tmux show-option -pqv @lace_port
# Then manually test SCP with the same options
```

## Implementation Phases

### Phase 1: WezTerm Ctrl+V Passthrough

**Files:** `dot_config/wezterm/wezterm.lua`

Add a `config.keys` table that overrides the default Ctrl+V binding:

```lua
config.keys = {
  { key = 'v', mods = 'CTRL', action = wezterm.action.SendKey { key = 'v', mods = 'CTRL' } },
}
```

**Validation:** Follow the WezTerm validation workflow from CLAUDE.md.
Verify via `show-keys` that Ctrl+V no longer maps to `PasteFrom`.
Verify Ctrl+Shift+V still works for text paste.

### Phase 2: tmux Environment Propagation

**Files:** `dot_config/tmux/tmux.conf`

This is prerequisite infrastructure: `wl-paste` needs correct `WAYLAND_DISPLAY` to function after tmux reattach.

Add `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` to `update-environment` so `wl-paste` survives session reattach:

```tmux
set -ga update-environment WAYLAND_DISPLAY
set -ga update-environment XDG_RUNTIME_DIR
```

Persist `allow-passthrough` (currently runtime-only, needed for image display protocols):

```tmux
set -g allow-passthrough on
```

**Validation:** Detach and reattach tmux. Verify `echo $WAYLAND_DISPLAY` still shows the correct value. Verify `wl-paste -l` works after reattach.

### Phase 3: `lace-paste-image` Script

**Files:** New Nushell script in lace bin directory (alongside `lace-split`, `lace-disconnect-pane`)

Write the script in Nushell (matching `lace-inspect` convention):
- `def main [pane_id: string]` entry point
- SSH detection via `pane_current_command`
- `lace-option` helper for two-tier metadata lookup (pane then session)
- 1-second `timeout` on `wl-paste -l` to prevent hung compositor blocking all paste
- `try/catch` for SCP errors (Nushell's structured error handling replaces bash `set -e` patterns)
- `do $passthrough` closure for fallback at every failure point
- Temp file naming includes pane ID and epoch timestamp

**Validation:** Run manually with `nu lace-paste-image %123`.
Test each branch: no image, local+image, SSH+image, SSH+no-metadata.

### Phase 4: tmux Binding and End-to-End

**Files:** `dot_config/tmux/tmux.conf`

Add root-table binding:

```tmux
# Image paste: context-aware via lace-paste-image.
# If clipboard has an image and pane is SSH'd: saves locally, SCPs to remote, pastes path.
# Otherwise: passes Ctrl+V through to the application.
bind -n C-v run-shell 'nu -c "lace-paste-image #{pane_id}"'
```

Place alongside the other lace bindings (after the Alt+HJKL split bindings).

**Validation:** `tmux list-keys | grep C-v` shows the binding.
Full end-to-end test: copy screenshot, Ctrl+V in local Claude Code, then in SSH Claude Code.

---
title: "WezTerm Screenshot Iteration Loop: Automated Font Rendering Tuning"
date: 2026-02-22
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-22T10:30:00-06:00"
task_list: dotfiles/wezterm
type: report
state: live
status: draft
tags: [wezterm, font-rendering, screenshot, automation, kde, wayland, iteration-loop]
---

# WezTerm Screenshot Iteration Loop: Automated Font Rendering Tuning

> BLUF: A complete config-change-screenshot-analyze loop is achievable on this system
> using three tools already installed: `wezterm --config-file` with `--class` for isolated
> launches, a KWin D-Bus script to activate the target window, and `spectacle -a -b` for
> Wayland-compatible active-window capture. The full cycle takes approximately 5 seconds.
> WezTerm has no built-in screenshot capability, and Wayland prevents direct window-targeted
> screenshots, so the KWin activation step is essential. A working proof-of-concept script
> is included below.

## System Inventory

| Component | Value |
|-----------|-------|
| Display server | Wayland (`wayland-0`) with XWayland (`:0`) |
| Compositor | KWin Wayland (`kwin_wayland`) |
| Desktop | KDE Plasma |
| Resolution | 3840x2160 @ 96 DPI |
| WezTerm version | 20240203-110809-5046fc22 |
| Screenshot tool | Spectacle 6.5.5 |
| Window manipulation | ImageMagick `import` (X11 only), `ydotool` (daemon not running) |
| Available but not useful | `kstart` (launcher only), `xprop` (X11 only for native Wayland windows) |
| Not installed | `grim`, `slurp`, `scrot`, `xdotool`, `wmctrl`, `kdotool`, `wlrctl` |

## The Core Problem: Wayland Window Targeting

On X11, tools like `import -window <id>` or `scrot -u` can capture a specific window by
ID. Wayland forbids this -- applications cannot enumerate or interact with other
applications' windows. Only the compositor (KWin) can.

This means any automated screenshot workflow on Wayland must route through the compositor.
Three approaches exist on this system:

1. **KWin scripting + spectacle** (tested, works) -- activate target window via D-Bus
   script, then capture active window with spectacle
2. **KWin ScreenShot2 D-Bus API** (available but complex) -- call `CaptureActiveWindow`
   directly via `gdbus`, but requires pipe fd management in bash
3. **XDG Desktop Portal** (`org.freedesktop.portal.Screenshot`) -- requires interactive
   confirmation dialog, unusable for automation

## Approach 1: KWin Script + Spectacle (Recommended)

This is the tested and proven approach. It uses three steps:

### Step 1: Launch WezTerm with a Unique Class

```bash
wezterm --config-file "$CONFIG" \
  start --class "org.wezfurlong.wezterm.fonttest" \
  --always-new-process \
  -- bash -c "$SAMPLE_TEXT_COMMAND; sleep 30" &
WEZ_PID=$!
sleep 3  # Wait for window to render
```

Key flags:
- `--config-file` loads the experimental config without touching the deployed one
- `--class` sets a unique Wayland `app_id` so KWin can distinguish this window
- `--always-new-process` prevents attaching to the existing wezterm GUI instance
- The inner command prints sample text then sleeps to keep the window open

### Step 2: Activate the Target Window via KWin Script

```bash
cat > /tmp/kwin_activate.js << 'JS'
var targetClass = "org.wezfurlong.wezterm.fonttest";
var clients = workspace.windowList();
for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    if (c.resourceClass === targetClass) {
        workspace.activeWindow = c;
    }
}
JS

dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
  /Scripting org.kde.kwin.Scripting.unloadScript string:"activate_fonttest" \
  >/dev/null 2>&1

LOAD_RESULT=$(dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
  /Scripting org.kde.kwin.Scripting.loadScript \
  string:"/tmp/kwin_activate.js" string:"activate_fonttest" 2>&1)

SCRIPT_NUM=$(echo "$LOAD_RESULT" | grep int32 | awk '{print $2}')

dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
  "/Scripting/Script${SCRIPT_NUM}" org.kde.kwin.Script.run >/dev/null 2>&1

sleep 1  # Wait for activation to take effect
```

This is necessary because launching wezterm from within another wezterm session does NOT
guarantee the new window receives focus. The launching terminal retains focus.

### Step 3: Screenshot the Active Window

```bash
spectacle -a -b -n -e -o /tmp/fonttest_screenshot.png
sleep 1  # Spectacle writes asynchronously
```

Flags: `-a` active window, `-b` background (no GUI), `-n` no notification, `-e` no
decorations, `-o` output file.

### Step 4: Clean Up

```bash
kill $WEZ_PID 2>/dev/null
wait $WEZ_PID 2>/dev/null
dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
  /Scripting org.kde.kwin.Scripting.unloadScript string:"activate_fonttest" \
  >/dev/null 2>&1
```

## Complete Iteration Script

```bash
#!/usr/bin/env bash
# wezterm-font-iteration.sh -- Change config, screenshot, repeat
set -euo pipefail

CONFIG="${1:?Usage: $0 <config-file> [output-dir]}"
OUTPUT_DIR="${2:-/tmp/wezterm-fonttest}"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCREENSHOT="$OUTPUT_DIR/font-$TIMESTAMP.png"
CLASS="org.wezfurlong.wezterm.fonttest"

# --- Sample text command ---
read -r -d '' SAMPLE_CMD << 'SAMPLE' || true
echo "=== Font Rendering Test ==="
echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"
echo "0123456789 !@#$%^&*() {}[]|\;:,.<>?"
echo 'fn main() { let x = 42; println!("Hello, world!"); }'
echo 'if __name__ == "__main__": print("test")'
echo ""
echo "== Ligatures =="
echo "fi fl ff ffi ffl -> => !== === >= <="
echo ""
echo "== Box Drawing =="
echo "┌──────┬──────┐"
echo "│ left │ right│"
echo "├──────┼──────┤"
echo "│  A   │  B   │"
echo "└──────┴──────┘"
echo ""
echo "-- Variant $TIMESTAMP --"
sleep 30
SAMPLE

# --- KWin activation script ---
cat > /tmp/kwin_activate_fonttest.js << JS
var clients = workspace.windowList();
for (var i = 0; i < clients.length; i++) {
    if (clients[i].resourceClass === "$CLASS") {
        workspace.activeWindow = clients[i];
    }
}
JS

# --- Step 1: Validate config parses ---
echo "Validating config..."
wezterm --config-file "$CONFIG" ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
if grep -q ERROR /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR:"
    grep ERROR /tmp/wez_stderr.txt
    exit 1
fi
echo "Config OK"

# --- Step 2: Launch wezterm ---
echo "Launching wezterm..."
wezterm --config-file "$CONFIG" \
    start --class "$CLASS" --always-new-process \
    -- bash -c "$SAMPLE_CMD" &
WEZ_PID=$!
sleep 3

# --- Step 3: Activate window via KWin ---
echo "Activating window..."
dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
    /Scripting org.kde.kwin.Scripting.unloadScript \
    string:"activate_fonttest" >/dev/null 2>&1 || true

LOAD_RESULT=$(dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
    /Scripting org.kde.kwin.Scripting.loadScript \
    string:"/tmp/kwin_activate_fonttest.js" string:"activate_fonttest" 2>&1)
SCRIPT_NUM=$(echo "$LOAD_RESULT" | grep int32 | awk '{print $2}')
dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
    "/Scripting/Script${SCRIPT_NUM}" org.kde.kwin.Script.run >/dev/null 2>&1
sleep 1

# --- Step 4: Screenshot ---
echo "Taking screenshot..."
spectacle -a -b -n -e -o "$SCREENSHOT" 2>/dev/null
sleep 1

# --- Step 5: Cleanup ---
kill "$WEZ_PID" 2>/dev/null
wait "$WEZ_PID" 2>/dev/null || true
dbus-send --session --dest=org.kde.KWin --type=method_call --print-reply \
    /Scripting org.kde.kwin.Scripting.unloadScript \
    string:"activate_fonttest" >/dev/null 2>&1 || true

echo "Screenshot saved: $SCREENSHOT"
echo "Total images in $OUTPUT_DIR: $(ls "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l)"
```

## WezTerm Config Overrides for Font Testing

WezTerm's `--config` flag allows inline overrides without editing the config file. This
enables rapid A/B testing:

```bash
# Test different font sizes
wezterm --config-file base.lua --config 'font_size=12.0' start ...
wezterm --config-file base.lua --config 'font_size=14.0' start ...

# Test different fonts
wezterm --config-file base.lua --config 'font=wezterm.font("JetBrains Mono")' start ...
wezterm --config-file base.lua --config 'font=wezterm.font("Fira Code")' start ...

# Test freetype load target (hinting)
wezterm --config-file base.lua --config 'freetype_load_target="Light"' start ...
wezterm --config-file base.lua --config 'freetype_load_target="Normal"' start ...

# Window size
wezterm --config-file base.lua --config 'initial_cols=100' --config 'initial_rows=30' start ...
```

These override any value set in the Lua config file.

## Approach 2: KWin ScreenShot2 D-Bus (Alternative)

KWin exposes `org.kde.KWin.ScreenShot2` at `/org/kde/KWin/ScreenShot2` with methods:

| Method | Input | Notes |
|--------|-------|-------|
| `CaptureActiveWindow` | `options: a{sv}`, `pipe: h` | Captures the focused window |
| `CaptureWindow` | `handle: s`, `options: a{sv}`, `pipe: h` | Captures by UUID |
| `CaptureArea` | `x, y, width, height`, `options`, `pipe` | Captures a screen region |
| `CaptureScreen` | `name: s`, `options`, `pipe` | Captures a named output |

The `pipe` parameter requires creating a Unix pipe fd and passing it via D-Bus fd passing.
This is straightforward in Python but awkward in bash. A Python helper would look like:

```python
import subprocess, os
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
r, w = os.pipe()
# Call CaptureActiveWindow with the write end as the pipe fd
# Read PNG data from the read end
```

This approach bypasses spectacle entirely but requires `python3-gobject` (not currently
installed). It also still requires the KWin activation step to target a specific window
unless you have the window's internal UUID.

## Limitations and Caveats

### Window Position on Wayland

WezTerm's `--position` flag is documented but ineffective on Wayland:

> Note that Wayland does not allow applications to control window positioning.

The compositor controls placement. The window appears wherever KWin decides. For
consistent screenshots, this is acceptable since spectacle captures just the window,
not its position on screen.

### Spectacle Captures the Active Window at Call Time

There is a TOCTOU (time-of-check-time-of-use) gap between the KWin activation script
and the spectacle capture. If the user clicks another window in that 1-second sleep,
spectacle captures the wrong window. Mitigations:

- Keep the sleep short (1 second is enough for KWin activation)
- Run the script when not actively using the desktop
- Consider using `CaptureActiveWindow` via D-Bus instead (atomic)

### xkbcommon Warnings

WezTerm emits harmless `dead_hamza` keysym warnings on stderr when launching. These are
from the system's compose table and do not affect functionality. Suppress with
`2>/dev/null` on the wezterm launch command.

### KWin Script Output

`print()` and `console.log()` from KWin scripts should appear in the systemd journal
under `kwin_wayland`, but on this system the output does not reliably appear. This makes
debugging KWin scripts difficult. The scripts work despite the invisible output.

### Multiple Test Instances

If a previous test wezterm with the same `--class` is still running, the KWin activation
script activates whichever one KWin finds first. Always kill the previous instance before
launching a new one. The cleanup step in the script handles this.

## Tool Installation Notes

For a more robust setup, these packages would help but are not required:

| Package | Purpose | Install |
|---------|---------|---------|
| `grim` + `slurp` | wlroots-native Wayland screenshot (may not work with KWin) | `sudo dnf install grim slurp` |
| `python3-gobject` | GObject introspection for direct KWin D-Bus calls | `sudo dnf install python3-gobject` |
| `kdotool` | xdotool-like window management for KDE Wayland | `sudo dnf install kdotool` |

None are strictly necessary -- the KWin script + spectacle approach works with what is
already installed.

## Recommended Workflow

1. Create a base config with the font settings to test in `/tmp/wezterm_fonttest.lua`
2. Run the iteration script: `./wezterm-font-iteration.sh /tmp/wezterm_fonttest.lua`
3. Edit the config, run again -- screenshots accumulate in `/tmp/wezterm-fonttest/`
4. Compare screenshots side by side to evaluate font rendering changes
5. Once satisfied, port the settings to `dot_config/wezterm/wezterm.lua`
6. Validate with the standard wezterm validation workflow from `CLAUDE.md`

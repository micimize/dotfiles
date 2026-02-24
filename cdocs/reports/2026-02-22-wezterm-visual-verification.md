---
title: "WezTerm Visual Verification: Programmatic Screenshot Capture and AI Analysis"
date: 2026-02-22
first_authored:
  by: "@claude-opus-4-6"
  at: "2026-02-22T14:00:00-06:00"
task_list: dotfiles/wezterm
type: report
state: live
status: draft
tags: [wezterm, visual-verification, screenshot, spectacle, font-tuning, automation, wayland, skill-candidate]
---

# WezTerm Visual Verification: Programmatic Screenshot Capture and AI Analysis

> BLUF: AI agents can visually verify WezTerm config changes by launching isolated test
> windows that capture themselves with `spectacle -b -a`. The self-capture pattern solves
> the Wayland focus problem: the test window runs spectacle internally, guaranteeing it
> captures its own content regardless of which window the compositor considers active.
> Environment variables select between config variants, enabling rapid A/B comparison
> without editing files between runs. Claude Code's multimodal capabilities then analyze
> the resulting PNGs directly. This technique was proven during a font-tuning session and
> should become a reusable `/wezterm-visual-test` skill.

## The Self-Capture Insight

The central problem on Wayland is that applications cannot target other applications'
windows for screenshot. When an agent launches a new WezTerm window from an existing
terminal, the launching terminal often retains compositor focus. Running `spectacle -a`
from the agent's terminal captures the agent's terminal, not the test window.

The solution: have the test window run spectacle on itself. Since the test window's shell
has focus within that window, and spectacle captures the active window, the test window
captures its own rendering. No KWin scripting, no D-Bus activation, no race conditions.

This is simpler than the KWin script approach documented in the companion report
(`2026-02-22-wezterm-screenshot-iteration.md`). The KWin approach remains useful when
the agent needs to capture an already-running window, but for purpose-built test windows,
self-capture is superior.

## Environment and Prerequisites

| Component | Value |
|-----------|-------|
| OS | ublue Aurora (Fedora-based, immutable) |
| Display server | Wayland (KDE Plasma, KWin compositor) |
| Resolution | 3840x2160 @ 96 DPI |
| Screenshot tool | Spectacle (pre-installed on KDE) |
| Config management | chezmoi, source at `dot_config/wezterm/wezterm.lua` |
| AI capabilities | Claude Code reads PNG files via multimodal vision |

No additional packages are required. Everything needed is already installed.

## Technique: Step by Step

### Step 1: Write a Test Harness Config

Create a minimal, isolated config file at `/tmp/wez_fonttest.lua`. Use environment
variables to switch between variants without editing the file between runs.

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()
local variant = os.getenv("WEZ_FONT_VARIANT") or "1"

-- Minimal window: no tab bar, small size for compact screenshots
config.font_size = 10.0
config.color_scheme = "Solarized Dark (Gogh)"
config.colors = { background = "#232323" }
config.initial_cols = 100
config.initial_rows = 12
config.enable_tab_bar = false

local variants = {
  ["1"] = {
    name = "JetBrains Mono Medium + NO_HINTING",
    font = wezterm.font("JetBrains Mono", { weight = "Medium" }),
    load_flags = "NO_HINTING",
  },
  ["2"] = {
    name = "JetBrains Mono DemiBold + NO_HINTING",
    font = wezterm.font("JetBrains Mono", { weight = "DemiBold" }),
    load_flags = "NO_HINTING",
  },
  ["3"] = {
    name = "JetBrains Mono Medium + DEFAULT (hinted)",
    font = wezterm.font("JetBrains Mono", { weight = "Medium" }),
    load_flags = "DEFAULT",
  },
}

local v = variants[variant]
if v then
  config.font = v.font
  config.freetype_load_flags = v.load_flags
end

return config
```

Key design choices:

- **`enable_tab_bar = false`** removes visual noise from screenshots.
- **Small `initial_cols` and `initial_rows`** produce compact, focused captures.
- **Environment variable selection** allows the launch script to iterate variants
  without touching the config file.
- **Isolated from real config** -- the test harness does not import or reference
  `dot_config/wezterm/wezterm.lua`. Test failures cannot break the real config.

### Step 2: Write a Self-Capture Launch Script

The test window prints sample text, waits for rendering to settle, then calls spectacle
on itself.

```bash
#!/usr/bin/env bash
# wez-selfcap.sh -- Launch a WezTerm test window that screenshots itself
set -euo pipefail

V="${1:?Usage: $0 <variant-number>}"
export WEZ_FONT_VARIANT="$V"
OUT="/tmp/wez_font_v${V}.png"
CONFIG="/tmp/wez_fonttest.lua"

# Validate config before launching
wezterm --config-file "$CONFIG" ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
if grep -q ERROR /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR:"
    cat /tmp/wez_stderr.txt
    exit 1
fi

# Inner command: print sample text, wait, self-capture, exit
INNER='
echo "=== Font Rendering Test ==="
echo "The quick brown fox jumps over the lazy dog."
echo "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz"
echo "0123456789 !@#$%^&*() {}[]|\;:,.<>?"
echo "fn main() { let x = 42; println!(\"Hello, world!\"); }"
echo "if __name__ == \"__main__\": print(\"test\")"
echo ""
echo "== Ligatures =="
echo "fi fl ff ffi ffl -> => !== === >= <="
echo ""
echo "-- Variant '"$V"' --"
sleep 1
spectacle -b -a -o "'"$OUT"'" -d 200 2>/dev/null
sleep 1
'

wezterm --config-file "$CONFIG" start --always-new-process -- bash -c "$INNER" &
WEZ_PID=$!

# Wait for the window to render, capture, and exit
sleep 5

# Clean up if the window is still running
kill "$WEZ_PID" 2>/dev/null || true
wait "$WEZ_PID" 2>/dev/null || true

if [ -f "$OUT" ]; then
    echo "Screenshot saved: $OUT"
else
    echo "ERROR: Screenshot not created"
    exit 1
fi
```

Critical details:

- **`spectacle -b`** runs in background mode (no GUI).
- **`spectacle -a`** captures the active window. Since the test window's shell is
  running spectacle, the test window is the active window.
- **`-d 200`** adds a 200ms delay for rendering to fully settle.
- **`sleep 1` before spectacle** gives WezTerm time to render all text output.
- **`sleep 1` after spectacle** gives spectacle time to write the file to disk.
- **`--always-new-process`** prevents the test window from attaching to the running
  WezTerm GUI instance.

### Step 3: Run Variants and Analyze with Claude Code

Execute the script for each variant, then read the PNGs directly.

```bash
bash /tmp/wez-selfcap.sh 1
bash /tmp/wez-selfcap.sh 2
bash /tmp/wez-selfcap.sh 3
```

The agent then reads the screenshots using its multimodal vision:

```
Read /tmp/wez_font_v1.png
Read /tmp/wez_font_v2.png
Read /tmp/wez_font_v3.png
```

Claude Code can evaluate:

- **Character weight and readability** -- is the text too thin, too bold?
- **Hinting quality** -- are characters crisp or blurry at the target size?
- **Ligature rendering** -- do programming ligatures display correctly?
- **Box drawing** -- do line-drawing characters connect without gaps?
- **Overall contrast** -- is the text distinguishable from the background?

### Step 4: Verify the Deployed Config

After choosing a variant and applying its settings to the real config, verify the
deployed result matches expectations.

```bash
wezterm --config-file dot_config/wezterm/wezterm.lua \
  start --always-new-process -- bash -c '
echo "=== Deployed Config Verification ==="
echo "The quick brown fox jumps over the lazy dog."
echo "fn main() { let x = 42; }"
sleep 1
spectacle -b -a -o /tmp/wez_deployed.png -d 200 2>/dev/null
sleep 1
'
sleep 5
```

Then read `/tmp/wez_deployed.png` to confirm the deployed config matches the chosen
variant.

## Findings from the Font-Tuning Session

These findings were discovered during the session that proved this technique.

### Config Field Pitfalls

- **`window_title` is NOT a valid WezTerm config field.** Attempting to set it crashes
  config evaluation. WezTerm sets window titles dynamically via the `format-window-title`
  event, not through a static config field.
- **`harfbuzz_features` is a top-level `config` setting**, not a per-font attribute in
  `TextStyleAttributes`. Set `config.harfbuzz_features = { "calt=1", "liga=1" }`, not as
  a field on the font object.

### Reload Behavior

- **`freetype_load_flags` changes require a full WezTerm restart.** They do not take
  effect via hot-reload. The test window approach naturally handles this since each
  variant launches a fresh WezTerm process.
- **Font family and weight changes DO hot-reload.** Changes to `config.font` are picked
  up when WezTerm detects the config file has changed.

### Screenshot Quality

- **Active-window capture produces well-cropped images.** No compositor decorations, no
  desktop background, just the terminal content.
- **Full-screen capture (`spectacle -f`) is a fallback** if active-window fails, but
  produces images where the test window occupies a small portion of 3840x2160.
- **The 200ms spectacle delay (`-d 200`) is sufficient** for text rendering to complete.
  Shorter delays risk capturing partially-rendered frames.

### Timing

- **1 second after text output** before spectacle is the minimum safe wait. WezTerm
  renders text asynchronously; capturing immediately after `echo` may show an empty or
  partial window.
- **5 seconds total** from launch to cleanup is reliable. The window needs approximately
  3 seconds to start, render, and be ready for capture.

## Comparison with KWin Script Approach

The companion report (`2026-02-22-wezterm-screenshot-iteration.md`) documents a KWin
D-Bus scripting approach that activates a target window by its `--class` identifier,
then captures it with `spectacle -a`.

| Aspect | Self-Capture | KWin Script |
|--------|-------------|-------------|
| Complexity | Low (no D-Bus, no KWin scripts) | Medium (D-Bus calls, JS scripting) |
| Focus reliability | Guaranteed (spectacle runs inside target) | Race condition possible |
| Captures existing windows | No (window must be purpose-built) | Yes |
| Cleanup | Minimal (just kill the process) | Must unload KWin scripts |
| Dependencies | spectacle only | spectacle + D-Bus + KWin scripting API |

Use self-capture for purpose-built test windows. Use KWin scripting when capturing
an already-running window that was not launched with self-capture capability.

## Pitfalls and Mitigations

### Silent Config Fallback Produces Misleading Screenshots

If the test harness config contains an invalid field (like `window_title`), WezTerm
silently falls back to all defaults. The test window opens and renders text, but with
the default font, not the configured one. The screenshot looks valid but shows the wrong
rendering.

**Mitigation:** Always validate the config with `ls-fonts` stderr before launching.

```bash
wezterm --config-file /tmp/wez_fonttest.lua ls-fonts 2>/tmp/wez_stderr.txt 1>/dev/null
if grep -q ERROR /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR:"; cat /tmp/wez_stderr.txt
    exit 1
fi
```

### Wayland Focus Uncertainty

On Wayland, the compositor decides which window has focus. If the user clicks another
window between the test window opening and spectacle running, spectacle captures the
wrong window.

**Mitigation:** The self-capture pattern minimizes this window. The inner script runs
spectacle immediately after a 1-second render delay. The user would need to click
another window within that exact second.

### Test Window Lingers on Failure

If the script crashes or spectacle fails, the test WezTerm window stays open
indefinitely (the inner `sleep 30` or similar keeps it alive).

**Mitigation:** The launch script uses `kill $WEZ_PID` in cleanup. For additional
safety, set a shorter inner sleep or use `timeout` on the wezterm launch.

### Multiple Monitors

On multi-monitor setups, the test window may appear on a monitor other than the one
the agent expects. `spectacle -a` captures the active window regardless of which monitor
it is on, so the screenshot is still correct.

## Future Skill Design: `/wezterm-visual-test`

This technique should become a reusable skill with the following interface.

### Input

```
/wezterm-visual-test variants="Medium+NO_HINTING, DemiBold+NO_HINTING, Medium+DEFAULT"
```

Or, for testing the deployed config:

```
/wezterm-visual-test deployed
```

### Automated Steps

1. **Parse variant specifications** into a test harness config with environment-variable
   switching.
2. **Validate each variant** with `ls-fonts` stderr check before launching.
3. **Launch each variant** in sequence, self-capturing to numbered PNG files.
4. **Read all PNGs** using Claude Code's multimodal vision.
5. **Present a comparison** with per-variant observations and a recommendation.
6. **Clean up** all temporary files, test configs, and lingering processes.

### Scope Boundaries

The skill should handle:

- Font family, weight, and size comparisons
- `freetype_load_flags` and `freetype_load_target` variations
- `harfbuzz_features` toggling
- Color scheme and background color testing
- Any config property that affects visual rendering

The skill should NOT handle:

- Key binding verification (use `show-keys` diff instead)
- Non-visual config changes (use `ls-fonts` validation)
- Changes that require user interaction to verify (use `action_callback` manual testing)

### Sample Text Requirements

The sample text should exercise:

- Uppercase and lowercase alphabet (weight and shape)
- Digits and punctuation (kerning and spacing)
- Programming constructs with brackets and operators (practical readability)
- Ligature sequences (`->`, `=>`, `!==`, `===`, `>=`, `<=`)
- Box-drawing characters (glyph alignment)
- A variant identifier label (which screenshot is which)

## Related Documents

- `cdocs/reports/2026-02-22-wezterm-screenshot-iteration.md` -- KWin script approach
  for window activation and capture
- `CLAUDE.md` -- WezTerm validation workflow (ls-fonts, show-keys diff)

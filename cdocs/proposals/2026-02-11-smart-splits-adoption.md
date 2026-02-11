---
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T21:15:00-05:00
task_list: dotfiles/wezterm-neovim-navigation
type: proposal
state: live
status: implementation_wip
tags: [wezterm, neovim, navigation, smart-splits, keybindings]
---

# Adopt smart-splits.nvim for Seamless WezTerm/Neovim Pane Navigation

> BLUF: Install [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) and update the WezTerm keybindings to enable seamless `Ctrl+h/j/k/l` navigation across both Neovim splits and WezTerm panes. This restores the vim-tmux-navigator experience lost in the tmux-to-wezterm migration. The change touches two files (`wezterm.lua` and a new `navigation.lua` plugin spec), preserves all existing keybinding muscle memory, and requires no lazy-loading. Each phase is verified by automated headless tests (Neovim: `cquit`-based Lua assertion suite; WezTerm: 4-layer `luac`/`ls-fonts`/`show-keys`/`cli` stack), with manual verification only for the `action_callback` IPC path that cannot be exercised programmatically. See [options analysis report](../reports/2026-02-11-wezterm-neovim-pane-navigation.md) for the full landscape evaluation and [Playwright for Neovim](../reports/2026-02-11-playwright-for-neovim.md) / [Playwright for WezTerm](../reports/2026-02-11-playwright-for-wezterm.md) for the testing methodology.

## Objective

Eliminate the keybinding collision where WezTerm intercepts `Ctrl+h/j/k/l` before Neovim, making it impossible to navigate between Neovim splits when running inside a WezTerm pane. The goal is a unified spatial model: press `Ctrl+l` and focus moves right, whether the next surface is a Neovim split or a WezTerm pane.

## Background

- The current config binds `Ctrl+h/j/k/l` in both WezTerm (`ActivatePaneDirection`) and Neovim (`<C-w>h/j/k/l`). WezTerm wins because it intercepts keys before passing them to the terminal.
- This was a solved problem with tmux via [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator). The pattern: the multiplexer detects the foreground process; if vim/nvim, forward the key; if not, navigate panes. The editor detects edge splits and delegates back to the multiplexer.
- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) (~1,500 stars, MIT, actively maintained) is the consensus successor for WezTerm, recommended by every archived alternative and the only option with first-class WezTerm support, directional resizing, and user-variable IPC.
- The [options analysis report](../reports/2026-02-11-wezterm-neovim-pane-navigation.md) evaluated 5 options and 3 WezTerm-native approaches. smart-splits was the clear winner.

## Proposed Solution

### Neovim Side: New Plugin Spec

Create `dot_config/nvim/lua/plugins/navigation.lua`:

```lua
-- Seamless navigation between Neovim splits and WezTerm panes.
-- Requires corresponding config in dot_config/wezterm/wezterm.lua.
-- See: cdocs/proposals/2026-02-11-smart-splits-adoption.md
return {
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,  -- Must set IS_NVIM user var at startup for WezTerm detection
    opts = {
      at_edge = "stop",  -- Do not wrap; let WezTerm handle cross-pane navigation
    },
    keys = {
      -- Navigation: Ctrl+h/j/k/l
      { "<C-h>", function() require("smart-splits").move_cursor_left() end,  desc = "Move left (split/pane)" },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end,  desc = "Move down (split/pane)" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end,    desc = "Move up (split/pane)" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move right (split/pane)" },
      -- Resize: Ctrl+Alt+h/j/k/l (matches existing WezTerm resize bindings)
      { "<C-A-h>", function() require("smart-splits").resize_left() end,  desc = "Resize left" },
      { "<C-A-j>", function() require("smart-splits").resize_down() end,  desc = "Resize down" },
      { "<C-A-k>", function() require("smart-splits").resize_up() end,    desc = "Resize up" },
      { "<C-A-l>", function() require("smart-splits").resize_right() end, desc = "Resize right" },
    },
  },
}
```

### Neovim Side: Remove Old Keymaps

Remove the manual `<C-h/j/k/l>` keymaps from `init.lua:82-86`. smart-splits takes over these bindings.

### WezTerm Side: Conditional Navigation

Replace the static `Ctrl+h/j/k/l` and `Ctrl+Alt+h/j/k/l` bindings in `wezterm.lua` with `action_callback` wrappers that check for Neovim:

```lua
-- =============================================================================
-- Smart Splits Integration (seamless neovim/wezterm pane navigation)
-- Requires smart-splits.nvim on the neovim side.
-- =============================================================================

local function is_nvim(pane)
  return pane:get_user_vars().IS_NVIM == "true"
end

local direction_keys = {
  Left = "h", Down = "j", Up = "k", Right = "l",
  h = "Left", j = "Down", k = "Up", l = "Right",
}

local function split_nav(resize_or_move, key)
  local mods = resize_or_move == "resize" and "CTRL|ALT" or "CTRL"
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        win:perform_action({ SendKey = { key = key, mods = mods } }, pane)
      else
        if resize_or_move == "resize" then
          win:perform_action({ AdjustPaneSize = { direction_keys[key], 5 } }, pane)
        else
          win:perform_action({ ActivatePaneDirection = direction_keys[key] }, pane)
        end
      end
    end),
  }
end
```

Then in `config.keys`, replace the 8 static bindings with:

```lua
  -- Pane navigation: Ctrl+H/J/K/L (smart-splits aware)
  split_nav("move", "h"),
  split_nav("move", "j"),
  split_nav("move", "k"),
  split_nav("move", "l"),

  -- Resize panes: Ctrl+Alt+H/J/K/L (smart-splits aware)
  split_nav("resize", "h"),
  split_nav("resize", "j"),
  split_nav("resize", "k"),
  split_nav("resize", "l"),
```

### Bindings Preserved Unchanged

These WezTerm bindings are **not affected** and remain as-is:

| Binding | Action | Why Unchanged |
|---|---|---|
| `Alt+h/j/k/l` | `SplitPane` | WezTerm-only operation, no Neovim equivalent |
| `Alt+n/p` | Tab navigation | WezTerm-only |
| `Alt+w` | Close pane | WezTerm-only |
| `Alt+c` | Copy mode | WezTerm-only |
| `Leader+*` | All leader bindings | WezTerm-only |

## Important Design Decisions

### Decision: Use `CTRL|ALT` for resize instead of smart-splits' default `META`

**Why:** `Alt+h/j/k/l` is already bound to WezTerm split creation (`SplitPane`). Using `META` (which maps to Alt on most systems) for resize would collide. The existing `Ctrl+Alt+h/j/k/l` resize bindings are already muscle memory, so we keep that modifier combination.

### Decision: `at_edge = "stop"` instead of `"wrap"`

**Why:** When at the last Neovim split in a direction, smart-splits should stop (not wrap within Neovim). This causes the navigation to fall through to WezTerm's `ActivatePaneDirection`, which moves focus to the adjacent WezTerm pane. Wrapping would keep focus trapped inside Neovim.

### Decision: Do not lazy-load smart-splits

**Why:** The plugin must set the `IS_NVIM` user variable via WezTerm escape sequences at startup. If lazy-loaded, the variable is unset until first navigation, and the WezTerm side would incorrectly assume the pane is not running Neovim. The `lazy = false` default in our lazy.nvim config already handles this, but the `keys` spec makes the intent explicit.

### Decision: New file `navigation.lua` instead of adding to `editor.lua`

**Why:** The integration spans two config files (neovim + wezterm) and has a specific IPC contract. A dedicated file makes the cross-config dependency visible and keeps `editor.lua` focused on in-editor enhancements.

## Stories

### Navigate from Neovim split to WezTerm pane
User has Neovim open with two vertical splits in the left WezTerm pane, and a terminal in the right WezTerm pane. Cursor is in the rightmost Neovim split. User presses `Ctrl+l`. smart-splits detects no split to the right, delegates to WezTerm CLI. Focus moves to the terminal pane.

### Navigate from WezTerm pane into Neovim
User is in the terminal pane (right). Presses `Ctrl+h`. WezTerm checks `IS_NVIM` on the left pane -- it is `true`. WezTerm sends `Ctrl+h` as a key to the left pane. smart-splits receives it inside Neovim and moves to the appropriate split.

### Resize across boundary
User presses `Ctrl+Alt+l` in the rightmost Neovim split. smart-splits detects the edge and invokes `wezterm cli adjust-pane-size Right 5`. The WezTerm pane boundary moves right, giving Neovim more space.

### Non-Neovim pane navigation
User has two terminal panes (no Neovim). Presses `Ctrl+l`. WezTerm checks `IS_NVIM` -- it is not set. WezTerm calls `ActivatePaneDirection("Right")` directly. Behavior is identical to today.

## Edge Cases / Challenging Scenarios

### Mux detach/reattach clears IS_NVIM

**Scenario:** User runs `wezterm connect unix`, opens Neovim, detaches, reattaches. The `IS_NVIM` user var is lost ([wezterm#5832](https://github.com/wezterm/wezterm/issues/5832)). WezTerm treats the pane as non-Neovim and intercepts `Ctrl+h/j/k/l`.

**Mitigation:** Add a `FocusGained` autocmd in the smart-splits plugin spec that re-sets the user var. This is a known workaround documented in the smart-splits wiki. Since `unix_domains` is configured but auto-connect is commented out, this is a future risk to monitor.

### Nushell as default shell

**Scenario:** If the user-var approach fails for any reason and the fallback `pane:get_foreground_process_name()` is used, nushell's process tree may not show `nvim` as the foreground process in all cases.

**Mitigation:** The user-var approach avoids this entirely. No fallback to process-name detection is needed as long as smart-splits is not lazy-loaded.

### Neovim inside a nested terminal

**Scenario:** User opens a Neovim terminal buffer (`:terminal`) and runs Neovim inside it. The outer Neovim has `IS_NVIM` set, so WezTerm always forwards keys. The inner Neovim's splits will work, but navigating out of the inner Neovim back to the outer Neovim requires `<C-\><C-n>` first.

**Mitigation:** This is an inherent limitation of all such solutions including vim-tmux-navigator. Not a regression.

## Test Plan

Testing combines automated programmatic verification with targeted manual checks.
See [Playwright for Neovim](../reports/2026-02-11-playwright-for-neovim.md) and
[Playwright for WezTerm](../reports/2026-02-11-playwright-for-wezterm.md) for the
full methodology.

### Automated Neovim Verification (Phase 1)

Run the existing headless test suite as a baseline before changes, then add smart-splits-specific tests and re-run.

#### Step 1: Capture baseline

```sh
nvim --headless -u dot_config/nvim/init.lua \
  -c "luafile dot_config/nvim/test/config_test.lua" \
  2>/dev/null
# Save exit code and /tmp/nvim_test_results.json as baseline
```

#### Step 2: Add smart-splits tests to `config_test.lua`

```lua
-- smart-splits plugin
check_plugin("smart-splits.nvim", true)  -- must be loaded (not lazy)

test("require('smart-splits') works", function()
  assert_true(pcall(require, "smart-splits"))
end)

-- Navigation keymaps (callback-based, so rhs is nil)
test("<C-h> mapped (smart-splits move left)", function()
  local m = get_keymap("n", "<C-H>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
  assert_true(m.desc ~= nil and m.desc:find("left", 1, true), "wrong desc: " .. tostring(m.desc))
end)
test("<C-j> mapped (smart-splits move down)", function()
  local m = get_keymap("n", "<C-J>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-k> mapped (smart-splits move up)", function()
  local m = get_keymap("n", "<C-K>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-l> mapped (smart-splits move right)", function()
  local m = get_keymap("n", "<C-L>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)

-- Resize keymaps
test("<C-A-h> mapped (smart-splits resize left)", function()
  local m = get_keymap("n", "<C-M-H>")  -- Ctrl+Alt encodes as C-M-
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-A-l> mapped (smart-splits resize right)", function()
  local m = get_keymap("n", "<C-M-L>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)

-- Verify old keymaps were removed (should no longer have <C-w>h as rhs)
test("<C-h> is NOT <C-w>h anymore", function()
  local m = get_keymap("n", "<C-H>")
  assert_true(m ~= nil, "not found")
  assert_true(m.rhs ~= "<C-w>h", "still mapped to old <C-w>h")
end)
```

#### Step 3: Run post-change validation

```sh
nvim --headless -u dot_config/nvim/init.lua \
  -c "luafile dot_config/nvim/test/config_test.lua" \
  2>/dev/null
# Exit code 0 = all tests pass, non-zero = failures
# Compare /tmp/nvim_test_results.json against baseline
```

**Pass criteria:** All existing tests still pass (no regressions). All new smart-splits tests pass. `cquit 0`.

### Automated WezTerm Verification (Phase 2)

Four-layer validation per the WezTerm testing report.

#### Layer 1: Lua syntax check

```sh
luac -p dot_config/wezterm/wezterm.lua
# Exit code 0 = valid syntax
```

#### Layer 2: Config evaluation via `ls-fonts` stderr

```sh
wezterm --config-file dot_config/wezterm/wezterm.lua ls-fonts 1>/dev/null 2>/tmp/wez_stderr.txt
if grep -q "ERROR" /tmp/wez_stderr.txt; then
    echo "CONFIG ERROR"; cat /tmp/wez_stderr.txt; exit 1
fi
```

#### Layer 3: `show-keys` diff for silent binding drops

```sh
# Capture before changes
wezterm show-keys --lua > /tmp/wez_keys_before.lua
wezterm show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_before.lua

# After changes
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua > /tmp/wez_keys_after.lua
wezterm --config-file dot_config/wezterm/wezterm.lua show-keys --lua --key-table copy_mode \
  > /tmp/wez_copy_mode_after.lua

# Verify NOT fallen back to defaults
wezterm --skip-config show-keys --lua > /tmp/wez_defaults.lua
diff -q /tmp/wez_defaults.lua /tmp/wez_keys_after.lua > /dev/null 2>&1 \
  && echo "FAIL: fell back to defaults" && exit 1

# Verify copy_mode unchanged (smart-splits should not touch copy_mode)
diff /tmp/wez_copy_mode_before.lua /tmp/wez_copy_mode_after.lua
# Expected: no differences

# Verify the 8 navigation bindings changed to action_callback
# show-keys displays action_callbacks as `wezterm.action_callback`
for key in h j k l; do
  grep -q "key = '$key', mods = 'CTRL', action = wezterm.action_callback" /tmp/wez_keys_after.lua \
    || echo "FAIL: Ctrl+$key not converted to action_callback"
  grep -q "key = '$key', mods = 'CTRL|ALT', action = wezterm.action_callback" /tmp/wez_keys_after.lua \
    || echo "FAIL: Ctrl+Alt+$key not converted to action_callback"
done

# Verify unaffected bindings still present
grep -q "SplitPane" /tmp/wez_keys_after.lua || echo "FAIL: Alt+h/j/k/l SplitPane missing"
grep -q "ActivateCopyMode" /tmp/wez_keys_after.lua || echo "FAIL: Alt+c CopyMode missing"
```

#### Layer 4: Live integration tests (post-deploy)

```sh
chezmoi apply
sleep 2  # wait for hot-reload

# Check GUI log for hot-reload errors
LATEST_LOG=$(ls -t "$XDG_RUNTIME_DIR/wezterm/wezterm-gui-log-"*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_LOG" ]; then
  grep -q "ERROR.*lua\|Failed to apply" "$LATEST_LOG" \
    && echo "FAIL: hot-reload errors in log"
fi

# Verify mux is healthy
wezterm cli list > /dev/null || echo "FAIL: mux unhealthy"

# Pane topology test: split and verify navigation
RIGHT=$(wezterm cli split-pane --right -- bash -c 'sleep 10')
sleep 0.1
wezterm cli get-pane-direction Left > /dev/null \
  && echo "PASS: pane topology correct" \
  || echo "FAIL: pane topology broken"
wezterm cli kill-pane --pane-id "$RIGHT"
```

**Pass criteria:** All 4 layers green. No ERROR in stderr. `show-keys` shows 8 `action_callback` bindings. Copy mode unchanged. Mux healthy.

### Manual Verification (both phases)

These scenarios require human interaction because `action_callback` logic and user-variable IPC cannot be exercised programmatically (see [Playwright for WezTerm](../reports/2026-02-11-playwright-for-wezterm.md#testing-action_callback-functions)).

1. **Neovim-only navigation:** Open Neovim with two vertical splits. `Ctrl+h/l` moves between them. `Ctrl+Alt+h/l` resizes them.
2. **Cross-boundary navigation (Neovim to WezTerm):** Neovim in left pane with 2 splits, terminal in right pane. From rightmost Neovim split, `Ctrl+l` moves focus to the terminal pane.
3. **Cross-boundary navigation (WezTerm to Neovim):** From the terminal pane, `Ctrl+h` moves focus into Neovim (to the appropriate split, not just the pane).
4. **Non-Neovim pane navigation:** Two terminal panes, no Neovim. `Ctrl+h/l` navigates between them (unchanged behavior).
5. **Unaffected bindings:** `Alt+h/j/k/l` still creates WezTerm splits. `Alt+c` enters copy mode. Leader bindings work.

### What Cannot Be Tested Programmatically

| Gap | Why | Mitigation |
|---|---|---|
| `action_callback` conditional logic (`is_nvim` check) | Callbacks only execute at keypress time; `show-keys` displays them as `EmitEvent` with no introspection | Manual verification of scenarios 2-4 above |
| `IS_NVIM` user variable set by smart-splits | `wezterm cli list --format json` does not expose user variables | Verify smart-splits plugin loaded (headless test) + manual scenario 2 |
| Cross-pane navigation direction correctness | No `wezterm cli send-key` exists; `send-text` goes to PTY not key handler | Manual verification of scenarios 2-3 |
| Resize across WezTerm/Neovim boundary | Same `action_callback` limitation | Manual `Ctrl+Alt+l` from edge Neovim split |

## Implementation Phases

### Phase 1: Add smart-splits.nvim to Neovim

1. Run the existing headless test suite to capture baseline (all tests must pass):
   ```sh
   nvim --headless -u dot_config/nvim/init.lua \
     -c "luafile dot_config/nvim/test/config_test.lua" 2>/dev/null
   cp /tmp/nvim_test_results.json /tmp/nvim_baseline.json
   ```
2. Create `dot_config/nvim/lua/plugins/navigation.lua` with the plugin spec above.
3. Remove the `<C-h/j/k/l>` keymaps from `dot_config/nvim/init.lua` (lines 82-86).
4. Update the comment on the line above to reflect smart-splits integration.
5. Add the smart-splits tests from the test plan to `config_test.lua`.
6. Run `chezmoi apply` and open Neovim to trigger lazy.nvim install.
7. Run the updated headless test suite:
   ```sh
   nvim --headless -u dot_config/nvim/init.lua \
     -c "luafile dot_config/nvim/test/config_test.lua" 2>/dev/null
   ```
8. Perform manual verification: Neovim with two vertical splits, `Ctrl+h/l` navigates between them.

**Success criteria (automated):** `cquit 0` from the headless test suite. smart-splits.nvim registered and loaded. `<C-H/J/K/L>` mapped with callbacks (not `<C-w>h` rhs). `<C-M-H/J/K/L>` mapped for resize. No regressions in existing tests. No errors in `v:errmsg` or `:messages`.

**Success criteria (manual):** `Ctrl+h/j/k/l` navigates between Neovim splits.

**What NOT to change:** `editor.lua`, `snacks.lua`, `ui.lua`, or any other plugin spec. The `Alt+h/j/k/l` split bindings in wezterm.lua remain untouched in this phase.

### Phase 2: Update WezTerm conditional navigation

1. Capture WezTerm baselines:
   ```sh
   wezterm show-keys --lua > /tmp/wez_keys_before.lua
   wezterm show-keys --lua --key-table copy_mode > /tmp/wez_copy_mode_before.lua
   ```
2. Add the `is_nvim()` and `split_nav()` helper functions to `wezterm.lua`.
3. Replace the 4 static `Ctrl+h/j/k/l` `ActivatePaneDirection` bindings with `split_nav("move", ...)`.
4. Replace the 4 static `Ctrl+Alt+h/j/k/l` `AdjustPaneSize` bindings with `split_nav("resize", ...)`.
5. Update the keybindings section comment to reference smart-splits.
6. Run the 4-layer WezTerm validation from the test plan (syntax, ls-fonts, show-keys diff, binding assertions).
7. Deploy with `chezmoi apply`, wait for hot-reload, check GUI logs for errors.
8. Run `wezterm cli list` to confirm mux health.
9. Run the pane topology integration test from the test plan.
10. Perform manual verification of cross-boundary navigation scenarios 2-5 from the test plan.

**Success criteria (automated):** `luac -p` exits 0. `ls-fonts` stderr has no ERROR. `show-keys` output differs from defaults. 8 bindings show `wezterm.action_callback`. Copy mode diff is empty. No hot-reload errors in GUI log. `wezterm cli list` succeeds. Pane topology test passes.

**Success criteria (manual):** Cross-boundary navigation works in both directions (Neovim-to-WezTerm and WezTerm-to-Neovim). Non-Neovim pane navigation unchanged. `Alt+h/j/k/l` split creation unaffected.

**What NOT to change:** Mouse bindings, copy mode, lace plugin, leader bindings, `Alt+h/j/k/l` split bindings, appearance settings, or the startup section.

### Phase 3: Cleanup and CLAUDE.md update (optional)

1. Update `CLAUDE.md` to document the smart-splits integration pattern under a new "Neovim/WezTerm Navigation" section.
2. Note the no-lazy-load requirement and the mux reattach workaround.

**What NOT to change:** The WezTerm validation workflow documentation (it remains accurate and applies to all future changes).
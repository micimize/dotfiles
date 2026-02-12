---
title: "Playwright for Neovim: Programmatic Config Verification for CLI-Based AI Agents"
date: 2026-02-11
first_authored:
  by: "claude-opus-4-6"
  at: 2026-02-11T22:30:00-05:00
type: report
state: live
status: accepted
tags: [neovim, testing, validation, cli, ai-agent, config, automation, lazy.nvim, headless]
---

# Playwright for Neovim: Programmatic Config Verification for CLI-Based AI Agents

## BLUF

Neovim's `--headless` mode is far more capable than WezTerm's CLI for programmatic config
verification. An AI agent running in a terminal can achieve **near-complete config
verification** without visual inspection by combining three layers: (1) stderr parsing from
`nvim --headless -u <config> -c "qall"` for parse errors (~90ms), (2) Lua assertion scripts
via `luafile` that check plugin state, keymaps, options, and `:messages` with `cquit` for
proper exit codes (~570ms), and (3) RPC queries via `--listen`/`--server` for live state
inspection of a running instance. The `VeryLazy` event can be triggered headlessly via
`nvim_exec_autocmds("UIEnter", {})`, enabling full plugin loading verification. The main
gaps are visual rendering (colorscheme appearance, statusline layout), mouse interactions,
and `action_callback`-based keymaps that only validate at keypress time.

The **recommended approach** is a standalone Lua test script run via `nvim --headless -u
<config> -c "luafile test.lua"`, which requires **zero additional dependencies** (no
plenary, no mini.test, no luarocks) and produces machine-parseable output with proper
exit codes.

---

## Testing Stack: Recommended Layers

| Layer | Method | What It Catches | Speed | Dependencies |
|-------|--------|----------------|-------|--------------|
| 0 | `luac -p init.lua` | Lua syntax errors only | <10ms | LuaJIT (bundled) |
| 1 | `nvim --headless -u <config> -c "qall" 2>err.txt` | Config parse/eval errors | ~90ms | None |
| 2 | `nvim --headless -u <config> -c "luafile test.lua"` | Plugin loading, keymaps, options, startup errors | ~570ms | None |
| 3 | `nvim --headless -u <config> --listen <sock>` + `--server` queries | Live state inspection, async behavior | ~2-3s | None |

Layer 2 is the sweet spot. It catches everything Layer 1 catches plus silent failures,
dropped keymaps, unloaded plugins, and option misconfigurations. Layer 3 is only needed
for scenarios requiring ongoing interaction (e.g., verifying LSP server startup or
async plugin behavior over time).

---

## 1. Headless Neovim (`nvim --headless`)

### What It Can Do

Headless mode runs a fully functional Neovim instance without a TUI. The full config
loads, plugins initialize, autocmds fire, and the Lua API is fully available. Key facts
from testing on nvim 0.11.6:

- Loads full `init.lua` config including lazy.nvim bootstrap and plugin setup
- All `vim.api.*`, `vim.fn.*`, `vim.opt.*`, `vim.keymap.*` APIs work normally
- Plugins install and load (lazy.nvim handles git clone, build steps)
- Can open files, trigger FileType autocmds, and activate buffer-local features
- LSP servers start and attach to buffers (tested with lua_ls)
- Treesitter parsers compile and attach to buffers
- Environment variables are fully accessible via `vim.env.*`
- `io.write()` and `print()` output to stdout; errors go to stderr
- `cquit <N>` exits with the specified exit code (critical for CI)

### What It Cannot Do

- No TUI rendering: `vim.api.nvim_list_uis()` returns empty table
- `UIEnter` autocmd does **not** fire automatically (must be triggered manually)
- No terminal escape sequence processing (no sixel, no OSC, no cursor positioning)
- No mouse event handling
- No visual colorscheme verification (highlights are set but not rendered)
- No statusline/bufferline visual layout verification

### The UIEnter Problem and Solution

Many plugins use `VeryLazy` (which triggers after `UIEnter`) for deferred loading.
In headless mode, `UIEnter` never fires because no UI attaches. The fix is simple:

```lua
-- Trigger VeryLazy manually in headless mode
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.wait(500, function() return false end)  -- let async handlers settle
```

After this, all `VeryLazy` plugins (which-key, lualine, flash, bufferline, etc.)
load and their keymaps become available. Verified working in testing.

### Concrete Example: Minimal Parse Check (Layer 1)

```bash
nvim --headless \
  -u dot_config/nvim/init.lua \
  -c "qall" \
  1>/dev/null 2>/tmp/nvim_stderr.txt

if grep -qiE "(error|E[0-9]+:)" /tmp/nvim_stderr.txt; then
  echo "CONFIG ERROR:"
  cat /tmp/nvim_stderr.txt
  exit 1
else
  echo "Config parsed OK"
fi
```

**Timing:** ~90ms on this system. Catches Lua errors, missing modules, undefined
variables, and vim command errors during config evaluation. Does NOT catch silently
dropped keymaps or plugins that fail to load gracefully.

---

## 2. `--cmd` and `-c` Flags

### Execution Order

1. `--cmd <cmd>` executes **before** any config file loads
2. `-u <config>` sources the user config (init.lua)
3. `-c <cmd>` (or `+<cmd>`) executes **after** config and first file load
4. Multiple `-c` flags execute in order

### Capturing Output

```bash
# Print from Lua goes to stdout
nvim --headless --clean -c "lua print('hello')" -c "qall"

# Errors go to stderr
nvim --headless --clean -c "lua error('boom')" -c "qall" 2>/tmp/err.txt

# Capture :messages programmatically
nvim --headless -u config.lua \
  -c "lua print(vim.api.nvim_exec2('messages', {output=true}).output)" \
  -c "qall"
```

### Checking v:errmsg

```bash
nvim --headless -u config.lua \
  -c "lua if vim.v.errmsg ~= '' then print('ERROR: ' .. vim.v.errmsg); vim.cmd('cquit 1') else vim.cmd('cquit 0') end"
```

### Quoting Pitfall

The `!` in `qall!` gets expanded by bash with `set -H` (default for interactive shells).
Always use double quotes: `-c "qall"` (without `!`) or `-c 'qall!'` with single quotes.
In most testing scenarios, `qall` (without `!`) is fine since there are no modified buffers.

### Limitation

Complex Lua one-liners in `-c` become unreadable quickly. For anything beyond trivial
checks, use `-c "luafile /path/to/test.lua"` instead.

---

## 3. RPC API (`--listen` / `--server`)

### Architecture

Neovim can listen on a Unix socket or TCP port. A second nvim instance (or any msgpack-rpc
client) connects to it and runs commands remotely.

```bash
# Start headless nvim with RPC socket
nvim --headless -u config.lua --listen /tmp/nvim.sock &

# Query from another process
nvim --server /tmp/nvim.sock --remote-expr "g:mapleader"
nvim --server /tmp/nvim.sock --remote-expr "luaeval('#require(\"lazy\").plugins()')"
nvim --server /tmp/nvim.sock --remote-expr "luaeval('vim.inspect(vim.fn.maparg(\" w\", \"n\", false, true))')"

# Shut down
nvim --server /tmp/nvim.sock --remote-send ":qall<CR>"
```

### Strengths

- Can inspect a running instance over time (useful for async operations)
- Can verify LSP server startup by waiting and then querying client list
- Can open files remotely and check buffer-local state
- Returns structured data (vim.inspect output is parseable)
- No additional dependencies: uses `nvim` binary itself as the client

### Weaknesses

- Requires managing background process lifecycle (start, wait, query, kill)
- Socket cleanup on error paths
- Slower startup (~2-3s) because you wait for the server to be ready
- `wait` on the background process returns non-zero on SIGTERM, complicating exit codes
- `--remote-expr` returns raw strings, requiring parsing for complex data

### When to Use

Use RPC when you need to:
- Verify async plugin behavior (LSP server attachment, treesitter compilation)
- Run multiple queries against the same instance without restart overhead
- Test state that changes over time (e.g., diagnostics appearing)
- Simulate a long-running session

For one-shot config validation, the `luafile` approach (Layer 2) is simpler and faster.

### `nvr` (neovim-remote)

`nvr` is a Python-based neovim remote client. It is NOT installed in this environment and
adds a `pip install neovim-remote` dependency. The built-in `nvim --server` provides the
same core functionality without additional dependencies. `nvr` adds convenience features
like `--remote-tab-wait` but none are needed for config testing.

---

## 4. Plenary.nvim Test Harness (`plenary.busted`)

### How It Works

Plenary provides a busted-compatible test framework invoked via `:PlenaryBustedFile` or
`:PlenaryBustedDirectory`. Tests use `describe`/`it` blocks with `luassert` assertions.

```lua
-- test/config_spec.lua
local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local assert = require("luassert")

describe("neovim config", function()
  it("has space as leader key", function()
    assert.equals(" ", vim.g.mapleader)
  end)

  it("has lazy.nvim loaded", function()
    local ok, lazy = pcall(require, "lazy")
    assert.is_true(ok)
  end)

  it("has <leader>w keymap", function()
    local maps = vim.api.nvim_get_keymap("n")
    local found = false
    for _, m in ipairs(maps) do
      if m.lhs == " w" then
        found = true
        assert.equals("<Cmd>w<CR>", m.rhs)
      end
    end
    assert.is_true(found)
  end)
end)
```

### Critical Caveat: PlenaryBustedFile Spawns a New Process

**PlenaryBustedFile runs the test file in a NEW neovim instance**, not the current one.
This means:
- The test process does NOT inherit the parent's loaded plugins or config state
- If your config has `colorscheme` commands that depend on plugins being in the rtp,
  the child process may fail with `E185: Cannot find color scheme`
- Lazy-loaded plugins from the parent are not loaded in the child

This was confirmed in testing: running `PlenaryBustedFile` against our config produced
`E5113: Error while calling lua chunk ... Cannot find color scheme 'solarized'` because
the child nvim did not have solarized.nvim in its runtimepath.

### Workaround

You can run plenary tests inside the config-loaded nvim by using `-c` to first force-load
plenary, then invoke the test:

```bash
nvim --headless \
  -u dot_config/nvim/init.lua \
  -c "lua require('lazy').load({plugins = {'plenary.nvim'}})" \
  -c "PlenaryBustedFile test/config_spec.lua"
```

But this is fragile. The child process spawned by PlenaryBustedFile still won't
have the parent's config.

### Verdict

Plenary.busted is **designed for plugin development testing**, not config testing. Its
process isolation model works against you when testing a monolithic config. The
standalone Lua script approach (Layer 2) is strictly superior for config validation:
simpler, faster, no process isolation surprises, and zero additional dependencies.

---

## 5. mini.test (echasnovski)

### Architecture

mini.test provides hierarchical test organization with hooks, parametrization, and a
child Neovim process pattern. It uses RPC under the hood to spawn and control child
nvim instances.

```lua
-- Typical mini.test setup
local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      child.lua([[M = require('my_plugin')]])
    end,
    post_once = child.stop,
  },
})

T['option check'] = function()
  child.lua('vim.opt.number = true')
  eq(child.lua_get('vim.opt.number:get()'), true)
end
```

### Strengths for Config Testing

- `child.lua()` and `child.lua_get()` are powerful for remote state inspection
- Screenshot testing compares text+highlight grids (closest thing to visual verification)
- Hierarchical test organization with proper hooks
- `MiniTest.gen_reporter.stdout()` works in headless mode for CI output

### Weaknesses

- Requires installing mini.nvim as a dependency (not currently in this config)
- Child process pattern has same RTP isolation issue as plenary
- Screenshot references require initial baseline generation by a human
- More complex setup than standalone Lua scripts
- The child process communication adds latency

### Verdict

mini.test is the **most sophisticated option** and the closest to "playwright for neovim"
in terms of screenshot comparison. However, for an AI agent doing config changes, the
overhead of managing child processes, screenshot baselines, and an additional dependency
is not justified. The standalone Lua script approach covers 95% of verification needs.
mini.test becomes valuable if you need screenshot regression testing (e.g., verifying
indent guide rendering or statusline layout).

---

## 6. Neotest

### What It Is

Neotest is a **test runner UI** for running project tests (jest, pytest, go test, etc.)
inside Neovim. It provides a sidebar for test results, inline diagnostics for failures,
and DAP integration for debugging tests.

### Relevance to Config Testing

**None.** Neotest is a plugin that runs your project's tests, not a framework for testing
Neovim's own config. It could theoretically run plenary or busted tests if you installed
neotest-plenary, but this adds unnecessary complexity.

### Verdict

Skip Neotest for config testing. It solves a different problem.

---

## 7. Lua Assertions in Headless Mode (Recommended Approach)

This is the recommended approach. A standalone Lua script that loads with the config,
checks assertions, and exits with a proper exit code.

### Pattern

```lua
-- test/config_test.lua
-- Run: nvim --headless -u init.lua -c "luafile test/config_test.lua"

local results = { pass = 0, fail = 0, errors = {} }

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    results.pass = results.pass + 1
    io.write("PASS: " .. name .. "\n")
  else
    results.fail = results.fail + 1
    table.insert(results.errors, { name = name, err = tostring(err) })
    io.write("FAIL: " .. name .. " -- " .. tostring(err) .. "\n")
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected=" .. tostring(expected)
      .. " actual=" .. tostring(actual))
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true, got " .. tostring(val)) end
end

-- Trigger VeryLazy for full plugin loading
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.wait(500, function() return false end)

-- ===== Tests go here =====

test("leader is space", function()
  assert_eq(vim.g.mapleader, " ")
end)

test("lazy.nvim loads", function()
  assert_true(pcall(require, "lazy"))
end)

test("snacks.nvim loaded", function()
  local plugins = require("lazy").plugins()
  for _, p in ipairs(plugins) do
    if p.name == "snacks.nvim" then
      assert_true(p._.loaded ~= nil, "snacks.nvim not loaded")
      return
    end
  end
  error("snacks.nvim not registered")
end)

-- ===== Summary =====

io.write(string.format("\nResults: %d passed, %d failed\n",
  results.pass, results.fail))

-- Write JSON for machine parsing
local f = io.open("/tmp/nvim_test_results.json", "w")
if f then f:write(vim.json.encode(results)); f:close() end

vim.cmd("cquit " .. (results.fail > 0 and "1" or "0"))
```

### Why This Works

1. **Zero dependencies**: Uses only nvim built-in Lua and vim APIs
2. **Proper exit codes**: `cquit 1` for failure, `cquit 0` for success
3. **Machine-parseable output**: JSON results file plus grep-friendly stdout
4. **Fast**: ~570ms for 32 tests on this system
5. **Full config context**: Runs inside the config-loaded nvim, not a child process
6. **Works from non-interactive terminal**: Verified working from Claude Code's terminal

### Edge Cases

- **`io.write` vs `print`**: Both work in headless mode. `io.write` gives more control
  over newlines. `print` adds a newline automatically.
- **`cquit` vs `quit`**: `cquit` is required for non-zero exit codes. `quit` always
  exits 0 (or prompts for unsaved buffers).
- **`vim.wait` for async operations**: Some plugins do async initialization.
  `vim.wait(ms, function() return false end)` creates a synchronous delay. For
  conditional waits, return `true` when the condition is met.
- **stdout mixing with plugin output**: treesitter install messages, lazy.nvim status
  messages, etc. may intermix with test output on stderr. Redirect stderr to a file
  if you need clean stdout.

---

## 8. Checking Plugin Load State

### lazy.nvim Introspection API

```lua
-- Get all plugins
local plugins = require("lazy").plugins()

-- Check if a specific plugin is registered and loaded
for _, p in ipairs(plugins) do
  print(p.name,
    "loaded=" .. tostring(p._.loaded ~= nil),
    "cond=" .. tostring(p._.cond))
end

-- Force-load a lazy plugin
require("lazy").load({ plugins = { "gitsigns.nvim" } })

-- Get stats
local stats = require("lazy").stats()
print("Total:", stats.count, "Loaded:", stats.loaded, "Startup:", stats.startuptime)
```

### Verifying Module Availability

```lua
-- Check if a plugin's main module loads
local ok, mod = pcall(require, "snacks")
assert(ok, "snacks module failed to load")
assert(mod ~= nil, "snacks module is nil")
```

### Checking Global Variables

Some plugins set global variables to indicate they loaded:

```lua
-- Old-style vim plugins
assert(vim.g.loaded_fugitive ~= nil, "fugitive not loaded")

-- Check if a plugin's commands exist
local cmds = vim.api.nvim_get_commands({})
assert(cmds["Git"] ~= nil, "Git command not registered")
```

### Full Plugin Verification Pattern

```lua
local function check_plugin(name, opts)
  opts = opts or {}
  local plugins = require("lazy").plugins()
  for _, p in ipairs(plugins) do
    if p.name == name then
      -- Registered
      if opts.loaded then
        assert(p._.loaded ~= nil, name .. " registered but not loaded")
      end
      if opts.module then
        local ok = pcall(require, opts.module)
        assert(ok, name .. ": require('" .. opts.module .. "') failed")
      end
      if opts.command then
        local cmds = vim.api.nvim_get_commands({})
        assert(cmds[opts.command], name .. ": command '" .. opts.command .. "' not found")
      end
      return true
    end
  end
  error(name .. " not registered in lazy.nvim")
end

-- Usage
check_plugin("snacks.nvim", { loaded = true, module = "snacks" })
check_plugin("gitsigns.nvim", { module = "gitsigns" })
check_plugin("vim-fugitive", { command = "Git" })
```

---

## 9. Checking Keybindings

### Global Keymaps

```lua
-- Get all normal mode keymaps
local nmaps = vim.api.nvim_get_keymap("n")

-- Search by lhs
local function find_keymap(mode, lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == lhs then return m end
  end
  return nil
end

-- Check a string-rhs keymap
local m = find_keymap("n", " w")
assert(m ~= nil, "<leader>w not mapped")
assert(m.rhs == "<Cmd>w<CR>", "wrong rhs: " .. tostring(m.rhs))
assert(m.desc == "Save", "wrong desc: " .. tostring(m.desc))
```

### Keymap Encoding Gotchas

The `lhs` field uses internal encoding that differs from what you write in `vim.keymap.set`:

| What you write | What `nvim_get_keymap` returns in `lhs` |
|---------------|----------------------------------------|
| `<leader>w` (with space leader) | `" w"` (literal space + w) |
| `<C-n>` | `"<C-N>"` (uppercase) |
| `<` (less-than in visual mode) | `"<lt>"` |
| `<CR>` | `"<CR>"` |

Always check actual `lhs` values by dumping keymaps first rather than guessing the encoding.

### Buffer-Local Keymaps

Buffer-local keymaps (e.g., LSP keymaps) require opening a file and triggering the
relevant autocmds:

```lua
-- Open a Lua file to trigger LspAttach
vim.cmd("edit /tmp/test.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {"local x = 1"})
vim.wait(2000, function() return false end)  -- wait for LSP

-- Check buffer-local keymaps
local buf_maps = vim.api.nvim_buf_get_keymap(0, "n")
local function find_buf_keymap(lhs)
  for _, m in ipairs(buf_maps) do
    if m.lhs == lhs then return m end
  end
  return nil
end

assert(find_buf_keymap("gd"), "gd (go to definition) not mapped")
assert(find_buf_keymap("K"), "K (hover) not mapped")
```

### Callback-Based Keymaps

Keymaps set with a Lua function callback have `rhs = nil` and `callback` set to a
non-zero integer (the function reference ID). You cannot inspect what the callback
does, but you can verify it exists:

```lua
local m = find_keymap("n", " ff")
assert(m ~= nil, "<leader>ff not mapped")
assert(m.callback ~= nil and m.callback ~= 0, "no callback set")
assert(m.desc == "Find files", "wrong desc")
-- Cannot verify the callback actually calls Snacks.picker.files()
-- That requires pressing the key and checking behavior
```

---

## 10. Checking for Startup Errors

### Three-Layer Error Detection

#### Layer 1: stderr

```bash
nvim --headless -u config.lua -c "qall" 2>/tmp/err.txt
if grep -qiE "(error|E[0-9]+:)" /tmp/err.txt; then
  echo "STARTUP ERROR"
  cat /tmp/err.txt
fi
```

Catches: Lua errors, vim command errors, missing modules, syntax errors.

#### Layer 2: v:errmsg

```lua
-- Inside a test script
test("v:errmsg is empty", function()
  assert_eq(vim.v.errmsg, "", "v:errmsg=" .. vim.v.errmsg)
end)
```

Catches: The last error message from vim. Useful for catching the most recent error
even if :messages buffer has scrolled.

#### Layer 3: :messages

```lua
-- Parse all startup messages for errors
test("no errors in :messages", function()
  local msgs = vim.api.nvim_exec2("messages", { output = true }).output
  local error_lines = {}
  for line in msgs:gmatch("[^\n]+") do
    if line:match("^E%d+:") or line:match("Error executing") or line:match("E5113") then
      table.insert(error_lines, line)
    end
  end
  assert_true(#error_lines == 0,
    "errors found: " .. table.concat(error_lines, "; "))
end)
```

Catches: All accumulated error messages, including warnings from plugins that catch
and re-raise errors.

#### Layer 4: vim.health (deep validation)

```lua
-- Run health checks programmatically
vim.cmd("checkhealth lazy")
local buf = vim.api.nvim_get_current_buf()
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
for _, line in ipairs(lines) do
  if line:match("ERROR") then
    print("HEALTH ERROR: " .. line)
  end
end
```

This is slow but thorough. It validates not just config parsing but also runtime
dependencies (git version, external tools, etc.).

---

## 11. Environment Simulation

### Setting Environment Variables

```bash
# Simulate being inside WezTerm
WEZTERM_PANE=42 TERM=xterm-256color \
  nvim --headless -u config.lua -c "luafile test.lua"

# Simulate being inside tmux
TMUX=/tmp/tmux-1000/default,12345,0 \
  nvim --headless -u config.lua -c "luafile test.lua"
```

### Testing Environment-Dependent Config Branches

```lua
-- Config that branches on environment
if vim.env.WEZTERM_PANE then
  -- WezTerm-specific config
  vim.g.is_wezterm = true
end

-- Test: verify the branch was taken
test("detects wezterm environment", function()
  assert_true(vim.g.is_wezterm == true, "wezterm not detected")
end)
```

### Simulating Terminal Capabilities

Some plugins check `vim.env.TERM`, `vim.fn.has("gui_running")`, or query terminal
capabilities. In headless mode:

```lua
-- vim.fn.has() results in headless mode:
vim.fn.has("gui_running")  -- returns 0
vim.fn.has("nvim")         -- returns 1
vim.fn.has("unix")         -- returns 1

-- To override for testing:
vim.env.TERM = "wezterm"
vim.env.COLORTERM = "truecolor"
```

**Limitation:** Terminal capability queries that use escape sequences (DECRQM, DA1, etc.)
will not work in headless mode because there is no terminal to respond. Plugins that
fall back gracefully when these queries time out will work; plugins that hard-require
a response will not.

---

## 12. CI/CD Examples and Patterns

### GitHub Actions Workflow for Config Validation

```yaml
name: Validate Neovim Config
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rhysd/action-setup-vim@v1
        with:
          neovim: true
          version: v0.11.6
      - name: Install plugins
        run: |
          nvim --headless -u dot_config/nvim/init.lua \
            -c "lua require('lazy').sync()" \
            -c "qall" 2>&1
      - name: Validate config
        run: |
          nvim --headless -u dot_config/nvim/init.lua \
            -c "luafile test/config_test.lua" 2>/tmp/stderr.txt
          EXIT=$?
          if [ $EXIT -ne 0 ]; then
            echo "::error::Config validation failed"
            cat /tmp/stderr.txt
            exit 1
          fi
```

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit (or managed by chezmoi)
# Validate neovim config before committing

if git diff --cached --name-only | grep -q "dot_config/nvim/"; then
  echo "Validating neovim config..."
  nvim --headless \
    -u dot_config/nvim/init.lua \
    -c "qall" \
    1>/dev/null 2>/tmp/nvim_precommit_err.txt

  if grep -qiE "(error|E[0-9]+:)" /tmp/nvim_precommit_err.txt; then
    echo "ERROR: Neovim config has errors:"
    cat /tmp/nvim_precommit_err.txt
    exit 1
  fi
  echo "Config OK"
fi
```

### Existing Dotfiles Repos with Testing

Most dotfiles repos do **not** have automated config testing. The neovim ecosystem
focuses testing on plugin development (plenary tests in plugin repos). The approach
described in this report is novel for dotfiles -- essentially treating your personal
config as a "product" with a test suite.

Notable patterns seen in the wild:
- **folke/lazy.nvim** uses plenary + custom test infra for the plugin itself
- **echasnovski/mini.nvim** uses mini.test with child processes and screenshot comparisons
- **LazyVim** uses `checkhealth` as its validation mechanism
- No major dotfiles repos were found with automated headless config testing

---

## 13. Plenary.nvim `async` and `job` Utilities

### What They Provide

Plenary's async module wraps Lua coroutines with a neovim-friendly API:

```lua
local async = require("plenary.async")

-- Run async function synchronously in tests
async.tests.it("async test", function()
  local result = async.wrap(function(callback)
    vim.defer_fn(function() callback("done") end, 100)
  end, 1)()
  assert.equals("done", result)
end)
```

### Relevance for Config Testing

**Limited.** Plenary's async utilities are useful for testing plugins that do async
operations (HTTP requests, file I/O, etc.). For config testing, `vim.wait()` provides
sufficient synchronization:

```lua
-- Wait for a condition (up to timeout)
vim.wait(5000, function()
  -- Check if LSP client attached
  return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end)
```

Plenary's job control (`plenary.job`) is useful for running external commands, but in
headless testing you can use `vim.fn.system()` or `vim.system()` (0.10+) directly.

### Verdict

Not needed for config testing. `vim.wait()` and `vim.system()` cover the use cases
without adding a plenary dependency to the test runner.

---

## 14. Real-World Limitations: What CANNOT Be Tested Headlessly

### Definitely Cannot Test

| Category | Why | Workaround |
|----------|-----|------------|
| Visual colorscheme appearance | No rendering engine in headless mode | Verify highlight groups exist via `nvim_get_hl()` |
| Statusline/bufferline layout | No screen buffer to inspect | Check plugin loaded + config values |
| Mouse click/scroll behavior | No mouse event processing | Verify mouse option is set (`vim.opt.mouse`) |
| Terminal escape sequences | No PTY in headless mode | Verify env vars and option settings |
| Floating window positioning | No screen dimensions | Check window config via API |
| Animation/transition effects | No frame rendering | Skip |
| Copy-to-clipboard via OSC 52 | No terminal to send escapes to | Verify clipboard option setting |

### Partially Testable

| Category | What Works | What Doesn't |
|----------|-----------|--------------|
| LSP features | Server starts, attaches, provides completions | Visual hover popup rendering |
| Treesitter | Parser compiles, highlights set | Visual syntax highlighting appearance |
| `action_callback` keymaps | Verify they exist as `EmitEvent` | Verify what the callback actually does |
| Autocommands | Verify registration via `nvim_get_autocmds` | Verify visual effects they produce |
| Plugin lazy-loading triggers | Force-trigger events, verify load | BufReadPre for actual file I/O timing |

### mini.test Screenshot Testing

mini.test's `child.get_screenshot()` is the closest thing to visual verification.
It captures a text+attribute grid of the nvim screen from a child process (which
has a pseudo-terminal attached via RPC). This can verify:

- Statusline content (text, not pixel-perfect rendering)
- Indent guide characters
- Diagnostic virtual text
- Floating window content and position

However, it requires mini.nvim as a dependency and baseline screenshot management.

---

## Recommendations for AI Agent Config Testing

### Immediate Implementation (Zero New Dependencies)

Create `dot_config/nvim/test/config_test.lua` with the assertion pattern from Section 7.
Run it from the agent with:

```bash
nvim --headless \
  -u dot_config/nvim/init.lua \
  -c "luafile dot_config/nvim/test/config_test.lua" \
  2>/tmp/nvim_test_stderr.txt

EXIT=$?
if [ $EXIT -ne 0 ]; then
  echo "TESTS FAILED (exit $EXIT)"
  cat /tmp/nvim_test_stderr.txt
fi
exit $EXIT
```

### Test Categories to Include

1. **Smoke test**: Config loads without errors (stderr + v:errmsg + :messages)
2. **Plugin registration**: All expected plugins in `require("lazy").plugins()`
3. **Plugin loading**: Critical plugins (snacks, treesitter, solarized) are loaded
4. **Core options**: leader, number, tabstop, expandtab, etc.
5. **Keymap existence**: All explicitly defined keymaps exist with correct rhs/desc
6. **Module availability**: `require()` works for critical plugin modules
7. **No regressions**: Total plugin count hasn't dropped unexpectedly

### Workflow for the Agent

1. Before making changes: run test suite, capture baseline
2. Make config changes
3. Run test suite again, compare results
4. If tests fail: revert changes and report
5. If tests pass: deploy via `chezmoi apply`

### Future Enhancements

- **`/nvim-validate` skill**: Automates the before/after workflow as a single command
- **Pre-commit hook**: Runs Layer 1 (stderr check) on every commit touching nvim config
- **mini.test adoption**: If screenshot regression testing becomes important (e.g.,
  verifying statusline layout after theme changes)
- **Startuptime regression**: Parse `--startuptime` output to detect performance regressions

---

## Appendix: Verified Test Script (32/32 Passing)

The following test script was verified against the current config (`dot_config/nvim/init.lua`)
running on nvim 0.11.6. It completes in ~570ms and produces both human-readable stdout
and a JSON results file at `/tmp/nvim_test_results.json`.

```lua
-- dot_config/nvim/test/config_test.lua
-- Run: nvim --headless -u dot_config/nvim/init.lua -c "luafile dot_config/nvim/test/config_test.lua"

local results = { pass = 0, fail = 0, tests = {} }

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    results.pass = results.pass + 1
    table.insert(results.tests, { name = name, status = "PASS" })
    io.write("PASS: " .. name .. "\n")
  else
    results.fail = results.fail + 1
    table.insert(results.tests, { name = name, status = "FAIL", error = tostring(err) })
    io.write("FAIL: " .. name .. " -- " .. tostring(err) .. "\n")
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true, got " .. tostring(val)) end
end

-- Trigger VeryLazy for full plugin loading
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.wait(500, function() return false end)

-- Core Settings
test("leader is space", function() assert_eq(vim.g.mapleader, " ") end)
test("number enabled", function() assert_true(vim.opt.number:get()) end)
test("relativenumber enabled", function() assert_true(vim.opt.relativenumber:get()) end)
test("tabstop is 2", function() assert_eq(vim.opt.tabstop:get(), 2) end)
test("shiftwidth is 2", function() assert_eq(vim.opt.shiftwidth:get(), 2) end)
test("expandtab enabled", function() assert_true(vim.opt.expandtab:get()) end)
test("clipboard is unnamedplus", function()
  assert_eq(vim.opt.clipboard:get()[1], "unnamedplus")
end)
test("termguicolors enabled", function() assert_true(vim.opt.termguicolors:get()) end)

-- Plugin Loading
test("lazy.nvim loads", function() assert_true(pcall(require, "lazy")) end)
test("plugin count > 20", function()
  assert_true(#require("lazy").plugins() > 20)
end)

local function check_plugin(name, expect_loaded)
  test(name .. " registered", function()
    local found = false
    for _, p in ipairs(require("lazy").plugins()) do
      if p.name == name then found = true; break end
    end
    assert_true(found, name .. " not in lazy.plugins()")
  end)
  if expect_loaded then
    test(name .. " loaded", function()
      for _, p in ipairs(require("lazy").plugins()) do
        if p.name == name then
          assert_true(p._.loaded ~= nil, name .. " not loaded")
          return
        end
      end
    end)
  end
end

check_plugin("snacks.nvim", true)
check_plugin("nvim-treesitter", true)
check_plugin("solarized.nvim", true)
check_plugin("gitsigns.nvim", false)
check_plugin("which-key.nvim", true)  -- VeryLazy, loaded after UIEnter
check_plugin("lualine.nvim", true)    -- VeryLazy
check_plugin("flash.nvim", true)      -- VeryLazy

-- Keymaps
local function get_keymap(mode, lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhs == lhs then return m end
  end
  return nil
end

test("<leader>w mapped to save", function()
  local m = get_keymap("n", " w")
  assert_true(m ~= nil, "not found")
  assert_eq(m.rhs, "<Cmd>w<CR>")
end)

test("<C-n> mapped to bnext", function()
  local m = get_keymap("n", "<C-N>")
  assert_true(m ~= nil, "not found")
  assert_eq(m.rhs, "<Cmd>bnext<CR>")
end)

test("<leader>ff mapped (snacks picker)", function()
  local m = get_keymap("n", " ff")
  assert_true(m ~= nil, "not found")
  assert_true(m.desc ~= nil and m.desc ~= "", "no desc")
end)

test("<leader>e mapped (snacks explorer)", function()
  assert_true(get_keymap("n", " e") ~= nil, "not found")
end)

test("<leader>bd mapped (snacks bufdelete)", function()
  assert_true(get_keymap("n", " bd") ~= nil, "not found")
end)

-- Error Detection
test("v:errmsg is empty", function()
  assert_eq(vim.v.errmsg, "", "v:errmsg=" .. vim.v.errmsg)
end)

test("no errors in :messages", function()
  local msgs = vim.api.nvim_exec2("messages", { output = true }).output
  local errs = {}
  for line in msgs:gmatch("[^\n]+") do
    if line:match("^E%d+:") or line:match("Error executing") then
      table.insert(errs, line)
    end
  end
  assert_true(#errs == 0, table.concat(errs, "; "))
end)

-- Module Availability
test("require('snacks') works", function() assert_true(pcall(require, "snacks")) end)
test("require('gitsigns') works after load", function()
  require("lazy").load({ plugins = { "gitsigns.nvim" } })
  assert_true(pcall(require, "gitsigns"))
end)

-- Summary
io.write(string.format("\n========================================\n"))
io.write(string.format("Results: %d passed, %d failed, %d total\n",
  results.pass, results.fail, results.pass + results.fail))
io.write("========================================\n")

local f = io.open("/tmp/nvim_test_results.json", "w")
if f then f:write(vim.json.encode(results)); f:close() end

vim.cmd("cquit " .. (results.fail > 0 and "1" or "0"))
```

Run command:
```bash
nvim --headless -u dot_config/nvim/init.lua \
  -c "luafile dot_config/nvim/test/config_test.lua" \
  2>/dev/null
```

---

## Sources

- [Testing Neovim plugins with Busted](https://hiphish.github.io/blog/2024/01/29/testing-neovim-plugins-with-busted/)
- [mini.nvim TESTING.md](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md)
- [mini.test repository](https://github.com/echasnovski/mini.test)
- [lazy.nvim Usage](https://lazy.folke.io/usage)
- [Neovim Lua Guide](https://neovim.io/doc/user/lua-guide.html)
- [Neovim Health](https://neovim.io/doc/user/health.html)
- [Neovim Starting](https://neovim.io/doc/user/starting.html)
- [Neotest](https://github.com/nvim-neotest/neotest)
- [Neovim TUI docs](https://neovim.io/doc/user/tui.html)

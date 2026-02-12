---
title: "Neovim Transition UX: Error Logging, Notifications, and Dashboard Research"
date: 2026-02-11
first_authored: 2026-02-11
status: draft
state: active
type: analysis
tags: [neovim, ux, notifications, logging, dashboard, ai-agent]
---

# Neovim Transition UX Research Report

## BLUF

Your three pain points -- ephemeral errors, invasive toasts, and a bare landing page -- are **widely shared frustrations** among VSCode-to-neovim converts. The ecosystem has produced strong solutions, with `folke/snacks.nvim` emerging as the centerpiece (notifications, dashboard, and notification history in one package). For AI-agent-friendly logging, no turnkey solution exists yet, but a lightweight `vim.notify` wrapper writing JSONL to disk is the clear path -- and the emerging MCP server ecosystem (especially `mcp-diagnostics.nvim`) is the longer-term play for structured agent access. The biggest architectural decision is whether to adopt `noice.nvim` (comprehensive message/cmdline/notification overhaul) or stay with a simpler stack (snacks.notifier + a file-logging wrapper).

---

## Context / Background

### Current Config State

Your neovim setup is a **custom kickstart-style config** (not a distro) using:
- **lazy.nvim** for plugin management
- **nvim-notify** (basic config, 3s timeout, replaces `vim.notify`)
- **persistence.nvim** for session save/restore (no dashboard plugin)
- **Native vim.lsp.config** (neovim 0.11+ API) with mason.nvim
- **nvim-treesitter** (main branch -- the rewritten 2025 API)
- **telescope.nvim** for fuzzy finding

This matters because several of the solutions below involve replacing nvim-notify or adding plugins that may conflict with it.

---

## Finding 1: Error and Message Logging

### The Problem

Neovim's message system has multiple overlapping layers that don't persist to disk:

| Layer | What it captures | Persistence |
|---|---|---|
| `:messages` ring buffer | `echomsg`, `echoerr`, `print()`, `vim.notify()` | Session-only, fixed-size |
| `$NVIM_LOG_FILE` (`~/.local/state/nvim/log`) | Internal C-level debug messages | Disk, but **not** Lua errors or plugin messages |
| `vim.lsp.log` (`~/.local/state/nvim/lsp.log`) | LSP client/server communication | Disk, but semi-structured and can grow to GB at DEBUG level |
| `nvim-notify` history | `vim.notify()` calls only | In-memory only |

**The gap**: There is no built-in mechanism that captures all Lua errors, plugin notifications, and LSP messages to a persistent, structured log file. A Neovim core maintainer has [acknowledged](https://github.com/neovim/neovim/discussions/30770) that both `nvim_echo` and `vim.notify` are "half-baked and need to be revisited."

Users on [LazyVim Discussion #1963](https://github.com/LazyVim/LazyVim/discussions/1963) report spending **4+ hours** debugging startup errors because messages appear truncated in popups and the built-in log file is empty.

### Recommended Solution: `vim.notify` File Logger

The most reliable approach is a `vim.notify` wrapper that writes JSONL to disk while passing through to whatever visual notification system you use:

```lua
-- In your init.lua, after plugin setup (use VeryLazy autocmd for correct ordering)
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local log_path = vim.fn.stdpath("log") .. "/notify.jsonl"
    local current_notify = vim.notify
    vim.notify = function(msg, level, opts)
      local file = io.open(log_path, "a")
      if file then
        local ok, entry = pcall(vim.json.encode, {
          t = os.date("!%Y-%m-%dT%H:%M:%SZ"),
          l = level or 2,
          m = msg,
          s = opts and opts.title or nil,
        })
        if ok then file:write(entry .. "\n") end
        file:close()
      end
      return current_notify(msg, level, opts)
    end
  end,
})
```

For diagnostics specifically, a `DiagnosticChanged` autocmd can dump structured data:

```lua
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function()
    local diag_path = vim.fn.stdpath("log") .. "/diagnostics.json"
    local all = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        for _, d in ipairs(vim.diagnostic.get(buf)) do
          table.insert(all, {
            file = vim.api.nvim_buf_get_name(buf),
            line = d.lnum + 1, col = d.col + 1,
            severity = d.severity, message = d.message,
            source = d.source, code = d.code,
          })
        end
      end
    end
    local file = io.open(diag_path, "w")
    if file then file:write(vim.json.encode(all)); file:close() end
  end,
})
```

An external agent can then `tail -f ~/.local/state/nvim/notify.jsonl` or read `diagnostics.json`.

### Existing Plugins for Logging

| Plugin | Approach | File output? | Notes |
|---|---|---|---|
| [structlog.nvim](https://github.com/Tastyep/structlog.nvim) | Pipeline: processors -> formatters -> sinks | Yes (file sink) | Best for plugin authors; not a `:messages` capture |
| [notify-log.nvim](https://github.com/BSeblu/notify-log.nvim) | Intercepts `vim.notify`, stores in a vim register | No (register only) | Lightweight; paste with `"np` |
| [vlog.nvim](https://github.com/tjdevries/vlog.nvim) | Single-file logger for plugins | Yes (`use_file` option) | Copy-paste design; no dependencies |
| [logger.nvim](https://github.com/rmagatti/logger.nvim) | Logger class with `vim.inspect` | Via `vim.notify` | Consistent format across plugins |

### AI-Agent Integration Path

For longer-term structured access, the **MCP server ecosystem** is the right direction:

- **[mcp-diagnostics.nvim](https://github.com/georgeharker/mcp-diagnostics.nvim)** -- Exposes `diagnostic_hotspots`, `diagnostic_stats`, `diagnostic_by_severity`, `diagnostics_summary`, `lsp_document_diagnostics` (with surrounding code context), plus LSP navigation tools (`lsp_hover`, `lsp_definition`, `lsp_references`, `lsp_code_actions`).
- **[mcphub.nvim](https://github.com/ravitemer/mcphub.nvim)** -- MCP client for neovim with a built-in server exposing `neovim://diagnostics/buffer` and `neovim://diagnostics/workspace` resources.
- **[mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server)** -- 19 tools including buffer reading, command execution, and search/replace. Connects via `--listen` socket.

Neovim's RPC API (`nvim --listen /tmp/nvim`) also allows any external process to call `nvim_exec_lua('return vim.diagnostic.get()', {})` and get structured data back.

---

## Finding 2: Notification Toasts / UI

### The Problem

The "plugin rewrite" toasts you're seeing are almost certainly from the **nvim-treesitter** major restructuring (the `nvim-treesitter.configs` module was deprecated, `context_commentstring` was deprecated) and possibly **mason.nvim v2** migration warnings. The 2024-2026 period has been a season of breaking changes across the plugin ecosystem.

Your current nvim-notify setup (3s timeout, top-right positioning, default render) shows these as prominent animated toast boxes that vanish before you can read them.

### The Notification Plugin Landscape (Ranked by Current Adoption)

**1. [folke/snacks.nvim](https://github.com/folke/snacks.nvim) notifier** -- Now the **LazyVim default** (replaced nvim-notify). Offers compact/minimal/fancy styles, bottom-anchored option, built-in history via `Snacks.notifier.show_history()` and `Snacks.notifier.get_history()`, and a `filter` function for programmatic suppression. Strongest choice for your setup.

**2. [folke/noice.nvim](https://github.com/folke/noice.nvim)** -- The most comprehensive option. Completely replaces the message, cmdline, and popupmenu UI. Killer feature: **routing system** that filters messages by event type, kind, and content, then sends them to different views (toast, mini virtualtext, split) or suppresses them entirely. Polarizing: users either love the full overhaul or find it too experimental.

**3. [j-hui/fidget.nvim](https://github.com/j-hui/fidget.nvim)** -- The "stays out of my way" choice. Renders notifications as subtle gray text (using `Comment` highlight) with fully transparent background. Originally for LSP progress, now a full `vim.notify` backend. Best for users who want notifications to exist but never demand attention.

**4. [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)** -- Your current plugin. Still widely used but increasingly being replaced. Can be made less invasive with `render = "compact"`, `stages = "static"`, `top_down = false`, `level = vim.log.levels.WARN`.

**5. [echasnovski/mini.notify](https://github.com/echasnovski/mini.nvim)** -- Displays all notifications in a **single floating window** (no individual toast bubbles). Good for users overwhelmed by multiple simultaneous toasts.

### Recommended Approach

Replace nvim-notify with **snacks.notifier** (or noice.nvim if you want the full cmdline overhaul):

```lua
-- Replace your nvim-notify config with:
{
  "folke/snacks.nvim",
  lazy = false,
  priority = 1000,
  opts = {
    notifier = {
      enabled = true,
      timeout = 3000,
      top_down = false,         -- bottom-anchored = less invasive
      style = "compact",        -- smaller footprint
      level = vim.log.levels.INFO,
      filter = function(notif)
        -- Suppress known noisy deprecation/rewrite toasts
        local suppress_patterns = { "deprecated", "rewritten", "breaking change" }
        for _, p in ipairs(suppress_patterns) do
          if notif.msg:find(p) then return false end
        end
        return true
      end,
    },
  },
  keys = {
    { "<leader>nh", function() Snacks.notifier.show_history() end, desc = "Notification History" },
    { "<leader>nd", function() Snacks.notifier.hide() end, desc = "Dismiss Notifications" },
  },
}
```

For the treesitter deprecation toasts specifically:
```lua
-- Add to init.lua before plugin setup:
vim.g.skip_ts_context_commentstring_module = true
```

For lazy.nvim update checker toasts:
```lua
-- In your lazy.nvim setup call:
require("lazy").setup(plugins, {
  checker = { enabled = true, notify = false },
})
```

### If You Want Maximum Control: noice.nvim Routes

```lua
routes = {
  -- Errors: full notification. Info: subtle virtualtext. Deprecations: suppressed.
  { filter = { event = "notify", find = "deprecated" }, opts = { skip = true } },
  { filter = { event = "notify", find = "No information available" }, opts = { skip = true } },
  { filter = { event = "msg_show", kind = "", find = "written" }, opts = { skip = true } },
  { filter = { event = "notify", min_height = 10 }, view = "split" },
  { filter = { event = "notify", kind = "info" }, view = "mini" },
}
```

---

## Finding 3: Landing Page / Dashboard

### The Problem

When you open `nvim` with no file argument, you get a blank buffer. VSCode shows recent files, recent projects, and quick actions. You have persistence.nvim for session restore but no visual start screen.

### Dashboard Plugin Landscape

**1. [folke/snacks.nvim](https://github.com/folke/snacks.nvim) dashboard** -- Now the **LazyVim default** dashboard. Since you'd be adopting snacks.nvim for notifications anyway, this is the natural choice. Highly configurable sections, recent files, and custom actions.

**2. [goolord/alpha-nvim](https://github.com/goolord/alpha-nvim)** -- The most popular standalone dashboard. Fast, fully programmable, many community themes. Good if you want deep customization without buying into the full snacks ecosystem.

**3. [glepnir/dashboard-nvim](https://github.com/glepnir/dashboard-nvim)** -- Mature dashboard with "doom" and "hyper" themes. Available as a LazyVim extra.

**4. [max397574/startup.nvim](https://github.com/max397574/startup.nvim)** -- Highly configurable with section-based layout. 497 stars. Pre-built themes (dashboard, evil, startify).

**5. [eoh-bse/minintro.nvim](https://github.com/eoh-bse/minintro.nvim)** -- Extremely minimalistic. Just a logo. For users who don't want a dashboard.

### Making the Dashboard High-Utility

Beyond recent files, consider integrating:

**Session management** (you already have persistence.nvim):
- Add dashboard buttons for "Restore Last Session" and "Restore This Directory Session"
- Your existing `<leader>qs`/`<leader>ql` mappings can be surfaced on the dashboard

**Project management**:
- [coffebar/neovim-project](https://github.com/coffebar/neovim-project) -- Maintains project history with quick access via Telescope/Snacks/fzf-lua. Runs on top of session manager to store all open tabs/buffers per project.
- [DrKJeff16/project.nvim](https://github.com/DrKJeff16/project.nvim) -- Actively maintained fork of ahmedkhalf/project.nvim. Auto-detects project roots, includes Snacks picker integration.
- `Snacks.picker.projects()` -- Built-in project picker in snacks.nvim.

**Health/status on dashboard**:
- `:checkhealth` output summary
- Git status via gitsigns.nvim data
- LSP server status
- Plugin update count (from lazy.nvim)

### Recommended Approach

Since snacks.nvim is already recommended for notifications, use **Snacks.dashboard** too:

```lua
{
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { section = "keys",    gap = 1, padding = 1 },
        { section = "recent_files", limit = 8, padding = 1 },
        { section = "projects", limit = 5, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
```

---

## Finding 4: AI-Agent-Friendly Neovim UX (Beyond Chat)

### Emerging Ecosystem

The space has converged around **MCP (Model Context Protocol)** as the dominant way to connect external AI agents to neovim state. Key projects:

| Project | What it exposes | Architecture |
|---|---|---|
| [mcp-diagnostics.nvim](https://github.com/georgeharker/mcp-diagnostics.nvim) | Diagnostic hotspots, LSP navigation, buffer status | Lua plugin or Node.js MCP server |
| [mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server) | 19 tools: cursor, marks, registers, buffers, search, edits | Node.js, connects via `--listen` socket |
| [claudecode.nvim](https://github.com/coder/claudecode.nvim) | Full Claude Code protocol (same as VS Code extension) | Pure Lua, WebSocket MCP |
| [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim) | Built-in neovim server + MCP client hub | Lua plugin |
| [ai-terminals.nvim](https://github.com/aweis89/ai-terminals.nvim) | Diagnostic forwarding, visual selections, command output to CLI AI tools | Terminal bridge via stdin |
| [nvim-mcp](https://github.com/linw1995/nvim-mcp) | LSP hover, diagnostics, code fixes | Rust, multi-transport |

### Error Explanation Plugins

| Plugin | What it does |
|---|---|
| [wtf.nvim](https://github.com/piersolenski/wtf.nvim) | Sends diagnostics + code context to AI, returns explanations. Supports Claude, Copilot, OpenAI, Ollama. |
| [ts-error-translator.nvim](https://github.com/dmmulroy/ts-error-translator.nvim) | Translates 67 TypeScript error codes to plain English. No AI API calls (static lookup). |

### The Architecture That Matters for You

Given your setup with Claude Code running alongside neovim in wezterm, the highest-value integration is:

1. **JSONL notify log** (Finding 1) -- Gives Claude Code a file to tail for real-time error awareness
2. **`diagnostics.json` dump** (Finding 1) -- Structured diagnostic state accessible without RPC
3. **claudecode.nvim** (longer term) -- Full protocol-level integration if you want Claude to see your editor state directly

---

## Recommendations

### Immediate (Low Effort, High Impact)

1. **Add a `vim.notify` JSONL file logger** to your init.lua (see Finding 1 snippet). This solves the "errors disappear" problem and creates an agent-readable log.

2. **Replace nvim-notify with snacks.notifier** configured for bottom-anchored, compact, filtered display. This solves the invasive toast problem and gives you `Snacks.notifier.show_history()`.

3. **Suppress known noisy toasts** -- Add `vim.g.skip_ts_context_commentstring_module = true` and set `checker.notify = false` in lazy.nvim config.

### Medium Term

4. **Add Snacks.dashboard** for a high-utility landing page with recent files, projects, and session restore buttons.

5. **Add a project management plugin** (neovim-project or project.nvim fork) to get VSCode-like "Open Recent Project" workflow.

### Longer Term

6. **Evaluate noice.nvim** for comprehensive message routing (errors prominent, info subtle, deprecations suppressed).

7. **Set up mcp-diagnostics.nvim** for structured AI agent access to your editor's diagnostic state.

8. **Consider claudecode.nvim** for direct Claude Code integration with neovim (same protocol as the VS Code extension).

---

## Sources

### Error Logging
- [neovim/neovim Discussion #30770 -- Logging best practices](https://github.com/neovim/neovim/discussions/30770)
- [LazyVim Discussion #1963 -- Startup error logging](https://github.com/LazyVim/LazyVim/discussions/1963)
- [Neovim Discourse -- More structured lsp.log](https://neovim.discourse.group/t/more-structured-lsp-log/3914)
- [Moritz Hamann -- Neovim Logging Utilities (Oct 2024)](https://moritzhamann.com/blog/2024-10-27-logging-in-neovim.html)
- [neovim/neovim#1029 -- "kill Press ENTER with fire"](https://github.com/neovim/neovim/issues/1029) (milestone 0.12)
- [structlog.nvim](https://github.com/Tastyep/structlog.nvim)
- [notify-log.nvim](https://github.com/BSeblu/notify-log.nvim)

### Notifications
- [snacks.nvim notifier docs](https://github.com/folke/snacks.nvim/blob/main/docs/notifier.md)
- [noice.nvim Guide to Messages](https://github.com/folke/noice.nvim/wiki/A-Guide-to-Messages)
- [noice.nvim Configuration Recipes](https://github.com/folke/noice.nvim/wiki/Configuration-Recipes)
- [fidget.nvim](https://github.com/j-hui/fidget.nvim)
- [nvim-notify](https://github.com/rcarriga/nvim-notify)
- [mini.notify docs](https://nvim-mini.org/mini.nvim/doc/mini-notify.html)
- [nvim-treesitter rewrite discussion #8357](https://github.com/nvim-treesitter/nvim-treesitter/discussions/8357)

### Dashboard / Landing Page
- [snacks.nvim dashboard docs](https://github.com/folke/snacks.nvim/blob/main/docs/dashboard.md)
- [alpha-nvim](https://github.com/goolord/alpha-nvim)
- [dashboard-nvim](https://github.com/glepnir/dashboard-nvim)
- [neovim-project](https://github.com/coffebar/neovim-project)
- [DrKJeff16/project.nvim](https://github.com/DrKJeff16/project.nvim)
- [persistence.nvim](https://github.com/folke/persistence.nvim)

### AI-Agent Integration
- [mcp-diagnostics.nvim](https://github.com/georgeharker/mcp-diagnostics.nvim)
- [mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server)
- [claudecode.nvim](https://github.com/coder/claudecode.nvim)
- [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim)
- [ai-terminals.nvim](https://github.com/aweis89/ai-terminals.nvim)
- [wtf.nvim](https://github.com/piersolenski/wtf.nvim)
- [ts-error-translator.nvim](https://github.com/dmmulroy/ts-error-translator.nvim)
- [ColinKennedy/neovim-ai-plugins (curated list)](https://github.com/ColinKennedy/neovim-ai-plugins)

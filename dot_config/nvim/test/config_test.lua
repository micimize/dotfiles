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

-- smart-splits plugin
check_plugin("smart-splits.nvim", true)

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
  local m = get_keymap("n", "<M-C-H>")  -- Ctrl+Alt encodes as M-C- (Meta first)
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-A-j> mapped (smart-splits resize down)", function()
  local m = get_keymap("n", "<M-C-J>")  -- Ctrl+Alt encodes as M-C- (Meta first)
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-A-k> mapped (smart-splits resize up)", function()
  local m = get_keymap("n", "<M-C-K>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-A-l> mapped (smart-splits resize right)", function()
  local m = get_keymap("n", "<M-C-L>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)

-- Insert-mode navigation keymaps (pane nav is mode-independent)
test("<C-h> mapped in insert mode", function()
  local m = get_keymap("i", "<C-H>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)
test("<C-l> mapped in insert mode", function()
  local m = get_keymap("i", "<C-L>")
  assert_true(m ~= nil, "not found")
  assert_true(m.callback ~= nil, "no callback set")
end)

-- FocusFromEdge command (entry-direction protocol with WezTerm)
test("FocusFromEdge command exists", function()
  local cmds = vim.api.nvim_get_commands({})
  assert_true(cmds.FocusFromEdge ~= nil, "FocusFromEdge command not found")
end)

-- Verify old keymaps were removed (should no longer have <C-w>h as rhs)
test("<C-h> is NOT <C-w>h anymore", function()
  local m = get_keymap("n", "<C-H>")
  assert_true(m ~= nil, "not found")
  assert_true(m.rhs ~= "<C-w>h", "still mapped to old <C-w>h")
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

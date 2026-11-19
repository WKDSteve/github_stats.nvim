-- TESTS/sheets/fixtures/redirect.lua -- send the plugin's `curl` and `gh` to the stand-in fake_github.lua.
--
-- A stand-in first on the PATH (testing.nvim's `fakes`) is not enough: lib.nvim starts `curl` through `vim.system`,
-- and libuv looks only for `.exe` and `.com` on Windows, so a `.cmd` stand-in is passed over and the real `curl`
-- would answer from the real network. So `vim.system` is wrapped: an argv whose program is `curl` or `gh` (with or
-- without `.exe`, or a path to one) becomes `<this nvim> -l fake_github.lua <state-dir> <program> <args...>`, a real
-- process on every system, with no shell and no cmd quoting in between. `vim.fn.executable("gh")` answers 1, so the
-- clone of the data repository takes the `gh` path (the other one would be `git clone https://github.com/...`).
--
-- Called as `chunk(state_dir, fake_path)`. A sheet loads it with `load(text, "=ghs_redirect")`, never `dofile`: a
-- chunk without a file name is runtime to `testing perf`'s trace, so the plugin's own line stays the caller of the
-- start (a `dofile` from `TESTS/` would make every start the sheet's).
local state, fake = ...
local wanted = { curl = true, gh = true }

local function redirect(cmd)
  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" then
    return cmd
  end
  local name = vim.fs.basename(cmd[1]):gsub("%.[eE][xX][eE]$", "")
  if not wanted[name] then
    return cmd
  end
  local copy = { vim.v.progpath, "-n", "-i", "NONE", "--headless", "-u", "NONE", "-l", fake, state, name }
  for i = 2, #cmd do
    copy[#copy + 1] = cmd[i]
  end
  return copy
end

local system = vim.system
---@diagnostic disable-next-line: duplicate-set-field
vim.system = function(cmd, opts, on_exit)
  return system(redirect(cmd), opts, on_exit)
end

local executable = vim.fn.executable
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.executable = function(name)
  if name == "gh" then
    return 1
  end
  return executable(name)
end

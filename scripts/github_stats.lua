---@brief `scripts/github_stats.lua` -- headless entry of github_stats.nvim (collect, report).
---@description
--- A thin wrapper: it puts this plugin and lib.nvim on the runtimepath (`-u NONE` loads neither), then hands
--- `arg` to `github_stats.cli`. Every rule lives in `lua/github_stats/`; there is no second implementation.
---
---     nvim --headless -u NONE -l scripts/github_stats.lua collect            # for a scheduler: once a day
---     nvim --headless -u NONE -l scripts/github_stats.lua report --format=json
---
--- lib.nvim is found through `$LIB_NVIM_DIR`, `$LIB_NVIM_PATH`, `$REPOS_DIR/lib.nvim`, `.deps/lib.nvim`, a sibling
--- checkout, then lazy.nvim's data folder. Like every `nvim -l` script it reads its arguments from the global `arg`.
--- Exit codes: 0 done, 1 a fetch or digest error, 2 usage/configuration, 3 environment.

-- Absolute: `nvim -l github_stats.lua` from inside scripts/ gives a bare relative name, and a relative plugin root
-- would leave `github_stats.*` to be found in whatever runtimepath Neovim has (another checkout).
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(script)))

vim.opt.rtp:prepend(plugin_root)

---@param dir string|nil
---@return boolean
local function has_lib(dir)
  return dir ~= nil and dir ~= "" and vim.fn.isdirectory(dir .. "/lua/lib/nvim") == 1
end

local repos = vim.env.REPOS_DIR
-- Not a list literal: `ipairs` would stop at the first unset variable.
local candidates = {
  LIB_NVIM_DIR = vim.env.LIB_NVIM_DIR,
  LIB_NVIM_PATH = vim.env.LIB_NVIM_PATH,
  REPOS_DIR = (repos and repos ~= "") and (repos .. "/lib.nvim") or nil,
  deps = plugin_root .. "/.deps/lib.nvim",
  sibling = vim.fs.dirname(plugin_root) .. "/lib.nvim",
  lazy = vim.fn.stdpath("data") .. "/lazy/lib.nvim",
}
local lib
for _, key in ipairs({ "LIB_NVIM_DIR", "LIB_NVIM_PATH", "REPOS_DIR", "deps", "sibling", "lazy" }) do
  if has_lib(candidates[key]) then
    lib = candidates[key]
    break
  end
end
if not lib then
  io.stderr:write("error: lib.nvim not found (set LIB_NVIM_DIR, or REPOS_DIR with a lib.nvim checkout)\n")
  os.exit(3)
end
vim.opt.rtp:append(lib)

local argv = {}
for i = 1, #(arg or {}) do
  argv[#argv + 1] = arg[i]
end

local ok, code = pcall(function()
  return require("github_stats.cli").run(argv)
end)
if not ok then
  io.stderr:write("error: ", tostring(code), "\n")
  code = 3
end
io.stdout:flush()
io.stderr:flush()
os.exit(tonumber(code) or 3)

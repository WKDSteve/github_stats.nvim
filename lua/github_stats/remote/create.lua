---@module 'github_stats.remote.create'
---@brief Make a new data repository: the files (workflow, README, config.json, an existing history) and the private GitHub repository.
---@description
--- `M.scaffold` only writes files, so specs and a dry run can look at the result. `M.create` is the whole step the
--- setup guide runs: scaffold, `git init`, the first commit and `gh repo create --private --push`. It runs its
--- commands through `remote.proc.run`, so it suspends inside the guide's coroutine and blocks in a headless script.

local M = {}

local proc = require("github_stats.remote.proc")
local remote = require("github_stats.remote")

local uv = vim.uv or vim.loop

---@return string
function M.plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  -- lua/github_stats/remote/create.lua -> the plugin root, four levels up
  local dir = vim.fs.normalize(vim.fn.fnamemodify(source, ":p"))
  for _ = 1, 4 do
    dir = vim.fs.dirname(dir)
  end
  return dir
end

---@return string
function M.template_dir()
  return M.plugin_root() .. "/templates/vault"
end

---@param text string
---@param values table<string, string>
---@return string
local function fill(text, values)
  return (text:gsub("{{([%u_]+)}}", function(key)
    return values[key] or ("{{" .. key .. "}}")
  end))
end

---@param path string
---@return string|nil
local function read_file(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

---@param path string
---@param text string
---@return boolean ok
---@return string|nil err
local function write_file(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd, err = io.open(path, "wb")
  if not fd then
    return false, err
  end
  fd:write(text)
  fd:close()
  return true, nil
end

---Copy every file under `from` into `to` (not `.git`). Existing files in `to` are overwritten.
---@param from string
---@param to string
---@return integer copied
---@return string|nil err
function M.copy_tree(from, to)
  local copied = 0
  for name, kind in vim.fs.dir(from, { depth = math.huge }) do
    local first = name:match("^[^/\\]+")
    if first ~= ".git" then
      local src = from .. "/" .. name
      local dst = to .. "/" .. name
      if kind == "directory" then
        vim.fn.mkdir(dst, "p")
      elseif kind == "file" then
        vim.fn.mkdir(vim.fs.dirname(dst), "p")
        local ok, err = uv.fs_copyfile(src, dst)
        if not ok then
          return copied, ("copying %s failed: %s"):format(name, tostring(err))
        end
        copied = copied + 1
      end
    end
  end
  return copied, nil
end

---@class GHStats.Remote.ScaffoldOpts
---@field repo string "owner/name"
---@field seed_dir? string A local history to take over (its config.json, data/ and the rest)
---@field plugin_ref? string Branch of github_stats.nvim the workflow uses (default "main")
---@field lib_ref? string Branch of lib.nvim (default "main")

---Write the files of a data repository into `dir`.
---@param dir string
---@param opts GHStats.Remote.ScaffoldOpts
---@return boolean ok
---@return string|nil err
---@return integer copied files taken over from `seed_dir`
function M.scaffold(dir, opts)
  if not remote.valid_repo(opts.repo) then
    return false, ("not a repository name: %s"):format(tostring(opts.repo)), 0
  end
  vim.fn.mkdir(dir, "p")

  local copied = 0
  if opts.seed_dir and vim.fn.isdirectory(opts.seed_dir) == 1 then
    local err
    copied, err = M.copy_tree(opts.seed_dir, dir)
    if err then
      return false, err, copied
    end
  end

  local values = {
    PLUGIN_URL = remote.PLUGIN_URL,
    PLUGIN_REF = opts.plugin_ref or "main",
    LIB_URL = remote.LIB_URL,
    LIB_REF = opts.lib_ref or "main",
    PLUGIN_HOME = (remote.PLUGIN_URL:gsub("%.git$", "")),
    REPO = opts.repo,
  }
  local templates = M.template_dir()
  for _, rel in ipairs({ ".github/workflows/collect.yml", "README.md", ".gitignore" }) do
    local text = read_file(templates .. "/" .. rel)
    if not text then
      return false, ("template missing: %s/%s"):format(templates, rel), copied
    end
    -- The workflow is always ours; a README or .gitignore the history already had stays.
    local target = dir .. "/" .. rel
    if rel == ".github/workflows/collect.yml" or vim.fn.filereadable(target) == 0 then
      local ok, err = write_file(target, fill(text, values))
      if not ok then
        return false, err, copied
      end
    end
  end

  if vim.fn.filereadable(dir .. "/config.json") == 0 then
    local ok, err = require("lib.nvim.fs.json").write(dir .. "/config.json", require("github_stats.config.DEFAULTS"))
    if not ok then
      return false, err, copied
    end
  end
  return true, nil, copied
end

---@class GHStats.Remote.CreateOpts : GHStats.Remote.ScaffoldOpts
---@field dir string Where the clone lives on this machine (must not exist yet, or be empty)

---Create the data repository: files, first commit, private GitHub repository, push.
---@param opts GHStats.Remote.CreateOpts
---@return boolean ok
---@return string|nil err
---@return integer copied
function M.create(opts)
  local dir = opts.dir
  if vim.fn.isdirectory(dir) == 1 and #vim.fn.readdir(dir) > 0 then
    return false, ("%s exists and is not empty"):format(dir), 0
  end
  local ok, err, copied = M.scaffold(dir, opts)
  if not ok then
    return false, err, copied
  end

  local steps = {
    { "git", "-C", dir, "init", "--quiet", "-b", "main" },
    { "git", "-C", dir, "add", "-A" },
    { "git", "-C", dir, "commit", "--quiet", "-m", "init: github_stats.nvim data repository" },
    {
      "gh",
      "repo",
      "create",
      opts.repo,
      "--private",
      "--description",
      "GitHub traffic history, collected daily by github_stats.nvim",
      "--source",
      dir,
      "--remote",
      "origin",
      "--push",
    },
  }
  for _, cmd in ipairs(steps) do
    local res = proc.run(cmd, { timeout_ms = 600000 })
    if not res.ok then
      return false, ("%s %s: %s"):format(cmd[1], cmd[cmd[1] == "git" and 4 or 2], proc.reason(res)), copied
    end
  end
  return true, nil, copied
end

return M

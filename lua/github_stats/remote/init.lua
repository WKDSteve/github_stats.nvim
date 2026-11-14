---@module 'github_stats.remote'
---@brief Where the history lives: a data repository GitHub Actions fills ("remote", the default) or this machine's own folder ("local").
---@description
--- Remote mode: a private GitHub repository holds `config.json` and `data/`. A scheduled workflow in it
--- (`templates/vault/.github/workflows/collect.yml`) runs `scripts/github_stats.lua collect` once a day and commits
--- the result. Every machine only clones and pulls it: the same history everywhere, nothing fetched twice, no commits
--- of stats in an editor config, and no 14-day window lost on a day without an editor.
---
--- Local mode is the plugin as it was: this Neovim fetches into its own folder (`config_dir`/`data_dir`).
---
--- How the mode is decided, first match wins:
---   1. `setup({ storage = "local" | "remote" | { mode = ... } })`
---   2. `setup({ config_dir = ... })` or `data_dir`: the user manages the folder, so "local"
---   3. the answer of the setup guide on this machine (the state file, `M.state_file()`)
---   4. "remote"
--- The repository and the clone folder come from `storage.repo`/`storage.dir`, else from the state file. Remote mode
--- without a known repository is "unset": the plugin keeps fetching locally until the guide (`:GithubStats setup`)
--- has run, so nothing is lost while the user decides.

local M = {}

local proc = require("github_stats.remote.proc")

M.WORKFLOW_FILE = "collect.yml"
M.SECRET_NAME = "GH_STATS_TOKEN"
M.DEFAULT_REPO_NAME = "github-stats-vault"
M.PLUGIN_URL = "https://github.com/WKDSteve/github_stats.nvim.git"
M.LIB_URL = "https://github.com/WKDSteve/lib.nvim.git"

---@alias GHStats.StorageMode "remote"|"local"
---@alias GHStats.StorageStatus "local"|"ready"|"clone"|"unset"

---What `setup()` takes as `storage`: the mode alone, or a table.
---@class GHStats.StorageOptions
---@field mode? GHStats.StorageMode
---@field repo? string "owner/name" of the data repository
---@field dir? string Where it is cloned (default: `stdpath("data")/github_stats.nvim-vault`)
---@field pull_interval_minutes? integer How often a running editor pulls (default 60)

---The resolved storage of this session.
---@class GHStats.Storage
---@field mode GHStats.StorageMode
---@field repo string|nil
---@field dir string
---@field pull_interval_minutes integer
---@field explicit_mode boolean The mode came from `setup()`
---@field deferred boolean The user chose "later" in the guide: it does not open by itself again

---What the state file keeps for this machine.
---@class GHStats.StorageState
---@field mode? GHStats.StorageMode
---@field repo? string
---@field dir? string
---@field deferred? boolean

---@type GHStats.Storage|nil
local current = nil

---@return string
function M.state_file()
  return vim.fn.stdpath("data") .. "/github_stats.nvim-remote.json"
end

---@return string
function M.default_dir()
  return vim.fn.stdpath("data") .. "/github_stats.nvim-vault"
end

---@return GHStats.StorageState
function M.read_state()
  local parsed = require("lib.nvim.fs.json").read(M.state_file())
  return type(parsed) == "table" and parsed or {}
end

---Merge `patch` into the state file (a `false` value removes a key).
---@param patch GHStats.StorageState|table
---@return boolean ok
---@return string|nil err
function M.write_state(patch)
  local state = M.read_state()
  for key, value in pairs(patch) do
    if value == false and key ~= "deferred" then
      state[key] = nil
    else
      state[key] = value
    end
  end
  vim.fn.mkdir(vim.fs.dirname(M.state_file()), "p")
  return require("lib.nvim.fs.json").write(M.state_file(), state)
end

---@param repo any
---@return boolean
function M.valid_repo(repo)
  return type(repo) == "string" and repo:match("^[%w._-]+/[%w._-]+$") ~= nil
end

---Decide the storage from the `setup()` options and the state file (see the module header).
---@param opts table|nil the options given to `setup()`
---@param state GHStats.StorageState|nil defaults to the state file
---@return GHStats.Storage storage
---@return string|nil err a value in `opts.storage` that was ignored
function M.resolve(opts, state)
  opts = opts or {}
  state = state or M.read_state()
  local raw = opts.storage
  local err

  ---@type GHStats.StorageOptions
  local given = {}
  if type(raw) == "string" then
    given.mode = raw
  elseif type(raw) == "table" then
    given = raw
  elseif raw ~= nil then
    err = ("storage must be a string or a table, got %s"):format(type(raw))
  end

  -- A copy: the caller's table is not ours to change.
  given = vim.deepcopy(given)
  if given.mode ~= nil and given.mode ~= "remote" and given.mode ~= "local" then
    err = ("storage.mode must be 'remote' or 'local', got %s"):format(vim.inspect(given.mode))
    given.mode = nil
  end
  if given.repo ~= nil and not M.valid_repo(given.repo) then
    err = ("storage.repo must look like owner/name, got %s"):format(vim.inspect(given.repo))
    given.repo = nil
  end

  local custom_paths = opts.config_dir ~= nil or opts.data_dir ~= nil
  local mode = given.mode
    or (custom_paths and "local")
    or ((state.mode == "local" or state.mode == "remote") and state.mode)
    or "remote"

  local dir = given.dir or state.dir or M.default_dir()
  local interval = tonumber(given.pull_interval_minutes) or 60
  if interval < 1 then
    interval = 60
  end

  return {
    mode = mode,
    repo = given.repo or (M.valid_repo(state.repo) and state.repo or nil),
    dir = vim.fs.normalize(vim.fn.expand(dir)),
    pull_interval_minutes = math.floor(interval),
    explicit_mode = given.mode ~= nil,
    deferred = state.deferred == true,
  },
    err
end

---@param s GHStats.Storage
---@return GHStats.StorageStatus
function M.status(s)
  if s.mode == "local" then
    return "local"
  end
  if vim.fn.isdirectory(s.dir .. "/.git") == 1 then
    return "ready"
  end
  if s.repo then
    return "clone"
  end
  return "unset"
end

---@param s GHStats.Storage|nil
---@return nil
function M.set_current(s)
  current = s
end

---@return GHStats.Storage|nil
function M.current()
  return current
end

---Whether this session reads its history from the data repository (and must not fetch itself).
---@return boolean
function M.active()
  return current ~= nil and M.status(current) == "ready"
end

-- -----------------------------------------------------------------------------------------------
-- git on the clone
-- -----------------------------------------------------------------------------------------------

---Clone the data repository into `s.dir` (through `gh` when it is there: it brings the credentials).
---@param s GHStats.Storage
---@param on_done fun(ok: boolean, err: string|nil)
---@return nil
function M.clone(s, on_done)
  if not s.repo then
    on_done(false, "no data repository known")
    return
  end
  vim.fn.mkdir(vim.fs.dirname(s.dir), "p")
  local cmd
  if vim.fn.executable("gh") == 1 then
    cmd = { "gh", "repo", "clone", s.repo, s.dir, "--", "--quiet" }
  else
    cmd = { "git", "clone", "--quiet", ("https://github.com/%s.git"):format(s.repo), s.dir }
  end
  proc.exec(cmd, { timeout_ms = 300000 }, function(res)
    on_done(res.ok, res.ok and nil or proc.reason(res))
  end)
end

---Pull the data repository (fast-forward only: the workflow is the only writer of `data/`).
---@param s GHStats.Storage
---@param on_done fun(ok: boolean, err: string|nil, changed: boolean)
---@return nil
function M.pull(s, on_done)
  proc.exec({ "git", "-C", s.dir, "rev-parse", "HEAD" }, nil, function(before)
    proc.exec({ "git", "-C", s.dir, "pull", "--ff-only", "--quiet" }, nil, function(res)
      if not res.ok then
        on_done(false, proc.reason(res), false)
        return
      end
      proc.exec({ "git", "-C", s.dir, "rev-parse", "HEAD" }, nil, function(after)
        on_done(true, nil, vim.trim(before.stdout) ~= vim.trim(after.stdout))
      end)
    end)
  end)
end

---Commit and push a changed `config.json` (the one file a machine writes), after a rebase onto what the workflow
---pushed in the meantime. Nothing to do is a success.
---@param s GHStats.Storage
---@param on_done fun(ok: boolean, err: string|nil, pushed: boolean)
---@return nil
function M.push_config(s, on_done)
  proc.exec({ "git", "-C", s.dir, "status", "--porcelain", "--", "config.json" }, nil, function(st)
    if not st.ok then
      on_done(false, proc.reason(st), false)
      return
    end
    if vim.trim(st.stdout) == "" then
      on_done(true, nil, false)
      return
    end
    proc.exec(
      { "git", "-C", s.dir, "commit", "--quiet", "-m", "config: tracked repositories changed", "--", "config.json" },
      nil,
      function(commit)
        if not commit.ok then
          on_done(false, proc.reason(commit), false)
          return
        end
        proc.exec({ "git", "-C", s.dir, "pull", "--rebase", "--quiet" }, nil, function(rebase)
          if not rebase.ok then
            on_done(false, proc.reason(rebase), false)
            return
          end
          proc.exec({ "git", "-C", s.dir, "push", "--quiet" }, nil, function(push)
            on_done(push.ok, push.ok and nil or proc.reason(push), push.ok)
          end)
        end)
      end
    )
  end)
end

---After new data arrived: forget what was read before and bring the digests other programs read up to date.
---@return nil
local function after_new_data()
  pcall(function()
    require("github_stats.storage").invalidate()
  end)
  pcall(function()
    require("github_stats.digest").refresh_if_stale()
  end)
end

---One sync: push a changed config.json, then pull. `quiet` reports failures only.
---@param on_done? fun(ok: boolean, err: string|nil, changed: boolean)
---@param quiet? boolean
---@return nil
function M.sync(on_done, quiet)
  local config = require("github_stats.config")
  local s = current
  local function finish(ok, err, changed)
    if on_done then
      on_done(ok, err, changed)
    end
  end
  if not s or M.status(s) ~= "ready" then
    local reason = "no data repository in use (:GithubStats setup)"
    if not quiet then
      config.notify("[github-stats] " .. reason, "warn")
    end
    finish(false, reason, false)
    return
  end
  M.push_config(s, function(ok_push, err_push, pushed)
    if not ok_push then
      config.notify(("[github-stats] Pushing config.json failed: %s"):format(err_push or "?"), "warn")
    end
    M.pull(s, function(ok, err, changed)
      if not ok then
        config.notify(("[github-stats] Pulling %s failed: %s"):format(s.repo or s.dir, err or "?"), "warn")
      else
        if changed then
          after_new_data()
        end
        if not quiet then
          local what = changed and "new data pulled" or "already up to date"
          config.notify(
            ("[github-stats] %s: %s%s"):format(s.repo or s.dir, what, pushed and ", config.json pushed" or ""),
            "info"
          )
        end
      end
      finish(ok, err, changed)
    end)
  end)
end

---The data repository's name, read from the clone's `origin` when the state has none (a clone made by hand).
---@param s GHStats.Storage
---@return string|nil
function M.repo_of(s)
  if s.repo then
    return s.repo
  end
  local res = proc.run({ "git", "-C", s.dir, "remote", "get-url", "origin" }, { timeout_ms = 10000 })
  if not res.ok then
    return nil
  end
  local owner, name = vim.trim(res.stdout):match("github%.com[:/]([%w._-]+)/([%w._-]+)$")
  if not owner then
    return nil
  end
  return owner .. "/" .. name:gsub("%.git$", "")
end

---Start the workflow now (`gh workflow run`), instead of waiting for tomorrow's run.
---@param on_done fun(ok: boolean, err: string|nil)
---@return nil
function M.dispatch(on_done)
  local s = current
  local repo = s and M.repo_of(s)
  if not repo then
    on_done(false, "no data repository in use (:GithubStats setup)")
    return
  end
  if vim.fn.executable("gh") ~= 1 then
    on_done(false, ("the GitHub CLI (gh) is not installed; start it on github.com/%s/actions"):format(repo))
    return
  end
  proc.exec({ "gh", "workflow", "run", M.WORKFLOW_FILE, "-R", repo }, nil, function(res)
    on_done(res.ok, res.ok and nil or proc.reason(res))
  end)
end

return M

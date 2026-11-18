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
---The tag a data repository's workflow clones github_stats.nvim and lib.nvim at: immutable, set on both repositories,
---not a release. A new one is cut only when the collect path changes (docs/FEATURES/REMOTE.md, "Pinned code"); the
---setup guide offers to move an older workflow to it.
M.COLLECT_REF = "collect-2026.11.14"

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
  interval = math.floor(interval)

  -- The sync on start: nil follows the pull interval, true is every start, false never, a number of minutes is the
  -- least age of the last sync before a start pulls again.
  local on_start = given.sync_on_start
  ---@type integer|false
  local start_minutes = interval
  if on_start == true then
    start_minutes = 0
  elseif on_start == false then
    start_minutes = false
  elseif type(on_start) == "number" and on_start >= 0 then
    start_minutes = math.floor(on_start)
  elseif on_start ~= nil then
    err = ("storage.sync_on_start must be true, false or minutes >= 0, got %s"):format(vim.inspect(on_start))
  end

  return {
    mode = mode,
    repo = given.repo or (M.valid_repo(state.repo) and state.repo or nil),
    dir = vim.fs.normalize(vim.fn.expand(dir)),
    pull_interval_minutes = interval,
    sync_on_start = start_minutes,
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

---The git client of the clone: `lib.nvim.git` (its network verbs never wait for a password prompt). Specs replace it.
M.git = require("lib.nvim.git")

---Pull the data repository (fast-forward only: the workflow is the only writer of `data/`).
---@param s GHStats.Storage
---@param on_done fun(ok: boolean, err: string|nil, changed: boolean)
---@return nil
function M.pull(s, on_done)
  M.git.pull_async({ dir = s.dir }, function(ok, err, changed)
    -- `changed` is nil when git could not say (no HEAD before the pull): then the read memo is dropped anyway.
    on_done(ok, err, ok and changed ~= false)
  end)
end

---Commit `path` when it changed, rebase onto what the workflow pushed in the meantime, push. Nothing to commit is a
---success with `pushed = false`.
---@param s GHStats.Storage
---@param path string relative to the clone
---@param message string
---@param on_done fun(ok: boolean, err: string|nil, pushed: boolean)
---@return nil
local function commit_and_push(s, path, message, on_done)
  local git = M.git
  local opts = { dir = s.dir, timeout_ms = 120000, env = { GIT_TERMINAL_PROMPT = "0" } }
  local function failed(res)
    on_done(false, proc.reason(res), false)
  end
  git.run_async({ "status", "--porcelain", "--", path }, opts, function(st)
    if not st.ok then
      return failed(st)
    end
    if vim.trim(st.stdout or "") == "" then
      on_done(true, nil, false)
      return
    end
    git.run_async({ "add", "--", path }, opts, function(add)
      if not add.ok then
        return failed(add)
      end
      git.run_async({ "commit", "--quiet", "-m", message, "--", path }, opts, function(commit)
        if not commit.ok then
          return failed(commit)
        end
        git.run_async({ "pull", "--rebase", "--quiet" }, opts, function(rebase)
          if not rebase.ok then
            return failed(rebase)
          end
          git.push_async({ dir = s.dir }, function(ok, err)
            on_done(ok, err, ok)
          end)
        end)
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
  commit_and_push(s, "config.json", "config: tracked repositories changed", on_done)
end

---Where the workflow lives in a clone.
---@param s GHStats.Storage
---@return string
function M.workflow_path(s)
  return s.dir .. "/.github/workflows/" .. M.WORKFLOW_FILE
end

---The github_stats.nvim ref the clone's workflow runs (`PLUGIN_REF`), nil when there is no workflow or no pin in it.
---@param s GHStats.Storage
---@return string|nil
function M.workflow_ref(s)
  local fd = io.open(M.workflow_path(s), "rb")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text:match('PLUGIN_REF:%s*"([^"]+)"')
end

---Whether the clone's workflow runs another github_stats.nvim than this plugin's pin (`M.COLLECT_REF`).
---@param s GHStats.Storage
---@return boolean outdated
---@return string|nil ref what it runs now
function M.workflow_outdated(s)
  local ref = M.workflow_ref(s)
  return ref ~= nil and ref ~= M.COLLECT_REF, ref
end

---Rewrite the clone's workflow from this plugin's template (pinned to `M.COLLECT_REF`), commit and push it. Pushing a
---workflow file needs a token with the `workflow` scope (git's credential helper or `gh auth setup-git`).
---@param s GHStats.Storage
---@param on_done fun(ok: boolean, err: string|nil, pushed: boolean)
---@return nil
function M.update_workflow(s, on_done)
  local repo = M.repo_of(s)
  if not repo then
    on_done(false, "the clone's origin names no GitHub repository", false)
    return
  end
  local ok, err = require("github_stats.remote.create").write_workflow(s.dir, repo)
  if not ok then
    on_done(false, err, false)
    return
  end
  commit_and_push(
    s,
    ".github/workflows/" .. M.WORKFLOW_FILE,
    ("workflow: run github_stats.nvim and lib.nvim at %s"):format(M.COLLECT_REF),
    on_done
  )
end

-- -----------------------------------------------------------------------------------------------
-- The sync on start: at most once per `sync_on_start` minutes, remembered across sessions
-- -----------------------------------------------------------------------------------------------

---The clock the stamp is read and written with (seconds). Specs replace it.
M.now = os.time

---Where the time of the last sync attempt is kept: machine state, not data, so `stdpath("state")`.
---@return string
function M.stamp_file()
  return vim.fn.stdpath("state") .. "/github_stats.nvim-last-sync.json"
end

---When a sync of the clone at `s.dir` last ran (successful or not), nil when never (or another clone's did).
---@param s GHStats.Storage
---@return integer|nil
function M.last_sync(s)
  local parsed = require("lib.nvim.fs.json").read(M.stamp_file())
  if type(parsed) ~= "table" or parsed.dir ~= s.dir or type(parsed.time) ~= "number" then
    return nil
  end
  return parsed.time
end

---Remember that a sync of the clone at `s.dir` ran now. A stamp that cannot be written only costs the next start a sync.
---@param s GHStats.Storage
---@return nil
function M.mark_synced(s)
  pcall(function()
    vim.fn.mkdir(vim.fs.dirname(M.stamp_file()), "p")
    require("lib.nvim.fs.json").write(M.stamp_file(), { time = M.now(), dir = s.dir })
  end)
end

---Whether the sync on start is due: `sync_on_start` is not false and the last sync of this clone (in any session,
---successful or not) is at least `sync_on_start` minutes old. A stamp from the future (a clock set back) is due.
---@param s GHStats.Storage
---@return boolean
function M.start_sync_due(s)
  local minutes = s.sync_on_start
  if minutes == nil then
    minutes = s.pull_interval_minutes
  end
  if minutes == false then
    return false
  end
  if minutes == nil or minutes <= 0 then
    return true
  end
  local last = M.last_sync(s)
  if not last then
    return true
  end
  local age = M.now() - last
  return age < 0 or age >= minutes * 60
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

---Callers waiting for the sync that is running; nil while none runs. Two at once would race for git's index lock
---(the background cycle and a dashboard refresh), so a second caller waits for the first one's result instead.
---@type (fun(ok: boolean, err: string|nil, changed: boolean))[]|nil
local waiting = nil

---One sync: push a changed config.json, then pull. `quiet` reports failures only. While one runs, a second call
---gets that one's result.
---@param on_done? fun(ok: boolean, err: string|nil, changed: boolean)
---@param quiet? boolean
---@return nil
function M.sync(on_done, quiet)
  if waiting then
    if on_done then
      waiting[#waiting + 1] = on_done
    end
    return
  end
  waiting = {}
  if on_done then
    waiting[1] = on_done
  end
  local config = require("github_stats.config")
  local s = current
  local function finish(ok, err, changed)
    local callers = waiting or {}
    waiting = nil
    for _, cb in ipairs(callers) do
      pcall(cb, ok, err, changed)
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
      -- Stamped whether it worked or not: a pull that fails every time (a clone git refuses to fast-forward) would
      -- otherwise cost every start its processes and a round trip again. The recurring cycle retries anyway.
      M.mark_synced(s)
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
  local url = M.git.remote_url("origin", { dir = s.dir })
  if not url then
    return nil
  end
  local owner, name = vim.trim(url):match("github%.com[:/]([%w._-]+)/([%w._-]+)$")
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

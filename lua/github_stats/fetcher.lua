---@module 'github_stats.fetcher'
---@brief Orchestrates fetching from multiple repositories
---@description
--- Coordinates parallel fetching of all metrics for configured repositories.
--- Manages fetch intervals and provides both automatic and manual fetch triggers.
---
--- A full fetch is four API calls per repository, so over a dozen-plus
--- repositories on a slow link it can run for a while with nothing to show for
--- it. `lib.nvim.progress` (optional dependency) reports it live — but only for
--- manual fetches: a silent background cycle stays silent, matching the existing
--- `background` convention below.

local config = require("github_stats.config")
local api = require("github_stats.api")
local storage = require("github_stats.storage")

local M = {}

local str_format = string.format

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

---@internal
---Starts a progress handle, or returns nil when lib.nvim isn't installed.
---@param total integer Number of repositories being fetched
---@return table|nil
local function new_progress(total)
  if not ok_progress then
    return nil
  end
  local cfg = config.get()
  local handle = progress_mod.create({
    title = "[github-stats]",
    style = (cfg and cfg.progress_style) or "auto",
  })
  handle:update({ text = str_format("fetching %d repositories", total), current = 0, total = total })
  return handle
end

---Store for detailed error information (accessible via debug command)
---@type GHStats.FetchSummary?
M.last_fetch_summary = nil

---@internal
---Get path to last_fetch tracking file
---
---`config.get_config_dir()` directly, not `get_storage_root() .. "/../..."`.
---The latter embeds a literal `..` in the string handed to
---`lib.nvim.fs.json`'s mkdir/write/rename calls (the same construction
---`github_stats.retention` had, and the same fix): resolving it correctly
---depends on every layer between here and the syscall agreeing, which held
---on this plugin's dev machine and did not on at least one CI runner.
---`get_config_dir()` names the same directory with no traversal to resolve.
---@return string
local function get_last_fetch_file()
  return config.get_config_dir() .. "/last_fetch.json"
end

---@internal
---Load last fetch timestamp. Delegates the read+decode to lib.nvim.fs.json.
---@return number? # Unix timestamp of last fetch, or nil
local function load_last_fetch()
  local data = require("lib.nvim.fs.json").read(get_last_fetch_file())
  return data and data.timestamp
end

---@internal
---Save current fetch timestamp. Delegates the encode+atomic-write to
---lib.nvim.fs.json.write (which also creates parent directories).
---@param timestamp number Unix timestamp
local function save_last_fetch(timestamp)
  require("lib.nvim.fs.json").write(get_last_fetch_file(), { timestamp = timestamp })
end

---@internal
---Check if fetch interval has elapsed
---@return boolean # True if enough time has passed
local function should_fetch()
  local cfg = config.get()
  if not cfg then
    return false
  end

  local last_fetch = load_last_fetch()
  if not last_fetch then
    return true -- Never fetched before
  end

  local now = os.time()
  local interval_seconds = cfg.fetch_interval_hours * 3600
  local elapsed = now - last_fetch

  return elapsed >= interval_seconds
end

---Whether a fetch without `force` would run now. `:GithubStats fetch` asks
---before a fetch is skipped instead of telling the user to retype it with
---`force` (UI-05). The second result says how long ago the last fetch was and
---what the interval is, both in hours; `nil` when nothing was fetched yet.
---@return boolean due
---@return { since_hours: number, interval_hours: number }|nil info
function M.fetch_due()
  local due = should_fetch()
  local cfg = config.get()
  local last = load_last_fetch()
  if not cfg or not last then
    return due, nil
  end
  return due, { since_hours = (os.time() - last) / 3600, interval_hours = cfg.fetch_interval_hours }
end

---@internal
---An empty completion summary for M.fetch_all's early-return paths below:
---nothing was fetched, but a passed `callback` must still be told the
---attempt is over rather than left waiting forever (ERR-03) -- distinct
---from M.last_fetch_summary, which stays untouched here since neither path
---is an actual fetch attempt.
---@return GHStats.FetchSummary
local function empty_summary()
  return { success = {}, errors = {}, timestamp = os.date("%Y-%m-%dT%H:%M:%S") }
end

---@internal
---Repositories named by `repo/metric` success entries, in first-seen order.
---Repository names contain one "/" themselves, so the metric is split off the
---last one.
---@param entries string[]
---@return string[]
local function repos_of(entries)
  local seen, repos = {}, {}
  for _, entry in ipairs(entries) do
    local repo = entry:match("^(.*)/[^/]+$")
    if repo and not seen[repo] then
      seen[repo] = true
      repos[#repos + 1] = repo
    end
  end
  return repos
end

---@internal
---Repositories fetch_all keeps in flight at once (`max_parallel_fetches`,
---default 4). Anything that is not a positive number falls back to the
---default rather than disabling the cap or stalling the queue.
---@return integer
local function max_parallel_fetches()
  local cfg = config.get()
  local n = cfg and cfg.max_parallel_fetches
  if type(n) ~= "number" or n < 1 then
    return 4
  end
  return math.floor(n)
end

---Fetch all repositories and metrics
---@param force boolean Whether to bypass interval check
---@param callback? fun(summary: GHStats.FetchSummary) Optional completion callback
---@param opts? { background?: boolean } When `background` is true, this is a
---  silent background cycle: the "starting fetch"/"no repos configured"/
---  "interval not elapsed" info notifications are suppressed, but the
---  "fetched N, M errors" notification still fires (still subject to
---  `notification_level`) so real problems aren't hidden.
function M.fetch_all(force, callback, opts)
  opts = opts or {}
  local background = opts.background == true

  local repos = config.get_repos()

  if #repos == 0 then
    if not background then
      config.notify("[github-stats] No repositories configured", "warn")
    end
    if callback then
      callback(empty_summary())
    end
    return
  end

  local cfg = config.get()
  local notify_fetch = cfg ~= nil and cfg.notify_fetch

  -- Inside the interval only the repositories without any stored data are fetched (a repository
  -- that was just added to the list, or found through `watch_users`); the rest waits for its
  -- interval. Such a partial fetch leaves last_fetch.json alone, so it never pushes the regular
  -- full fetch out by a day.
  local partial = false
  if not force and not should_fetch() then
    local fresh = {}
    for _, repo in ipairs(repos) do
      if not storage.has_data(repo) then
        fresh[#fresh + 1] = repo
      end
    end
    if #fresh == 0 then
      if notify_fetch == true and not background then
        config.notify("[github-stats] Fetch interval not elapsed (use 'force' to bypass)", "info")
      end
      if callback then
        callback(empty_summary())
      end
      return
    end
    repos, partial = fresh, true
  end

  if partial then
    -- Also in a background cycle: something new is being fetched, which is worth one line.
    config.notify(
      str_format(
        "[github-stats] Fetching %d new repositor%s: %s",
        #repos,
        #repos == 1 and "y" or "ies",
        table.concat(repos, ", ")
      ),
      "info"
    )
  elseif not background then
    config.notify(str_format("[github-stats] Starting fetch: %d repos, force=%s", #repos, tostring(force)), "info")
  end

  local all_success = {}
  local all_errors = {}

  -- Manual fetches only: a background cycle is meant to be invisible, and an
  -- indicator that appears on a timer the user didn't trigger is noise.
  local progress = (not background) and new_progress(#repos) or nil

  ---@param results ({ success: string[], errors: table<string, string> }|nil)[] per repository, in list order
  ---@param start_errors any[] per repository: what its fetch threw while starting
  local function finish(results, start_errors)
    for i, repo in ipairs(repos) do
      local result = results[i]
      if result then
        vim.list_extend(all_success, result.success)
        all_errors = vim.tbl_extend("force", all_errors, result.errors)
      end
      if start_errors[i] ~= nil then
        all_errors[repo] = str_format("fetch failed to start: %s", tostring(start_errors[i]))
      end
    end

    -- Save fetch timestamp (not for a partial fetch of new repositories only: the interval of
    -- everything else is still running)
    if not partial then
      save_last_fetch(os.time())
    end

    -- Opportunistically fold old clones/views days into the archive and
    -- prune stale referrers/paths snapshots. Internally rate-limited to
    -- once/24h (github_stats.retention.maybe_run_all), so this is cheap on
    -- every fetch that isn't the first one of the day.
    local retention = require("github_stats.retention")
    retention.maybe_run_all_async(function(retention_summary)
      if retention_summary and not background then
        local touched = retention_summary.compacted_deleted + retention_summary.pruned_deleted
        if touched > 0 then
          config.notify(
            str_format(
              "[github-stats] Retention: archived %d day(s), removed %d files (%s freed)",
              retention_summary.archived,
              touched,
              retention.format_bytes(retention_summary.freed_bytes)
            ),
            "info"
          )
        end
        if vim.tbl_count(retention_summary.errors) > 0 then
          config.notify(
            str_format(
              "[github-stats] Retention had %d error(s), see :GithubStats debug",
              vim.tbl_count(retention_summary.errors)
            ),
            "warn"
          )
        end
      end

      -- Publish the digest other programs read (github_stats.digest) for the
      -- repositories that got any data this cycle. Deferred and pcall-wrapped
      -- inside write_later: a digest problem must never fail or slow a fetch.
      -- After retention, which moves days into the archive the digest reads.
      require("github_stats.digest").write_later(repos_of(all_success))
    end)

    -- Create summary
    local summary = {
      success = all_success,
      errors = all_errors,
      timestamp = os.date("%Y-%m-%dT%H:%M:%S"),
    }

    -- Store for debug access
    M.last_fetch_summary = summary

    -- Closed before the notifications below, so the indicator is gone by
    -- the time the summary appears rather than lingering behind it.
    if progress then
      progress:finish(str_format("fetched %d metrics", #all_success))
    end

    -- Notify user: error summary always fires (still gated by
    -- notification_level) even in background mode, so real problems
    -- surface; the plain success message is suppressed in the background.
    local error_count = vim.tbl_count(all_errors)
    if error_count > 0 then
      config.notify(str_format("[github-stats] Fetched %d metrics, %d errors", #all_success, error_count), "warn")
    elseif not background then
      config.notify(str_format("[github-stats] Successfully fetched %d metrics", #all_success), "info")
    end

    if callback then
      callback(summary)
    end
  end

  -- At most `max_parallel_fetches` repositories in flight; the rest wait and
  -- start as slots free up. Every repository is four curl spawns, and a spawn
  -- costs ~10-15 ms of synchronous process creation on Windows (far more when
  -- AV/EDR scans each one), so starting them all in one loop blocked the UI
  -- for the whole burst. Refills happen from completion callbacks, i.e. from
  -- the event loop, so the UI gets a turn between each batch of spawns.
  -- lib.nvim's map_limit runs the queue: a fetch that throws while starting
  -- (vim.system raises when a spawn fails) counts as that repository's error
  -- instead of stranding the rest of the list and the callback.
  local function fetch_one(repo, _, done)
    M.fetch_repo(repo, function(success, errors)
      done({ success = success, errors = errors })
    end)
  end

  local on_progress = progress
    and function(count, total)
      progress:update({
        text = str_format("%d of %d repositories", count, total),
        current = count,
        total = total,
      })
    end

  require("lib.nvim.async").map_limit(repos, max_parallel_fetches(), fetch_one, finish, {
    on_progress = on_progress or nil,
  })
end

---Automatic fetch (respects interval)
function M.auto_fetch()
  M.fetch_all(false)
end

---Manual fetch with force option
---@param force boolean Whether to force fetch
function M.manual_fetch(force)
  M.fetch_all(force)
end

---Fetch all metrics for a single repository. Shared by fetch_all's
---per-repo loop above and the dashboard's single-repo force-refresh
---(github_stats.dashboard.actions).
---@param repo string Repository identifier
---@param callback fun(success: string[], errors: table<string, string>)
function M.fetch_repo(repo, callback)
  local metrics = { "clones", "views", "referrers", "paths" }
  local completed = 0
  local success = {}
  local errors = {}

  local function check_complete()
    completed = completed + 1
    if completed == #metrics then
      callback(success, errors)
    end
  end

  for _, metric in ipairs(metrics) do
    api.fetch_metric_async(repo, metric, function(data, err)
      if err or not data then
        errors[repo .. "/" .. metric] = err
      else
        local save_ok, save_err = storage.write_metric(repo, metric, data)
        if save_ok then
          table.insert(success, repo .. "/" .. metric)
        else
          errors[repo .. "/" .. metric] = save_err or "Unknown storage error"
        end
      end
      check_complete()
    end)
  end
end

return M

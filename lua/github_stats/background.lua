---@module 'github_stats.background'
---@brief Silent background fetch/discovery cycle
---@description
--- Owns the plugin's persistent background activity: periodically
--- re-discovering repositories from `watch_users` (if configured) and
--- fetching fresh metrics, entirely silently unless something actually
--- fails. This runs for the whole Neovim session (not just once on
--- startup), so long-running sessions stay up to date without requiring a
--- restart or a manual `:GithubStats fetch`.
---
--- Disabled entirely via `background = { enabled = false }`, in which case
--- the user relies on manual `:GithubStats fetch` only.

local M = {}

---@type uv.uv_timer_t?
local timer = nil

---@internal
---Run one background cycle: discover repos (if configured), then fetch
---@return nil
local function run_cycle()
  local config = require("github_stats.config")
  local fetcher = require("github_stats.fetcher")

  -- Remote mode: the workflow of the data repository fetches; this machine only pulls (and refreshes its digests
  -- when something arrived). Fetching here as well would fetch twice and leave changes in a clone nobody commits.
  local remote = require("github_stats.remote")
  if remote.active() then
    remote.sync(nil, true)
    return
  end

  -- The history is synced between machines, the digest is not: when the other
  -- machine fetched, this one skips its own fetch for the interval and would
  -- never rebuild its digest. So every cycle first checks whether the digest
  -- lags the history (a directory listing per repository, cheap) and rebuilds
  -- it if so. Scheduled and pcall-wrapped: it must not hold up the fetch below.
  vim.schedule(function()
    pcall(function()
      require("github_stats.digest").refresh_if_stale()
    end)
  end)

  local cfg = config.get()
  local watch_users = cfg and cfg.watch_users or {}

  if #watch_users == 0 then
    fetcher.fetch_all(false, nil, { background = true })
    return
  end

  local repo_discovery = require("github_stats.repo_discovery")
  repo_discovery.discover(watch_users, function(repo_names, errors)
    config.set_discovered_repos(repo_names)

    for username, err in pairs(errors) do
      config.notify(string.format("[github-stats] Failed to discover repos for '%s': %s", username, err), "warn")
    end

    fetcher.fetch_all(false, nil, { background = true })
  end)
end

---@internal
---Derive how often to check whether a fetch is due, in milliseconds.
---This does not change how often a fetch actually happens - that's still
---governed by `fetch_interval_hours` inside fetcher.should_fetch(). It only
---controls how promptly a long-running session notices a fetch is due,
---instead of waiting for the next VimEnter.
---How long to wait before the FIRST background cycle, in ms.
---@param cfg GHStats.SetupOptions?
---@return integer
local function initial_delay_ms(cfg)
  local n = cfg and cfg.background and cfg.background.initial_delay_ms
  return (type(n) == "number" and n >= 0) and math.floor(n) or 1000
end

---@param cfg GHStats.SetupOptions?
---@return integer
local function poll_interval_ms(cfg)
  local remote = require("github_stats.remote")
  if remote.active() then
    local s = remote.current() --[[@as GHStats.Storage]]
    return math.floor(s.pull_interval_minutes * 60 * 1000)
  end
  local interval_hours = (cfg and cfg.fetch_interval_hours) or 24
  local minutes = math.min(60, interval_hours * 60)
  return math.floor(minutes * 60 * 1000)
end

---Start the background cycle (idempotent: safe to call more than once)
---@return nil
function M.start()
  if timer then
    return
  end

  local config = require("github_stats.config")
  local cfg = config.get()

  if cfg and cfg.background and cfg.background.enabled == false then
    return
  end

  -- First cycle, deferred to avoid competing with startup. Configurable for
  -- the same reason the recurring interval below already is: how long startup
  -- actually takes is a property of the user's config, not of this plugin --
  -- one second is plenty after a lean start and lands in the middle of a
  -- heavy one.
  vim.defer_fn(run_cycle, initial_delay_ms(cfg))

  -- Recurring cycles for the rest of the session
  timer = vim.uv.new_timer()
  if timer then
    local interval_ms = poll_interval_ms(cfg)
    timer:start(interval_ms, interval_ms, vim.schedule_wrap(run_cycle))
  end
end

---Stop the background cycle, if running (mainly for tests/reload)
---@return nil
function M.stop()
  if timer then
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    timer = nil
  end
end

return M

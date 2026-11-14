---@module 'github_stats'
---@brief GitHub Stats collector for Neovim
---@description
--- Main entry point for GitHub Stats plugin.
--- Automatically fetches repository traffic data once per day.
--- Provides commands for manual fetching and analytics.
---
--- Configuration:
---   Edit ~/.config/nvim/lua/plugins/github-stats/config.json
---
--- Available commands (built via lib.nvim.bindings.usercmd.composer):
---   :GithubStats fetch [force]              - Fetch all metrics
---   :GithubStats show {repo} {metric}       - Show detailed stats
---   :GithubStats summary {clones|views}     - Summary across all repos
---   :GithubStats referrers {repo} [limit]   - Top referrers
---   :GithubStats paths {repo} [limit]       - Top paths
---   :GithubStats chart {repo} {metric}      - Sparkline chart
---   :GithubStats export {repo|all} ...      - Export to CSV/Markdown
---   :GithubStats diff {repo} {metric} ...   - Compare two periods
---   :GithubStats compact [dry-run]          - Archive/prune old data
---   :GithubStats debug                      - Debug configuration
---   :GithubStats[!] dashboard               - Open dashboard (! forces refresh)
---
--- Healthcheck:
---   :checkhealth github_stats
local M = {}

---The options of the last `setup()`, kept for `reload_storage()`.
---@type GHStats.SetupOptions
local last_opts = {}

---Resolve where the history lives (`github_stats.remote`) and load the configuration from there.
---@param opts GHStats.SetupOptions
---@return boolean ok
---@return string|nil err
local function init_storage(opts)
  local config = require("github_stats.config")
  local remote = require("github_stats.remote")

  local storage, storage_err = remote.resolve(opts)
  if storage_err then
    config.notify("[github-stats] " .. storage_err, "warn")
  end
  remote.set_current(storage)

  -- `storage` is not a config option: it decides the paths and is taken out like them.
  local init_opts = {}
  for key, value in pairs(opts) do
    if key ~= "storage" then
      init_opts[key] = value
    end
  end
  if remote.status(storage) == "ready" then
    init_opts.config_dir = storage.dir
    init_opts.data_dir = nil
  end
  return config.init(init_opts)
end

---Setup the plugin
---@param opts? GHStats.SetupOptions Setup options (see |github_stats-configuration|)
function M.setup(opts)
  opts = opts or {}
  last_opts = opts

  -- Initialize configuration
  local config = require("github_stats.config")
  local ok, err = init_storage(opts)
  if not ok then
    config.notify(string.format("[github-stats] Configuration error: %s", err), "error")
    return
  end

  -- Register commands (now modularized)
  local commands = require("github_stats.bindings.usrcmds")
  commands.setup()

  -- Setup auto-fetch on VimEnter (and optional dashboard auto-open)
  local autocmds = require("github_stats.bindings.autocmds")
  autocmds.setup()
end

---Decide the storage again (after the setup guide or a clone changed it) and restart the background cycle on it.
---@return boolean ok
function M.reload_storage()
  local config = require("github_stats.config")
  local background = require("github_stats.background")
  background.stop()
  local ok, err = init_storage(last_opts)
  if not ok then
    config.notify(string.format("[github-stats] Configuration error: %s", err), "error")
    return false
  end
  pcall(function()
    require("github_stats.storage").invalidate()
  end)
  background.start()
  return true
end

-- Expose submodules for advanced usage
M.config = require("github_stats.config")
M.api = require("github_stats.api")
M.storage = require("github_stats.storage")
M.fetcher = require("github_stats.fetcher")
M.analytics = require("github_stats.analytics")
M.dashboard = require("github_stats.dashboard")

return M

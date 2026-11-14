---@module 'github_stats.bindings.autocmds'
---@brief Plugin-lifecycle autocmds
---@description
--- Registers the plugin's global autocmds (startup: starts the background
--- fetch/discovery cycle, optionally auto-opens the dashboard). Buffer-scoped
--- autocmds tied to a dynamically created dashboard buffer/window (e.g.
--- BufWipeout cleanup, VimResized re-render) are kept next to the code that
--- creates that buffer, since they are lifecycle details of that instance
--- rather than global plugin bindings.

local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

---Register the VimEnter handler that starts the background cycle (and
---optionally auto-opens the dashboard)
---@return nil
function M.setup()
  autocmd.create("VimEnter", function()
    -- Start the silent background cycle (no-op if background.enabled ==
    -- false): fetching in local mode, pulling the data repository in remote
    -- mode. Remote mode with a known repository that is not cloned yet (a new
    -- machine with `storage.repo` in its spec) clones it first.
    local background = require("github_stats.background")
    local remote = require("github_stats.remote")
    local storage = remote.current()
    local status = storage and remote.status(storage)
    if storage and status == "clone" then
      remote.clone(storage, function(ok, err)
        local config = require("github_stats.config")
        if ok then
          config.notify(("[github-stats] Cloned the data repository %s"):format(storage.repo), "info")
          require("github_stats").reload_storage()
        else
          config.notify(
            ("[github-stats] Cloning %s failed: %s (fetching locally meanwhile)"):format(storage.repo, err or "?"),
            "warn"
          )
          background.start()
        end
      end)
    else
      background.start()
    end

    -- First start in remote mode without a data repository: the setup guide,
    -- once (its "later" is remembered). Until then the plugin fetches locally.
    local wizard = require("github_stats.remote.wizard")
    if storage and wizard.should_auto_open(storage) then
      vim.defer_fn(function()
        wizard.open({ auto = true })
      end, 1500)
    end

    -- Auto-open dashboard if enabled (independent of fetch completion,
    -- same as before: it shows whatever is already cached and gets
    -- refreshed once the background cycle's data lands)
    vim.defer_fn(function()
      local config = require("github_stats.config")
      local cfg = config.get()
      if cfg and cfg.dashboard and cfg.dashboard.enabled and cfg.dashboard.auto_open then
        local dashboard = require("github_stats.dashboard")
        dashboard.open(false)
      end
    end, 1000)
  end, { group = autocmd.group("GithubStatsAutoFetch", true) })
end

return M

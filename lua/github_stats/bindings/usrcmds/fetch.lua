---@module 'github_stats.bindings.usrcmds.fetch'
---@brief Manual and forced fetch trigger
---@description
--- Handles `:GithubStats fetch` with its optional force parameter.
--- Provides completion for 'force' keyword. When the minimum fetch interval
--- has not elapsed yet, the command asks whether to fetch anyway (UI-05)
--- instead of skipping and telling the user to retype it with `force`.

local fetcher = require("github_stats.fetcher")

local M = {}

local FETCH_ANYWAY = "Fetch anyway"
local KEEP = "Not now"

---Execute fetch command
---@param args table Command arguments from nvim_create_user_command
---@see github_stats.fetcher.manual_fetch
function M.execute(args)
  local remote = require("github_stats.remote")
  if remote.active() then
    M.dispatch_remote()
    return
  end
  local force = args.args == "force"
  local due, info = true, nil
  if not force then
    due, info = fetcher.fetch_due()
  end
  if force or due then
    fetcher.manual_fetch(force)
    return
  end
  local question = info
      and ("Last fetch %.1f h ago, the interval is %g h. Fetch now anyway?"):format(info.since_hours, info.interval_hours)
    or "The fetch interval has not elapsed yet. Fetch now anyway?"
  -- The harmless answer first: the dialog starts on it (`choose`: index 0 is a dismissal, which fetches nothing).
  require("lib.nvim.ui.dialog").choose("[github-stats] " .. question, { KEEP, FETCH_ANYWAY }, 1, function(index)
    if index == 2 then
      fetcher.manual_fetch(true)
    end
  end)
end

---How long after starting the workflow the editor pulls its result (a run takes about a minute).
M.PULL_AFTER_MS = 150000

---Remote mode: start the data repository's workflow, then pull once it has had time to run.
---@return nil
function M.dispatch_remote()
  local config = require("github_stats.config")
  local remote = require("github_stats.remote")
  remote.dispatch(function(ok, err)
    if not ok then
      config.notify(("[github-stats] Starting the workflow failed: %s"):format(err or "?"), "error")
      return
    end
    config.notify(
      ("[github-stats] Workflow started; pulling its result in %d s (:GithubStats sync any time)"):format(M.PULL_AFTER_MS / 1000),
      "info"
    )
    vim.defer_fn(function()
      remote.sync()
    end, M.PULL_AFTER_MS)
  end)
end

---Get completion candidates
---@param arg_lead string Current argument being typed
---@param _cmd_line string Full command line (unused)
---@param _cursor_pos number Cursor position (unused)
---@return string[] # Completion candidates
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, _cmd_line, _cursor_pos)
  if vim.startswith("force", arg_lead) then
    return { "force" }
  end
  return {}
end

return M

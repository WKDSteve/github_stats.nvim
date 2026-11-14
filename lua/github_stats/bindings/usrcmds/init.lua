---@module 'github_stats.bindings.usrcmds'
---@brief User command registration and orchestration
---@description
--- Central registry for all GitHub Stats user commands, built via
--- lib.nvim.bindings.usercmd.composer as a single `:GithubStats <subcommand>` verb.
--- Each execute()/complete() pair below is unchanged from before the
--- migration; routes only reconstruct a compatible `{ args = "..." }` table
--- (the same shape nvim_create_user_command's callback passed) and forward
--- it, so validation/error messages/business logic are untouched.
---
--- Breaking change: the 10 flat `:GithubStatsX` commands are replaced by
--- `:GithubStats x` subcommands (no compat aliases). `:GithubStatsDashboard!`
--- becomes `:GithubStats! dashboard` -- bang now attaches to the verb, not
--- the subcommand (composer only supports one bang slot per command, shared
--- across all subcommands), matching cascade.nvim's precedent.

local composer = require("lib.nvim.bindings.usercmd.composer")

local fetch = require("github_stats.bindings.usrcmds.fetch")
local show = require("github_stats.bindings.usrcmds.show")
local summary = require("github_stats.bindings.usrcmds.summary")
local referrers = require("github_stats.bindings.usrcmds.referrers")
local paths = require("github_stats.bindings.usrcmds.paths")
local debug = require("github_stats.bindings.usrcmds.debug")
local compact = require("github_stats.bindings.usrcmds.compact")
local digest = require("github_stats.bindings.usrcmds.digest")
local chart = require("github_stats.bindings.usrcmds.chart")
local export = require("github_stats.bindings.usrcmds.export")
local diff = require("github_stats.bindings.usrcmds.diff")
local dashboard = require("github_stats.bindings.usrcmds.dashboard")

local M = {}

---@internal
---Rebuild a single space-joined string from bound positionals + leftover
--- tokens, matching the raw `args.args` a flat nargs="+" command would have
--- received -- every execute() below still does its own vim.split on it.
---@param ctx table composer Ctx
---@return string
local function reconstruct(ctx)
  local all = {}
  for _, v in ipairs(ctx.pos) do
    all[#all + 1] = tostring(v)
  end
  for _, v in ipairs(ctx.rest) do
    all[#all + 1] = v
  end
  return table.concat(all, " ")
end

-- Dynamic completion types: config-driven repo lists and date presets can't
-- be static `enum`/`values` snapshots, so each is looked up fresh per call.
composer.register_type("GH_REPO", {
  desc = "Repository as owner/repo, completed from the configured list",
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead)
    local repos = require("github_stats.config").get_repos()
    return vim.tbl_filter(function(r)
      return vim.startswith(r, arg_lead)
    end, repos)
  end,
})

composer.register_type("GH_REPO_OR_ALL", {
  desc = "Repository (owner/repo), or all for every repo (.md/.pdf only)",
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead)
    local options = vim.list_extend({ "all" }, require("github_stats.config").get_repos())
    return vim.tbl_filter(function(o)
      return vim.startswith(o, arg_lead)
    end, options)
  end,
})

-- Shared by show/chart's start_date/end_date slots. Both accept either an
-- ISO date or a preset name; only presets are completable. The original
-- completers additionally suppressed end_date's suggestions once start_date
-- was itself a preset (a preset already implies its own end) -- that
-- cross-slot refinement doesn't fit composer's per-slot completion model,
-- so end_date always offers presets here. Dispatch/validation is unaffected.
composer.register_type("GH_DATE_OR_PRESET", {
  desc = "Date as YYYY-MM-DD, or a preset such as last_week",
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead)
    local presets = require("github_stats.date_presets").list()
    return vim.tbl_filter(function(p)
      return vim.startswith(p, arg_lead)
    end, presets)
  end,
})

composer.register_type("GH_PERIOD", {
  desc = "Period as YYYY-MM (one month) or YYYY (one year)",
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead)
    -- Not the date presets: `parse_period` takes only YYYY-MM or YYYY.
    local now = os.date("*t")
    local current_month = string.format("%04d-%02d", now.year, now.month)
    local last_month_num, last_month_year = now.month - 1, now.year
    if last_month_num < 1 then
      last_month_num, last_month_year = 12, last_month_year - 1
    end
    local last_month = string.format("%04d-%02d", last_month_year, last_month_num)
    local suggestions = { current_month, last_month, tostring(now.year), tostring(now.year - 1) }
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arg_lead)
    end, suggestions)
  end,
})

local METRIC = { "clones", "views" }

-- Texts of the metric values for the option float (the cheatsheet in the command line).
local METRIC_DESC = {
  clones = "Git clones of the repository",
  views = "Page views of the repository",
}
local CHART_METRIC_DESC = vim.tbl_extend("force", METRIC_DESC, {
  both = "Total vs unique count comparison chart",
})
local EXPORT_METRIC_DESC = vim.tbl_extend("force", METRIC_DESC, {
  both = "Clones and views together in one report",
})

---Register all user commands
function M.setup()
  composer.verb("GithubStats", {
    desc = "GitHub traffic stats: fetch, inspect, chart, export, diff",
    bang = true,
    routes = {
      {
        path = { "fetch" },
        args = {
          {
            name = "force",
            type = "STRING",
            optional = true,
            enum = { "force" },
            enum_desc = { force = "Fetch now, ignoring the minimum fetch interval" },
          },
        },
        desc = "Fetch GitHub stats (asks before ignoring the interval; 'force' skips the question)",
        run = function(ctx)
          fetch.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "show" },
        args = {
          { name = "repo", type = "GH_REPO" },
          { name = "metric", type = "STRING", enum = METRIC, enum_desc = METRIC_DESC },
          {
            name = "start_date",
            type = "GH_DATE_OR_PRESET",
            optional = true,
            desc = "First day as YYYY-MM-DD, or a preset (sets both ends)",
          },
          {
            name = "end_date",
            type = "GH_DATE_OR_PRESET",
            optional = true,
            desc = "Last day as YYYY-MM-DD (ignored after a preset)",
          },
        },
        desc = "Show stats for repo/metric: {repo} {metric} [start] [end]",
        run = function(ctx)
          show.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "summary" },
        args = { { name = "metric", type = "STRING", enum = METRIC, enum_desc = METRIC_DESC } },
        desc = "Show summary across all repos: {clones|views}",
        run = function(ctx)
          summary.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "referrers" },
        args = {
          { name = "repo", type = "GH_REPO" },
          { name = "limit", type = "STRING", optional = true, desc = "How many referrers to list (default: 10)" },
        },
        desc = "Show top referrers: {repo} [limit]",
        run = function(ctx)
          referrers.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "paths" },
        args = {
          { name = "repo", type = "GH_REPO" },
          { name = "limit", type = "STRING", optional = true, desc = "How many paths to list (default: 10)" },
        },
        desc = "Show top paths: {repo} [limit]",
        run = function(ctx)
          paths.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "chart" },
        args = {
          { name = "repo", type = "GH_REPO" },
          {
            name = "metric",
            type = "STRING",
            enum = { "clones", "views", "both" },
            enum_desc = CHART_METRIC_DESC,
          },
          {
            name = "arg3",
            type = "GH_DATE_OR_PRESET",
            optional = true,
            desc = "Start date, or a range alone: 30d, 6m, 1y, a preset or all",
          },
          {
            name = "arg4",
            type = "GH_DATE_OR_PRESET",
            optional = true,
            desc = "End date YYYY-MM-DD (the start must then be a date too)",
          },
        },
        desc = "Show sparkline chart: {repo} {clones|views|both} [start|range] [end]",
        run = function(ctx)
          chart.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "export" },
        args = {
          { name = "target", type = "GH_REPO_OR_ALL" },
          {
            name = "metric",
            type = "STRING",
            enum = { "clones", "views", "both" },
            enum_desc = EXPORT_METRIC_DESC,
          },
          {
            name = "filepath",
            type = "PATH",
            desc = "Output file; .csv, .md or .pdf decides the format",
          },
        },
        desc = "Export to CSV/Markdown: {repo|all} {clones|views|both} {filepath}",
        run = function(ctx)
          export.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "diff" },
        args = {
          { name = "repo", type = "GH_REPO" },
          { name = "metric", type = "STRING", enum = METRIC, enum_desc = METRIC_DESC },
          { name = "period1", type = "GH_PERIOD", desc = "First period, the baseline (YYYY-MM or YYYY)" },
          {
            name = "period2",
            type = "GH_PERIOD",
            desc = "Second period; the change is shown relative to the first",
          },
        },
        desc = "Compare periods: {repo} {metric} {YYYY-MM} {YYYY-MM}",
        run = function(ctx)
          diff.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "compact" },
        args = {
          {
            name = "mode",
            type = "STRING",
            optional = true,
            enum = { "dry-run" },
            enum_desc = { ["dry-run"] = "Only report what would be archived and removed" },
          },
        },
        desc = "Archive old clones/views data and prune stale referrers/paths snapshots (use 'dry-run' to preview)",
        run = function(ctx)
          compact.execute({ args = reconstruct(ctx) })
        end,
      },

      {
        path = { "digest" },
        desc = "Rebuild the per-repository digest other programs read (after a sync, the local one may lag)",
        run = function()
          digest.execute({})
        end,
      },

      {
        path = { "setup" },
        desc = "Guide: where the history lives (data repository filled by GitHub Actions, or local) and what it needs",
        run = function()
          require("github_stats.remote.wizard").open()
        end,
      },

      {
        path = { "sync" },
        desc = "Remote mode: push a changed config.json, pull the data repository now",
        run = function()
          require("github_stats.remote").sync()
        end,
      },

      {
        path = { "debug" },
        desc = "Debug configuration and test API connection",
        run = function()
          debug.execute({})
        end,
      },

      {
        path = { "dashboard" },
        desc = "Open GitHub Stats Dashboard (use :GithubStats! dashboard to force refresh)",
        run = function(ctx)
          dashboard.execute({ bang = ctx.bang })
        end,
      },
    },
  })
end

return M

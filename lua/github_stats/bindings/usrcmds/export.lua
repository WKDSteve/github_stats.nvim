---@module 'github_stats.bindings.usrcmds.export'
---@brief Export data to CSV, Markdown or PDF
---@description
--- Exports traffic statistics to various file formats. PDF export goes
--- through pdfport.nvim (optional dependency, soft-required); the report
--- content is identical to the Markdown export, just handed to pdfport as
--- text instead of written to a .md file first.

local config = require("github_stats.config")
local analytics = require("github_stats.analytics")
local export = require("github_stats.export")
-- Not vim.fn.expand(): filepath is user/buffer text, see export.lua's own
-- `local expand = require("lib.nvim.cross.fs.expand_path")` for why (SEC-34).
local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

local str_format = string.format

---@internal
---Resolve the export format from filepath's extension. A path with no
---extension at all gets a sensible default appended (markdown for the "all"
---target, since it's the only format supported there; CSV otherwise) rather
---than erroring -- previously `:GithubStats export all clones report` failed
---outright with "File must have .csv or .md extension" for missing an
---extension it could have just filled in. A path that DOES have some other
---extension (e.g. `.txt`) is left alone; the caller still reports the
---standard error for that case, since silently bolting `.csv` onto a path
---the user clearly named on purpose would be more surprising than helpful.
---@param filepath string Requested output path
---@param target string Export target ("all" or a repo)
---@return string?, string, string? # format ("csv"|"markdown"|"pdf", nil if unresolvable), resolved filepath, notice message if a default was applied
local function resolve_format(filepath, target)
  if filepath:match("%.csv$") then
    return "csv", filepath, nil
  end
  if filepath:match("%.md$") then
    return "markdown", filepath, nil
  end
  if filepath:match("%.pdf$") then
    return "pdf", filepath, nil
  end

  local basename = vim.fn.fnamemodify(filepath, ":t")
  if basename:match("%.") then
    return nil, filepath, nil
  end

  local default_ext = (target == "all") and ".md" or ".csv"
  local default_format = (target == "all") and "markdown" or "csv"
  return default_format, filepath .. default_ext, str_format("No extension given, defaulting to '%s'", default_ext)
end

---Run the writer for `format` and report through the shared `report`.
---The csv/markdown writers are synchronous and return `ok, err`; the pdf writer
---(pdfport.nvim, optional) is asynchronous and calls the callback it is given.
---@param format string "csv"|"markdown"|"pdf"
---@param report fun(ok: boolean, err: string?)
---@param writers table<string, function>
local function write_as(format, report, writers)
  local writer = writers[format]
  if format == "pdf" then
    writer(report)
  else
    report(writer())
  end
end

---Execute export command
---@param args table Command arguments
---@see github_stats.export
function M.execute(args)
  local parts = vim.split(args.args, "%s+")

  if #parts < 3 then
    config.notify("[github-stats] Usage: :GithubStats export {repo|all} {clones|views|both} {filepath}", "error")
    return
  end

  local target = parts[1]
  local metric = parts[2]
  local filepath = parts[3]

  -- Validate metric
  if metric ~= "clones" and metric ~= "views" and metric ~= "both" then
    config.notify("[github-stats] Metric must be 'clones', 'views', or 'both'", "error")
    return
  end

  -- Determine format from extension, defaulting when none was given
  local format, resolved_path, notice = resolve_format(filepath, target)
  if not format then
    config.notify("[github-stats] File must have .csv, .md or .pdf extension", "error")
    return
  end
  filepath = resolved_path
  if notice then
    config.notify(str_format("[github-stats] %s", notice), "info")
  end

  -- PDF goes through pdfport.nvim (optional dependency) and is async, unlike
  -- the synchronous csv/markdown writers below -- reported via the same
  -- ok/err shape through a callback instead of a direct return value.
  ---@param ok boolean
  ---@param export_err string?
  local function report(ok, export_err)
    if ok then
      config.notify(str_format("[github-stats] Exported to: %s", expand_path(filepath)), "info")
    else
      config.notify(str_format("[github-stats] Export failed: %s", export_err), "error")
    end
  end

  -- Export all repos
  if target == "all" then
    if format == "csv" then
      config.notify("[github-stats] 'all' target only supports Markdown/PDF format", "error")
      return
    end

    if metric == "both" then
      local clones_results, clones_err = analytics.query_all_repos("clones", nil, nil)
      local views_results, views_err = analytics.query_all_repos("views", nil, nil)

      if clones_err and views_err then
        config.notify(str_format("[github-stats] Error: %s", clones_err), "error")
        return
      end

      write_as(format, report, {
        markdown = function()
          return export.export_combined_summary_markdown(clones_results, views_results, filepath)
        end,
        pdf = function(done)
          export.export_combined_summary_markdown_pdf(clones_results, views_results, filepath, done)
        end,
      })

      return
    end

    local results, err = analytics.query_all_repos(metric, nil, nil)
    if err then
      config.notify(str_format("[github-stats] Error: %s", err), "error")
      return
    end

    write_as(format, report, {
      markdown = function()
        return export.export_summary_markdown(metric, results, filepath)
      end,
      pdf = function(done)
        export.export_summary_markdown_pdf(metric, results, filepath, done)
      end,
    })

    return
  end

  -- Export single repo, combined clones+views
  if metric == "both" then
    local clones_stats, clones_err = analytics.query_metric({ repo = target, metric = "clones" })
    local views_stats, views_err = analytics.query_metric({ repo = target, metric = "views" })

    if clones_err and views_err then
      config.notify(str_format("[github-stats] Error: %s", clones_err or views_err), "error")
      return
    end

    write_as(format, report, {
      csv = function()
        return export.export_combined_csv(
          target,
          clones_stats and clones_stats.daily_breakdown or {},
          views_stats and views_stats.daily_breakdown or {},
          filepath
        )
      end,
      markdown = function()
        return export.export_combined_markdown(target, clones_stats, views_stats, filepath)
      end,
      pdf = function(done)
        export.export_combined_markdown_pdf(target, clones_stats, views_stats, filepath, done)
      end,
    })

    return
  end

  -- Export single repo, single metric
  local stats, err = analytics.query_metric({
    repo = target,
    metric = metric,
  })

  if err or not stats then
    config.notify(str_format("[github-stats] Error: %s", err or "No data"), "error")
    return
  end

  write_as(format, report, {
    csv = function()
      return export.export_daily_csv(target, metric, stats.daily_breakdown, filepath)
    end,
    markdown = function()
      return export.export_markdown(target, metric, stats, filepath)
    end,
    pdf = function(done)
      export.export_markdown_pdf(target, metric, stats, filepath, done)
    end,
  })
end

---Get completion candidates
---@param arg_lead string Current argument
---@param cmd_line string Full command line
---@param _cursor_pos number Cursor position
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.complete(arg_lead, cmd_line, _cursor_pos)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  local arg_index = #parts

  if cmd_line:match("%s$") then
    arg_index = arg_index + 1
  end

  -- First argument: repository or "all"
  if arg_index == 2 then
    local options = vim.list_extend({ "all" }, config.get_repos())
    return vim.tbl_filter(function(opt)
      return vim.startswith(opt, arg_lead)
    end, options)
  end

  -- Second argument: metric
  if arg_index == 3 then
    local metrics = { "clones", "views", "both" }
    return vim.tbl_filter(function(metric)
      return vim.startswith(metric, arg_lead)
    end, metrics)
  end

  -- Third argument: filepath (use built-in file completion)
  if arg_index == 4 then
    return vim.fn.getcompletion(arg_lead, "file")
  end

  return {}
end

return M

---@diagnostic disable: undefined-global

-- Specs for the whole github_stats.bindings.usrcmds layer: each subcommand's
-- execute()/complete() pair plus the composer verb they are wired into.
--
-- Every collaborator that would leave the process (the API client, the
-- fetcher) or open a window (usrcmds.utils' float) is replaced in
-- package.loaded *before* the command modules are required -- they capture
-- those modules in upvalues at load time. What stays real: the config module,
-- the argument parsing and validation in each execute(), the completion
-- arithmetic, and the composer registration itself.

describe("usrcmds", function()
  local config
  local tmp_dir
  local notices, floats
  local saved = {}
  local calls
  local scratch_buf

  ---@type table<string, any>
  local MODULES = {}

  ---@param kind string
  ---@return boolean
  local function notified(kind)
    for _, entry in ipairs(notices) do
      if entry.message:find(kind, 1, true) then
        return true
      end
    end
    return false
  end

  ---Replace `name` in package.loaded, remembering the previous value.
  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  before_each(function()
    calls = { fetch = {}, export = {}, retention = {}, api = {}, dashboard = {}, diff = {} }
    notices, floats = {}, {}
    saved = {}
    scratch_buf = vim.api.nvim_create_buf(false, true)

    -- The command modules capture these at require time, so they have to be
    -- in place before the requires below.
    stub("github_stats.bindings.usrcmds.utils", {
      show_float = function(lines, title)
        floats[#floats + 1] = { lines = lines, title = title }
        return scratch_buf, nil
      end,
      format_number = function(n)
        return tostring(n)
      end,
      split_lines = function(s)
        return vim.split(s, "\n", { plain = true })
      end,
    })

    stub("github_stats.fetcher", {
      manual_fetch = function(force)
        calls.fetch[#calls.fetch + 1] = force
      end,
      fetch_due = function()
        return true, nil
      end,
      last_fetch_summary = nil,
    })

    stub("github_stats.api", {
      fetch_metric_async = function(repo, metric, cb)
        calls.api[#calls.api + 1] = { repo = repo, metric = metric }
        cb({ count = 1 }, nil)
      end,
    })

    stub("github_stats.dashboard", {
      open = function(force)
        calls.dashboard[#calls.dashboard + 1] = force
      end,
    })

    -- chart.execute() resolves date/preset/range arguments itself before
    -- calling query_metric (ERR-10), so parse_time_range must stay the real
    -- implementation rather than a mock -- it is what turns "14d" or
    -- "this_month" into concrete dates.
    local real_parse_time_range = require("github_stats.analytics").parse_time_range
    stub("github_stats.analytics", {
      query_metric = function(query)
        return MODULES.query_metric(query)
      end,
      query_all_repos = function(metric, s, e)
        return MODULES.query_all_repos(metric, s, e)
      end,
      get_top_referrers = function(repo, limit)
        return MODULES.get_top_referrers(repo, limit)
      end,
      get_top_paths = function(repo, limit)
        return MODULES.get_top_paths(repo, limit)
      end,
      parse_time_range = real_parse_time_range,
    })

    stub("github_stats.diff", {
      compare_periods = function(repo, metric, p1, p2)
        calls.diff[#calls.diff + 1] = { repo, metric, p1, p2 }
        return MODULES.compare_periods(repo, metric, p1, p2)
      end,
      format_comparison = function()
        return { "comparison line" }
      end,
    })

    stub("github_stats.retention", {
      run_all = function(opts)
        calls.retention[#calls.retention + 1] = opts
        return MODULES.retention_summary()
      end,
      format_bytes = function(bytes)
        return string.format("%dB", bytes)
      end,
    })

    local function record_export(name)
      return function(...)
        local args = { ... }
        calls.export[#calls.export + 1] = { name = name, args = args }
        -- The *_pdf variants report through a callback instead of returning.
        if name:match("_pdf$") then
          args[#args](true, nil)
          return
        end
        return true, nil
      end
    end
    stub("github_stats.export", {
      export_daily_csv = record_export("export_daily_csv"),
      export_combined_csv = record_export("export_combined_csv"),
      export_markdown = record_export("export_markdown"),
      export_markdown_pdf = record_export("export_markdown_pdf"),
      export_combined_markdown = record_export("export_combined_markdown"),
      export_combined_markdown_pdf = record_export("export_combined_markdown_pdf"),
      export_summary_markdown = record_export("export_summary_markdown"),
      export_summary_markdown_pdf = record_export("export_summary_markdown_pdf"),
      export_combined_summary_markdown = record_export("export_combined_summary_markdown"),
      export_combined_summary_markdown_pdf = record_export("export_combined_summary_markdown_pdf"),
    })

    -- Default scripted answers; individual tests override these.
    MODULES.query_metric = function(query)
      return {
        repo = query.repo,
        metric = query.metric,
        period_start = "2026-03-01",
        period_end = "2026-03-02",
        total_count = 12,
        total_uniques = 5,
        daily_breakdown = {
          ["2026-03-01"] = { count = 4, uniques = 2 },
          ["2026-03-02"] = { count = 8, uniques = 3 },
        },
      },
        nil
    end
    MODULES.query_all_repos = function()
      return {
        ["user/a"] = {
          period_start = "2026-03-01",
          period_end = "2026-03-02",
          total_count = 12,
          total_uniques = 5,
          daily_breakdown = {},
        },
      },
        nil
    end
    MODULES.get_top_referrers = function()
      return { { referrer = "github.com", count = 10, uniques = 4 } }, nil
    end
    MODULES.get_top_paths = function()
      return { { path = "/", title = "Home", count = 10, uniques = 4 } }, nil
    end
    MODULES.compare_periods = function()
      return { repo = "user/a" }, nil
    end
    MODULES.retention_summary = function()
      return { archived = 2, compacted_deleted = 3, pruned_deleted = 1, freed_bytes = 4096, errors = {} }
    end

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.date_presets",
      "github_stats.bindings.usrcmds",
      "github_stats.bindings.usrcmds.fetch",
      "github_stats.bindings.usrcmds.show",
      "github_stats.bindings.usrcmds.summary",
      "github_stats.bindings.usrcmds.referrers",
      "github_stats.bindings.usrcmds.paths",
      "github_stats.bindings.usrcmds.debug",
      "github_stats.bindings.usrcmds.compact",
      "github_stats.bindings.usrcmds.chart",
      "github_stats.bindings.usrcmds.export",
      "github_stats.bindings.usrcmds.diff",
      "github_stats.bindings.usrcmds.dashboard",
    }) do
      if saved[name] == nil then
        saved[name] = { package.loaded[name] }
      end
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "user/alpha", "user/beta" } })
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end
  end)

  after_each(function()
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
    package.loaded["github_stats.config"] = nil
    if scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf) then
      vim.api.nvim_buf_delete(scratch_buf, { force = true })
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("fetch", function()
    it("passes 'force' through and nothing else", function()
      local fetch = require("github_stats.bindings.usrcmds.fetch")

      fetch.execute({ args = "force" })
      fetch.execute({ args = "" })
      fetch.execute({ args = "forc" })

      assert.same({ true, false, false }, calls.fetch)
    end)

    it("asks instead of skipping when the interval has not elapsed (UI-05)", function()
      local asked = {}
      local answer
      stub("lib.nvim.ui.dialog", {
        choose = function(question, choices, default, cb)
          asked[#asked + 1] = { question = question, choices = choices, default = default }
          cb(answer)
        end,
      })
      package.loaded["github_stats.fetcher"].fetch_due = function()
        return false, { since_hours = 2, interval_hours = 24 }
      end
      local fetch = require("github_stats.bindings.usrcmds.fetch")

      answer = 1 -- "Not now"
      fetch.execute({ args = "" })
      assert.equals(1, #asked)
      assert.equals(1, asked[1].default, "the harmless answer is focused")
      assert.truthy(asked[1].question:find("Last fetch 2.0 h ago, the interval is 24 h", 1, true))
      assert.equals("Not now", asked[1].choices[1])
      assert.same({}, calls.fetch)

      answer = 2 -- "Fetch anyway"
      fetch.execute({ args = "" })
      assert.same({ true }, calls.fetch)

      answer = 0 -- dismissed
      fetch.execute({ args = "" })
      assert.same({ true }, calls.fetch)

      fetch.execute({ args = "force" })
      assert.equals(3, #asked)
      assert.same({ true, true }, calls.fetch)
    end)

    it("fetches nothing until a late answer, and only on 'Fetch anyway' (UI-05)", function()
      local pending = {}
      stub("lib.nvim.ui.dialog", {
        choose = function(_, _, _, cb)
          pending[#pending + 1] = cb
        end,
      })
      package.loaded["github_stats.fetcher"].fetch_due = function()
        return false, { since_hours = 2, interval_hours = 24 }
      end
      local fetch = require("github_stats.bindings.usrcmds.fetch")
      local before = #calls.fetch

      fetch.execute({ args = "" })
      fetch.execute({ args = "" })
      assert.equals(before, #calls.fetch, "nothing is fetched while the question is open")
      pending[1](1)
      assert.equals(before, #calls.fetch, "a late 'Not now' fetches nothing")
      pending[2](2)
      assert.equals(before + 1, #calls.fetch, "a late 'Fetch anyway' fetches once")
    end)

    it("completes the force keyword only while it still matches", function()
      local fetch = require("github_stats.bindings.usrcmds.fetch")

      assert.same({ "force" }, fetch.complete("", "", 0))
      assert.same({ "force" }, fetch.complete("fo", "", 0))
      assert.same({}, fetch.complete("x", "", 0))
    end)
  end)

  describe("show", function()
    local show
    before_each(function()
      show = require("github_stats.bindings.usrcmds.show")
    end)

    it("insists on a repo and a metric", function()
      show.execute({ args = "user/alpha" })

      assert.equals(0, #floats)
      assert.is_true(notified("Usage: :GithubStats show"))
    end)

    it("rejects a metric that is neither clones nor views", function()
      show.execute({ args = "user/alpha stars" })

      assert.equals(0, #floats)
      assert.is_true(notified("Invalid metric 'stars'"))
    end)

    it("reports an analytics error", function()
      MODULES.query_metric = function()
        return nil, "storage exploded"
      end

      show.execute({ args = "user/alpha clones" })

      assert.is_true(notified("Error: storage exploded"))
    end)

    it("warns rather than showing an empty report", function()
      MODULES.query_metric = function(query)
        return {
          repo = query.repo,
          metric = query.metric,
          period_start = "N/A",
          period_end = "N/A",
          total_count = 0,
          total_uniques = 0,
          daily_breakdown = {},
        },
          nil
      end

      show.execute({ args = "user/alpha clones" })

      assert.equals(0, #floats)
      assert.is_true(notified("No data found for user/alpha/clones"))
    end)

    it("renders the report and binds <BS> back to the dashboard", function()
      show.execute({ args = "user/alpha clones 2026-03-01 2026-03-02" })

      assert.equals(1, #floats)
      assert.equals("GitHub Stats: user/alpha/clones", floats[1].title)

      local text = table.concat(floats[1].lines, "\n")
      assert.is_truthy(text:find("Repository: user/alpha", 1, true))
      assert.is_truthy(text:find("Period: 2026-03-01 to 2026-03-02", 1, true))
      assert.is_truthy(text:find("Daily Breakdown:", 1, true))

      local maps = vim.api.nvim_buf_get_keymap(scratch_buf, "n")
      local has_bs = false
      for _, m in ipairs(maps) do
        if m.lhs == "<BS>" then
          has_bs = true
        end
      end
      assert.is_true(has_bs)
    end)

    -- ERR-10: a typo'd ISO date or an unrecognized preset must error out
    -- rather than silently becoming "no filter" -- the old code handed
    -- start_date/end_date straight to analytics.query_metric, where a
    -- non-ISO value fails parse_date and the filter is dropped with no
    -- signal, even though the command's own completion (M.complete above)
    -- suggests preset names for that exact slot.
    it("rejects a start_date that is neither ISO nor a known preset", function()
      local seen_query = false
      MODULES.query_metric = function()
        seen_query = true
        return { daily_breakdown = {} }, nil
      end

      show.execute({ args = "user/alpha clones 2026-o1-01" })

      assert.is_false(seen_query)
      assert.is_true(notified("Invalid start_date '2026-o1-01'"))
    end)

    it("resolves a preset start_date into concrete dates", function()
      local seen
      local real_query_metric = MODULES.query_metric
      MODULES.query_metric = function(query)
        seen = query
        return real_query_metric(query)
      end

      show.execute({ args = "user/alpha clones today" })

      assert.is_string(seen.start_date)
      assert.equals(seen.start_date, seen.end_date)
    end)

    -- M.complete() is a leftover from the pre-composer flat `:GithubStatsShow`
    -- command: nothing in this repo calls it any more (the `:GithubStats show`
    -- verb completes through composer's registered GH_REPO/GH_DATE_OR_PRESET
    -- types instead), and its slot arithmetic still counts from a command line
    -- whose first token IS the whole command. Pinned in that shape, since it
    -- is still reachable as public API.
    it("completes repo, metric and date slots by position", function()
      assert.same({ "user/alpha", "user/beta" }, show.complete("", "GithubStatsShow ", 0))
      assert.same({ "user/alpha" }, show.complete("user/a", "GithubStatsShow user/a", 0))
      assert.same({ "clones", "views" }, show.complete("", "GithubStatsShow user/alpha ", 0))
      assert.same({ "views" }, show.complete("v", "GithubStatsShow user/alpha v", 0))

      local presets = show.complete("to", "GithubStatsShow user/alpha clones to", 0)
      assert.same({ "today" }, presets)
    end)

    it("offers no end_date once the start slot already holds a preset", function()
      assert.same({}, show.complete("", "GithubStatsShow user/alpha clones today ", 0))
      assert.is_true(#show.complete("", "GithubStatsShow user/alpha clones 2026-03-01 ", 0) > 0)
    end)

    it("offers nothing past the last slot", function()
      assert.same({}, show.complete("", "GithubStatsShow a b c d e ", 0))
    end)
  end)

  describe("summary", function()
    local summary
    before_each(function()
      summary = require("github_stats.bindings.usrcmds.summary")
    end)

    it("insists on clones or views", function()
      summary.execute({ args = "stars" })

      assert.equals(0, #floats)
      assert.is_true(notified("Metric must be 'clones' or 'views'"))
    end)

    it("reports 'no data' rather than an empty float", function()
      MODULES.query_all_repos = function()
        return {}, nil
      end

      summary.execute({ args = "clones" })

      assert.equals(0, #floats)
      assert.is_true(notified("No data available"))
    end)

    it("warns about partial errors but still shows what it has", function()
      MODULES.query_all_repos = function()
        return { ["user/a"] = { period_start = "x", period_end = "y", total_count = 1, total_uniques = 1 } }, "Errors: something"
      end

      summary.execute({ args = "views" })

      assert.is_true(notified("Errors occurred"))
      assert.equals(1, #floats)
    end)

    it("lists one block per repository", function()
      summary.execute({ args = "clones" })

      local text = table.concat(floats[1].lines, "\n")
      assert.equals("GitHub Stats Summary: clones", floats[1].title)
      assert.is_truthy(text:find("Repository: user/a", 1, true))
      assert.is_truthy(text:find("Total Count: 12", 1, true))
    end)

    it("completes the metric", function()
      assert.same({ "clones", "views" }, summary.complete("", "", 0))
      assert.same({ "clones" }, summary.complete("c", "", 0))
    end)
  end)

  describe("referrers and paths", function()
    it("reports an analytics error", function()
      MODULES.get_top_referrers = function()
        return {}, "unreadable"
      end

      require("github_stats.bindings.usrcmds.referrers").execute({ args = "user/alpha" })

      assert.is_true(notified("Error: unreadable"))
    end)

    it("says so when there is no referrer data", function()
      MODULES.get_top_referrers = function()
        return {}, nil
      end

      require("github_stats.bindings.usrcmds.referrers").execute({ args = "user/alpha" })

      assert.equals(0, #floats)
      assert.is_true(notified("No referrer data available"))
    end)

    it("numbers the referrer list and passes the limit through", function()
      local seen_limit
      MODULES.get_top_referrers = function(_, limit)
        seen_limit = limit
        return { { referrer = "github.com", count = 10, uniques = 4 } }, nil
      end

      require("github_stats.bindings.usrcmds.referrers").execute({ args = "user/alpha 3" })

      assert.equals(3, seen_limit)
      assert.equals("Top Referrers: user/alpha", floats[1].title)
      assert.is_truthy(table.concat(floats[1].lines, "\n"):find(" 1. github.com", 1, true))
    end)

    it("defaults the limit to ten when it is missing or unparsable", function()
      local seen = {}
      MODULES.get_top_referrers = function(_, limit)
        seen[#seen + 1] = limit
        return { { referrer = "a", count = 1, uniques = 1 } }, nil
      end

      local referrers = require("github_stats.bindings.usrcmds.referrers")
      referrers.execute({ args = "user/alpha" })
      referrers.execute({ args = "user/alpha lots" })

      assert.same({ 10, 10 }, seen)
    end)

    it("says so when there is no path data, and lists titles when there is", function()
      MODULES.get_top_paths = function()
        return {}, nil
      end
      local paths = require("github_stats.bindings.usrcmds.paths")
      paths.execute({ args = "user/alpha" })
      assert.is_true(notified("No path data available"))

      MODULES.get_top_paths = function()
        return { { path = "/docs", title = "Docs", count = 4, uniques = 2 } }, nil
      end
      paths.execute({ args = "user/alpha" })

      local text = table.concat(floats[1].lines, "\n")
      assert.is_truthy(text:find("Title: Docs", 1, true))
    end)

    it("completes the repository in the first slot only", function()
      local referrers = require("github_stats.bindings.usrcmds.referrers")
      local paths = require("github_stats.bindings.usrcmds.paths")

      -- Legacy flat-command line shape; see the note on show.complete above.
      assert.same({ "user/alpha", "user/beta" }, referrers.complete("", "GithubStatsReferrers ", 0))
      assert.same({}, referrers.complete("", "GithubStatsReferrers user/alpha ", 0))
      assert.same({ "user/beta" }, paths.complete("user/b", "GithubStatsPaths user/b", 0))
      assert.same({}, paths.complete("", "GithubStatsPaths user/alpha ", 0))
    end)
  end)

  describe("chart", function()
    local chart
    before_each(function()
      chart = require("github_stats.bindings.usrcmds.chart")
    end)

    it("insists on a repo and a metric", function()
      chart.execute({ args = "user/alpha" })

      assert.is_true(notified("Usage: :GithubStats chart"))
    end)

    it("rejects an unknown metric", function()
      chart.execute({ args = "user/alpha stars" })

      assert.is_true(notified("Metric must be 'clones', 'views', or 'both'"))
    end)

    it("draws a single-metric sparkline chart", function()
      chart.execute({ args = "user/alpha clones" })

      assert.equals("Chart: user/alpha/clones", floats[1].title)
      assert.equals("GitHub Stats: user/alpha/clones", floats[1].lines[1])
    end)

    it("draws a comparison chart for 'both'", function()
      chart.execute({ args = "user/alpha both" })

      assert.equals("Chart: user/alpha", floats[1].title)
      assert.is_truthy(table.concat(floats[1].lines, "\n"):find("Count (Total):", 1, true))
    end)

    it("resolves a lone third argument that looks like a time range into concrete dates", function()
      local seen
      MODULES.query_metric = function(query)
        seen = query
        return { daily_breakdown = {} }, nil
      end

      chart.execute({ args = "user/alpha clones 14d" })
      assert.is_nil(seen.time_range)
      assert.is_string(seen.start_date)
      assert.is_string(seen.end_date)

      seen = nil
      chart.execute({ args = "user/alpha clones last_week" })
      assert.is_string(seen.start_date)
      assert.is_string(seen.end_date)
    end)

    it("reads it as a start date otherwise, with the fourth as the end", function()
      local seen
      MODULES.query_metric = function(query)
        seen = query
        return { daily_breakdown = {} }, nil
      end

      chart.execute({ args = "user/alpha clones 2026-03-01 2026-03-09" })

      assert.equals("2026-03-01", seen.start_date)
      assert.equals("2026-03-09", seen.end_date)
      assert.is_nil(seen.time_range)
    end)

    -- ERR-10: a typo'd date or an unrecognized preset must error out rather
    -- than silently becoming "no filter" (the old `arg3:match("last")`
    -- heuristic let this fall through to start_date, where parse_date
    -- rejects it and drops the filter with no signal).
    it("rejects a third argument that is neither a date, range nor known preset", function()
      local seen_query = false
      MODULES.query_metric = function()
        seen_query = true
        return { daily_breakdown = {} }, nil
      end

      chart.execute({ args = "user/alpha clones not-a-real-range" })

      assert.is_false(seen_query)
      assert.is_true(notified("Invalid date/range/preset 'not-a-real-range'"))
    end)

    it("rejects a typo'd ISO date given alongside an end date", function()
      local seen_query = false
      MODULES.query_metric = function()
        seen_query = true
        return { daily_breakdown = {} }, nil
      end

      chart.execute({ args = "user/alpha clones 2026-o1-01 2026-02-01" })

      assert.is_false(seen_query)
      assert.is_true(notified("Invalid start_date '2026-o1-01'"))
    end)

    it("reports a query error", function()
      MODULES.query_metric = function()
        return nil, "nope"
      end

      chart.execute({ args = "user/alpha clones" })
      assert.is_true(notified("Error: nope"))

      chart.execute({ args = "user/alpha both" })
      assert.is_true(notified("Error: nope"))
    end)

    it("completes repo, metric and preset slots", function()
      -- Legacy flat-command line shape; see the note on show.complete above.
      assert.same({ "user/alpha", "user/beta" }, chart.complete("", "GithubStatsChart ", 0))
      assert.same({ "clones", "views", "both" }, chart.complete("", "GithubStatsChart user/alpha ", 0))
      assert.same({ "today" }, chart.complete("to", "GithubStatsChart user/alpha both to", 0))
      assert.same({}, chart.complete("", "GithubStatsChart user/alpha both today ", 0))
      assert.same({}, chart.complete("", "GithubStatsChart a b c d e ", 0))
    end)
  end)

  describe("export", function()
    local export_cmd
    before_each(function()
      export_cmd = require("github_stats.bindings.usrcmds.export")
    end)

    ---@return string name of the export function that was called
    local function last_export()
      return calls.export[#calls.export].name
    end

    it("insists on all three arguments", function()
      export_cmd.execute({ args = "user/alpha clones" })

      assert.equals(0, #calls.export)
      assert.is_true(notified("Usage: :GithubStats export"))
    end)

    it("rejects an unknown metric", function()
      export_cmd.execute({ args = "user/alpha stars out.csv" })

      assert.is_true(notified("Metric must be 'clones', 'views', or 'both'"))
    end)

    it("resolves the format from the extension", function()
      export_cmd.execute({ args = "user/alpha clones out.csv" })
      assert.equals("export_daily_csv", last_export())

      export_cmd.execute({ args = "user/alpha clones out.md" })
      assert.equals("export_markdown", last_export())

      export_cmd.execute({ args = "user/alpha clones out.pdf" })
      assert.equals("export_markdown_pdf", last_export())
    end)

    it("appends a default extension when none was given", function()
      export_cmd.execute({ args = "user/alpha clones report" })

      assert.equals("export_daily_csv", last_export())
      assert.equals("report.csv", calls.export[1].args[4])
      assert.is_true(notified("No extension given, defaulting to '.csv'"))
    end)

    it("defaults the 'all' target to Markdown instead", function()
      export_cmd.execute({ args = "all clones report" })

      assert.equals("export_summary_markdown", last_export())
      assert.equals("report.md", calls.export[1].args[3])
      assert.is_true(notified("defaulting to '.md'"))
    end)

    it("refuses a path that names some other extension", function()
      export_cmd.execute({ args = "user/alpha clones notes.txt" })

      assert.equals(0, #calls.export)
      assert.is_true(notified("File must have .csv, .md or .pdf extension"))
    end)

    it("refuses CSV for the 'all' target", function()
      export_cmd.execute({ args = "all clones out.csv" })

      assert.equals(0, #calls.export)
      assert.is_true(notified("'all' target only supports Markdown/PDF format"))
    end)

    it("routes 'all both' to the combined summary writers", function()
      export_cmd.execute({ args = "all both out.md" })
      assert.equals("export_combined_summary_markdown", last_export())

      export_cmd.execute({ args = "all both out.pdf" })
      assert.equals("export_combined_summary_markdown_pdf", last_export())
    end)

    it("routes a single repo with 'both' by format", function()
      export_cmd.execute({ args = "user/alpha both out.csv" })
      assert.equals("export_combined_csv", last_export())

      export_cmd.execute({ args = "user/alpha both out.md" })
      assert.equals("export_combined_markdown", last_export())

      export_cmd.execute({ args = "user/alpha both out.pdf" })
      assert.equals("export_combined_markdown_pdf", last_export())
    end)

    it("aborts 'all' when the query failed", function()
      MODULES.query_all_repos = function()
        return {}, "everything failed"
      end

      export_cmd.execute({ args = "all clones out.md" })

      assert.equals(0, #calls.export)
      assert.is_true(notified("Error: everything failed"))
    end)

    it("aborts a single repo when both metrics failed", function()
      MODULES.query_metric = function()
        return nil, "no data at all"
      end

      export_cmd.execute({ args = "user/alpha both out.md" })
      assert.equals(0, #calls.export)
      assert.is_true(notified("Error: no data at all"))

      export_cmd.execute({ args = "user/alpha clones out.md" })
      assert.equals(0, #calls.export)
    end)

    it("reports success with the expanded path", function()
      export_cmd.execute({ args = "user/alpha clones out.csv" })

      assert.is_true(notified("Exported to:"))
    end)

    it("reports a writer failure", function()
      package.loaded["github_stats.export"].export_daily_csv = function()
        return false, "permission denied"
      end

      export_cmd.execute({ args = "user/alpha clones out.csv" })

      assert.is_true(notified("Export failed: permission denied"))
    end)

    it("completes target, metric and then file paths", function()
      -- Legacy flat-command line shape; see the note on show.complete above.
      local targets = export_cmd.complete("", "GithubStatsExport ", 0)
      assert.same({ "all", "user/alpha", "user/beta" }, targets)
      assert.same({ "clones", "views", "both" }, export_cmd.complete("", "GithubStatsExport all ", 0))
      -- Third slot defers to Neovim's own file completion.
      assert.is_table(export_cmd.complete("", "GithubStatsExport all both ", 0))
      assert.same({}, export_cmd.complete("", "GithubStatsExport all both x.md ", 0))
    end)
  end)

  describe("diff", function()
    local diff_cmd
    before_each(function()
      diff_cmd = require("github_stats.bindings.usrcmds.diff")
    end)

    it("insists on all four arguments and explains the period format", function()
      diff_cmd.execute({ args = "user/alpha clones 2026-01" })

      assert.equals(0, #calls.diff)
      assert.is_true(notified("Usage: :GithubStats diff"))
      assert.is_true(notified("Period format: YYYY-MM or YYYY"))
    end)

    it("rejects an unknown metric", function()
      diff_cmd.execute({ args = "user/alpha stars 2026-01 2026-02" })

      assert.equals(0, #calls.diff)
      assert.is_true(notified("Metric must be 'clones' or 'views'"))
    end)

    it("reports a comparison error", function()
      MODULES.compare_periods = function()
        return nil, "Invalid period1"
      end

      diff_cmd.execute({ args = "user/alpha clones nope 2026-02" })

      assert.equals(0, #floats)
      assert.is_true(notified("Error: Invalid period1"))
    end)

    it("shows the formatted comparison", function()
      diff_cmd.execute({ args = "user/alpha clones 2026-01 2026-02" })

      assert.same({ "user/alpha", "clones", "2026-01", "2026-02" }, calls.diff[1])
      assert.equals("Diff: user/alpha/clones", floats[1].title)
      assert.same({ "comparison line" }, floats[1].lines)
    end)

    it("completes repo, metric and both period slots", function()
      -- Legacy flat-command line shape; see the note on show.complete above.
      assert.same({ "user/alpha", "user/beta" }, diff_cmd.complete("", "GithubStatsDiff ", 0))
      assert.same({ "clones", "views" }, diff_cmd.complete("", "GithubStatsDiff user/alpha ", 0))

      local now = os.date("*t")
      local this_month = string.format("%04d-%02d", now.year, now.month)
      local period3 = diff_cmd.complete(this_month, "GithubStatsDiff user/alpha clones " .. this_month, 0)
      assert.same({ this_month }, period3)

      -- Presets are not periods: parse_period takes only YYYY-MM or YYYY.
      local period4 = diff_cmd.complete("to", "GithubStatsDiff user/alpha clones 2026-01 to", 0)
      assert.same({}, period4)

      assert.same({}, diff_cmd.complete("", "GithubStatsDiff a b c d e ", 0))
    end)

    it("offers no date preset for the period slots of the composer verb", function()
      require("github_stats.bindings.usrcmds")
      local period = require("lib.nvim.bindings.usercmd.composer.argtypes").get("GH_PERIOD")
      assert.same({}, period.complete("to"))
      assert.same({}, period.complete("last"))
      local year = tostring(os.date("*t").year)
      assert.same(
        { year },
        vim.tbl_filter(function(s)
          return s == year
        end, period.complete(""))
      )
    end)
  end)

  describe("compact", function()
    local compact
    before_each(function()
      compact = require("github_stats.bindings.usrcmds.compact")
    end)

    it("runs retention with the configured windows and reports what it removed", function()
      compact.execute({ args = "" })

      assert.equals(1, #calls.retention)
      assert.is_false(calls.retention[1].dry_run)
      assert.equals(15, calls.retention[1].cutoff_days)
      assert.equals(15, calls.retention[1].prune_days)
      assert.is_true(notified("[github-stats] archived 2 day(s), removed 4 files (4096B freed)"))
    end)

    it("words a dry run differently and touches nothing", function()
      compact.execute({ args = "dry-run" })

      assert.is_true(calls.retention[1].dry_run)
      assert.is_true(notified("Dry run: archived 2 day(s), would remove 4 files (4096B)"))
    end)

    it("reports each retention error separately", function()
      MODULES.retention_summary = function()
        return {
          archived = 0,
          compacted_deleted = 0,
          pruned_deleted = 0,
          freed_bytes = 0,
          errors = { ["user/alpha/clones"] = "unreadable" },
        }
      end

      compact.execute({ args = "" })

      assert.is_true(notified("Retention error (user/alpha/clones): unreadable"))
    end)

    it("completes the dry-run keyword", function()
      assert.same({ "dry-run" }, compact.complete(""))
      assert.same({ "dry-run" }, compact.complete("dry"))
      assert.same({}, compact.complete("x"))
    end)
  end)

  describe("debug", function()
    local debug_cmd
    before_each(function()
      debug_cmd = require("github_stats.bindings.usrcmds.debug")
    end)

    it("reports the configuration, token state and a live API probe", function()
      local saved_token = vim.env.GITHUB_TOKEN
      vim.env.GITHUB_TOKEN = "ghp_0123456789"

      debug_cmd.execute({})

      vim.env.GITHUB_TOKEN = saved_token

      assert.equals(1, #floats)
      local text = table.concat(floats[1].lines, "\n")
      assert.equals("Debug Info", floats[1].title)
      assert.is_truthy(text:find("2 tracked (2 explicit, 0 discovered)", 1, true))
      assert.is_truthy(text:find("Token source: env", 1, true))
      assert.is_truthy(text:find("Token: Present (14 chars)", 1, true))
      assert.is_truthy(text:find("No fetch performed yet", 1, true))
      assert.is_truthy(text:find("Repo: user/alpha", 1, true))
      assert.same({ { repo = "user/alpha", metric = "clones" } }, calls.api)
    end)

    it("reports where the digest goes and that none was written yet", function()
      debug_cmd.execute({})

      local text = table.concat(floats[1].lines, "\n")
      assert.is_truthy(text:find("Digest:", 1, true))
      assert.is_truthy(text:find("Directory: ", 1, true))
      assert.is_truthy(text:find("No digest written in this session yet", 1, true))
    end)

    it("names the token error instead of the token", function()
      local saved_token = vim.env.GITHUB_TOKEN
      vim.env.GITHUB_TOKEN = nil

      debug_cmd.execute({})

      vim.env.GITHUB_TOKEN = saved_token

      assert.is_truthy(table.concat(floats[1].lines, "\n"):find("Token: ERROR", 1, true))
    end)

    it("summarises the last fetch, errors included", function()
      package.loaded["github_stats.fetcher"].last_fetch_summary = {
        timestamp = "2026-03-05T09:00:00",
        success = { "user/alpha/clones" },
        errors = { ["user/beta/views"] = "403" },
      }

      debug_cmd.execute({})

      local text = table.concat(floats[1].lines, "\n")
      assert.is_truthy(text:find("Timestamp: 2026-03-05T09:00:00", 1, true))
      assert.is_truthy(text:find("Successful: 1 metrics", 1, true))
      assert.is_truthy(text:find("user/beta/views: 403", 1, true))
    end)

    it("names the watched users when there are any", function()
      config.init({ config_dir = tmp_dir, repos = { "user/alpha" }, watch_users = { "acme" } })

      debug_cmd.execute({})

      assert.is_truthy(table.concat(floats[1].lines, "\n"):find("Watched users: acme", 1, true))
    end)

    it("says so when nothing is configured, without probing the API", function()
      config.init({ config_dir = tmp_dir, repos = {} })

      debug_cmd.execute({})

      assert.equals(0, #calls.api)
      assert.is_truthy(table.concat(floats[1].lines, "\n"):find("No repositories configured", 1, true))
    end)

    it("reports an API error in the same float", function()
      package.loaded["github_stats.api"].fetch_metric_async = function(_, _, cb)
        cb(nil, "403 Forbidden")
      end

      debug_cmd.execute({})

      assert.is_truthy(table.concat(floats[1].lines, "\n"):find("Error: 403 Forbidden", 1, true))
    end)

    it("bails out when the configuration never loaded", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      config.get = function()
        return nil
      end

      debug_cmd.execute({})

      assert.equals(0, #floats)
      assert.is_true(notified("Config not loaded"))
    end)
  end)

  describe("dashboard", function()
    it("forwards the bang as the force-refresh flag", function()
      local dashboard_cmd = require("github_stats.bindings.usrcmds.dashboard")

      dashboard_cmd.execute({ bang = true })
      dashboard_cmd.execute({ bang = false })

      assert.same({ true, false }, calls.dashboard)
    end)
  end)

  describe("composer registration", function()
    after_each(function()
      pcall(vim.api.nvim_del_user_command, "GithubStats")
    end)

    it("registers a single :GithubStats verb", function()
      require("github_stats.bindings.usrcmds").setup()

      assert.equals(2, vim.fn.exists(":GithubStats"))
    end)

    it("completes its subcommands", function()
      require("github_stats.bindings.usrcmds").setup()

      local subcommands = vim.fn.getcompletion("GithubStats ", "cmdline")

      for _, expected in ipairs({
        "fetch",
        "show",
        "summary",
        "referrers",
        "paths",
        "chart",
        "export",
        "diff",
        "compact",
        "digest",
        "debug",
        "dashboard",
      }) do
        assert.is_truthy(vim.tbl_contains(subcommands, expected), "missing subcommand: " .. expected)
      end
    end)

    it("completes a subcommand's own arguments through the registered types", function()
      require("github_stats.bindings.usrcmds").setup()

      local repos = vim.fn.getcompletion("GithubStats show ", "cmdline")
      assert.is_truthy(vim.tbl_contains(repos, "user/alpha"))

      local targets = vim.fn.getcompletion("GithubStats export ", "cmdline")
      assert.is_truthy(vim.tbl_contains(targets, "all"))

      local presets = vim.fn.getcompletion("GithubStats show user/alpha clones ", "cmdline")
      assert.is_truthy(vim.tbl_contains(presets, "today"))

      local periods = vim.fn.getcompletion("GithubStats diff user/alpha clones ", "cmdline")
      assert.is_truthy(vim.tbl_contains(periods, tostring(os.date("*t").year)))
    end)

    it("routes a subcommand's arguments through to its execute()", function()
      require("github_stats.bindings.usrcmds").setup()

      vim.cmd("GithubStats fetch force")

      assert.same({ true }, calls.fetch)
    end)

    it("attaches the bang to the verb, not the subcommand", function()
      require("github_stats.bindings.usrcmds").setup()

      vim.cmd("GithubStats dashboard")
      vim.cmd("GithubStats! dashboard")

      assert.same({ false, true }, calls.dashboard)
    end)
  end)
end)

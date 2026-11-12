-- TESTS/sheets/features.lua -- the functionalities of github_stats.nvim as its user meets them; `testing sheets
-- report` says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet
-- that names an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/what-you-get.md, docs/FEATURES/ and ALL/manual-test-checklists/github_stats.md.
return {
  {
    id = "github_stats.fetch",
    title = "Traffic data is fetched in a silent background cycle, or now with :GithubStats fetch force",
    surface = { "command:GithubStats fetch" },
    docs = "docs/FEATURES/FETCHING.md",
  },
  {
    id = "github_stats.watch-users",
    title = "The repositories of the users in watch_users are discovered without listing them one by one",
    docs = "docs/FEATURES/FETCHING.md",
  },
  {
    id = "github_stats.dashboard",
    title = "The interactive dashboard over everything collected: sorting, time ranges, trend and sparklines",
    surface = { "command:GithubStats dashboard" },
    docs = "docs/FEATURES/DASHBOARD.md",
  },
  {
    id = "github_stats.reports",
    title = "Read-only reports on stored data: show, summary, period-over-period diff and ASCII charts",
    surface = {
      "command:GithubStats show",
      "command:GithubStats summary",
      "command:GithubStats diff",
      "command:GithubStats chart",
    },
    docs = "docs/FEATURES/ANALYTICS.md",
  },
  {
    id = "github_stats.referrers",
    title = "The top referrer sources and the most visited paths of a repository",
    surface = { "command:GithubStats referrers", "command:GithubStats paths" },
    docs = "docs/FEATURES/ANALYTICS.md",
  },
  {
    id = "github_stats.date-presets",
    title = "Named date ranges, built-in and user-defined, wherever a command takes a range",
    docs = "docs/FEATURES/DATE_PRESETS.md",
  },
  {
    id = "github_stats.export",
    title = "The history written out as CSV, Markdown or PDF, the extension chosen by the format",
    surface = { "command:GithubStats export" },
    docs = "docs/FEATURES/EXPORT.md",
  },
  {
    id = "github_stats.digest",
    title = "A per-repository traffic digest other programs read",
    surface = { "command:GithubStats digest" },
    docs = "docs/FEATURES/DIGEST.md",
  },
  {
    id = "github_stats.retention",
    title = "Old clones and views are archived and stale snapshots pruned, by hand with :GithubStats compact",
    surface = { "command:GithubStats compact" },
    docs = "docs/FEATURES/RETENTION.md",
  },
  {
    id = "github_stats.diagnostics",
    title = ":checkhealth github_stats and :GithubStats debug say what the collector sees",
    surface = { "command:GithubStats debug" },
    docs = "docs/FEATURES/DIAGNOSTICS.md",
  },
  {
    id = "github_stats.statusline",
    title = "A statusline string with this week's views, never blocking on the network",
    docs = "docs/statusline.md",
  },
  {
    id = "github_stats.cli",
    title = "scripts/github_stats.lua runs one background cycle or a report headless, with exit codes",
    docs = "docs/cli.md",
  },
}

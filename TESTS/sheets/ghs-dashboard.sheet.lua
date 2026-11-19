-- Feature sheet: the dashboard over the stored history, and its refresh key `R`, which fetches every repository
-- again. The GitHub API is the stand-in fixtures/fake_github.lua (no request leaves the machine).
return {
  id = "ghs.dashboard",
  feature = "github_stats.dashboard",
  title = ":GithubStats dashboard, refreshed with R",
  sizes = { { rows = 40, cols = 130 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.fake_github()]] },
    {
      lua = [[_G.dir = vim.fn.tempname(); require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" },
        token_source = "file", token_file = _G.token_file, background = { enabled = false } })]],
    },
    { keys = ":GithubStats dashboard<CR>", note = "open the dashboard before anything was fetched" },
    { wait = [[_G.wintext():find("me/proj", 1, true)]], note = "it lists the tracked repository" },
    { expect = [[#_G.calls("curl") == 0]], note = "opening it fetches nothing" },
    { keys = "R", note = "refresh all" },
    {
      wait = [[_G.called("curl", "/repos/me/proj/traffic/clones") and _G.called("curl", "/repos/me/proj/traffic/views")]],
      timeout = 20000,
      note = "R fetches the repository again",
    },
    {
      wait = [[require("github_stats.analytics").query_metric({ repo = "me/proj", metric = "views", time_range = "7d" })
        .total_count == 21]],
      timeout = 20000,
      note = "the fetched views are stored (3 days x 7)",
    },
    { steady = 300, note = "the dashboard redraws with them" },
    {
      expect = [[_G.wintext():find("21 total", 1, true) ~= nil]],
      note = "and shows the fetched views (not the empty numbers from before the fetch)",
    },
    { keys = "q" },
    { wait = [[not _G.wintext():find("me/proj", 1, true)]], note = "q closes it" },
  },
  judge = { "the dashboard reads well: columns, sparklines, the key hints" },
  manual = { "once with a real GITHUB_TOKEN: R refreshes the dashboard of real repositories" },
}

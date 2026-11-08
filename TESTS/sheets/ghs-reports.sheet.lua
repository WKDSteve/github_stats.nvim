-- Live check: the read-only reports of :GithubStats on stored data (task github_stats.nvim/testblatt-bindings-checkliste;
-- the :GithubStats section of BINDINGS-RUNTIME-CHECKLIST.md). Seeded with two months of clones and views of me/proj.
return {
  id = "ghs.reports",
  title = ":GithubStats show, summary, diff and chart on stored data",
  task = "github_stats.nvim/testblatt-bindings-checkliste",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":GithubStats show me/proj clones<CR>" },
    { wait = [[_G.floattext():find("Repository: me/proj", 1, true)]], note = "show opens its float" },
    {
      expect = [[_G.floattext():find("Total Count: 20", 1, true) and _G.floattext():find("2026-10-12", 1, true)]],
      note = "with the total of the five days and the daily breakdown",
    },
    { lua = [[_G.closefloats()]] },
    { keys = ":GithubStats show me/proj views 2026-10-01 2026-10-31<CR>" },
    {
      wait = [[_G.floattext():find("Total Count: 12", 1, true)]],
      note = "show with a date range counts only October (3 days x 4)",
    },
    { expect = [[not _G.floattext():find("2026-09-10", 1, true)]], note = "and leaves September out" },
    { lua = [[_G.closefloats()]] },
    { keys = ":GithubStats summary clones<CR>" },
    { wait = [[_G.floattext():find("me/proj", 1, true)]], note = "summary lists the repository" },
    { lua = [[_G.closefloats()]] },
    { keys = ":GithubStats diff me/proj clones 2026-09 2026-10<CR>" },
    { wait = [[_G.floattext():find("2026-10", 1, true) ~= nil]], note = "diff compares the two months" },
    { lua = [[_G.closefloats()]] },
    { keys = ":GithubStats chart me/proj clones<CR>" },
    {
      wait = [[_G.floattext():find("Chart: me/proj", 1, true) or _G.floattext():find("me/proj", 1, true)]],
      note = "chart opens a sparkline float",
    },
    { lua = [[_G.closefloats()]] },
    { lua = [[_G.forget()]] },
    { keys = ":GithubStats show me/proj stars<CR>" },
    { wait = [[_G.noted("expected one of clones|views")]], note = "a metric that does not exist is refused" },
  },
  judge = { "the show, summary, diff and chart floats read well (numbers, alignment, the sparkline)" },
}

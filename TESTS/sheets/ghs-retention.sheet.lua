-- Feature sheet: `:GithubStats compact` -- first the dry run (nothing changes), then the real run, which folds the
-- old days into the archive; the history reads the same afterwards.
return {
  id = "ghs.retention",
  feature = "github_stats.retention",
  title = ":GithubStats compact dry-run, then compact",
  sizes = { { rows = 30, cols = 110 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":GithubStats compact dry-run<CR>" },
    {
      wait = [[_G.noted("Dry run: archived ") and _G.noted("would remove") and not _G.noted("Retention error")]],
      note = "the dry run previews the archive, without an error",
    },
    {
      expect = [[#vim.fn.glob(_G.dir .. "/data/**/*archive*", true, true) == 0]],
      note = "and writes no archive",
    },
    { lua = [[_G.forget()]] },
    { keys = ":GithubStats compact<CR>" },
    {
      wait = [[_G.noted("[github-stats] archived ") and _G.noted("removed") and not _G.noted("Retention error")]],
      note = "compact archives the old days",
    },
    {
      expect = [[#vim.fn.glob(_G.dir .. "/data/**/*archive*", true, true) > 0]],
      note = "into an archive file (which the dry run did not write)",
    },
    { keys = ":GithubStats show me/proj clones<CR>" },
    {
      wait = [[_G.floattext():find("Total Count: 20", 1, true)]],
      note = "the history still sums all five days (archived ones included)",
    },
  },
}

-- Feature sheet: `:GithubStats fetch force` fetches the traffic of the tracked repository. The GitHub API is the
-- stand-in fixtures/fake_github.lua (no request leaves the machine); clones, views, referrers and paths arrive and
-- are stored, and the reports show them.
return {
  id = "ghs.fetch",
  feature = "github_stats.fetch",
  title = ":GithubStats fetch force stores the traffic the API answers",
  sizes = { { rows = 30, cols = 110 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.fake_github()]] },
    {
      lua = [[_G.dir = vim.fn.tempname(); require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" },
        token_source = "file", token_file = _G.token_file, background = { enabled = false } })]],
    },
    { keys = ":GithubStats fetch force<CR>", note = "the user forces a fetch" },
    { wait = [[_G.noted("Successfully fetched 4 metrics")]], timeout = 20000, note = "all four metrics arrive" },
    {
      expect = [[#_G.calls("curl") == 4 and _G.called("curl", "/repos/me/proj/traffic/clones")
        and _G.called("curl", "/repos/me/proj/traffic/popular/paths")]],
      note = "one request per metric, to the stand-in only",
    },
    {
      expect = [[not _G.called("curl", "sheet-dummy-token")]],
      note = "the token never appears on a command line (it goes through curl's -K -)",
    },
    { keys = ":GithubStats show me/proj clones<CR>" },
    { wait = [[_G.floattext():find("Total Count: 15", 1, true)]], note = "show sums the three fetched days (3 x 5)" },
    { lua = [[_G.closefloats(); _G.forget()]] },
    { keys = ":GithubStats fetch<CR>", note = "a plain fetch right after one" },
    {
      wait = [[_G.floattext():find("Fetch anyway", 1, true)]],
      note = "asks whether to fetch anyway, the interval has not elapsed",
    },
    { keys = "<CR>", note = "the dialog starts on the harmless answer" },
    { wait = [[not _G.floattext():find("Fetch anyway", 1, true)]], note = "the dialog closes" },
    { expect = [[#_G.calls("curl") == 4]], note = "and nothing is fetched" },
  },
  manual = { "once with a real GITHUB_TOKEN: :GithubStats fetch force fetches the real traffic of a repository" },
}

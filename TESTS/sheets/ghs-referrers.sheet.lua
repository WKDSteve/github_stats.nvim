-- Feature sheet: the top referrers and popular paths of a repository, as a fetch brought them in. The GitHub API is
-- the stand-in fixtures/fake_github.lua (no request leaves the machine).
return {
  id = "ghs.referrers",
  feature = "github_stats.referrers",
  title = ":GithubStats referrers and paths after a fetch",
  sizes = { { rows = 30, cols = 110 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.fake_github()]] },
    {
      lua = [[_G.dir = vim.fn.tempname(); require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" },
        token_source = "file", token_file = _G.token_file, background = { enabled = false } })]],
    },
    { keys = ":GithubStats referrers me/proj<CR>", note = "before any fetch" },
    { wait = [[_G.noted("No referrer data available")]], note = "says there is nothing yet" },
    { keys = ":GithubStats fetch force<CR>" },
    { wait = [[_G.noted("Successfully fetched 4 metrics")]], timeout = 20000, note = "the fetch brings them in" },
    { expect = [[_G.called("curl", "/repos/me/proj/traffic/popular/referrers")]], note = "from the referrers endpoint" },
    { keys = ":GithubStats referrers me/proj<CR>" },
    {
      wait = [[_G.floattext():find("news.example.test", 1, true) and _G.floattext():find("Count: 12", 1, true)]],
      note = "the top referrer with its count",
    },
    { expect = [[_G.floattext():find("search.example.test", 1, true) ~= nil]], note = "and the second one" },
    { lua = [[_G.closefloats()]] },
    { keys = ":GithubStats paths me/proj<CR>" },
    { wait = [[_G.floattext():find("/me/proj", 1, true)]], note = "paths lists the most visited path" },
  },
  manual = { "once with a real GITHUB_TOKEN: the referrers of a repository with traffic read plausibly" },
}

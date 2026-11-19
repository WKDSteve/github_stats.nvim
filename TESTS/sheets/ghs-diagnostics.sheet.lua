-- Feature sheet: what the collector sees -- `:checkhealth github_stats` (curl, the token, a live API probe) and
-- `:GithubStats debug` (the configuration and an API test). The API is the stand-in fixtures/fake_github.lua; the
-- `curl --version` probe of the health check runs the real curl (local, no network).
return {
  id = "ghs.diagnostics",
  feature = "github_stats.diagnostics",
  title = ":checkhealth github_stats and :GithubStats debug",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.fake_github(); _G.boot()]] },
    {
      lua = [[require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" },
        token_source = "file", token_file = _G.token_file, background = { enabled = false } })]],
    },
    { keys = ":checkhealth github_stats<CR>", note = "the user runs the health check" },
    {
      wait = [[_G.wintext():find("API connection", 1, true) or _G.wintext():find("API Connectivity", 1, true)]],
      timeout = 20000,
      note = "it reaches the API section",
    },
    { wait = [[_G.called("curl", "/repos/me/proj/traffic/clones")]], note = "the live probe asks the API (the stand-in)" },
    { expect = [[_G.wintext():find("curl available", 1, true) ~= nil]], note = "and finds curl" },
    { expect = [[not _G.wintext():find("ERROR curl", 1, true)]], note = "without a curl error" },
    { lua = [[vim.cmd("bwipeout!")]] },
    { keys = ":GithubStats debug<CR>" },
    { wait = [[_G.floattext():find("me/proj", 1, true) ~= nil]], note = "debug lists the configured repository" },
    {
      wait = [[#_G.calls("curl") >= 2]],
      timeout = 20000,
      note = "and tests the API connection with a request of its own",
    },
  },
  manual = {
    ":checkhealth github_stats and :GithubStats debug with a real GITHUB_TOKEN report the API connection as OK",
  },
}

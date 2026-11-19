-- Feature sheet: `watch_users` -- the editor starts with one watched user and no repository listed; the background
-- cycle discovers the user's repositories and fetches them. The GitHub API is the stand-in fixtures/fake_github.lua.
return {
  id = "ghs.watch-users",
  feature = "github_stats.watch-users",
  title = "watch_users: the background cycle discovers and fetches a user's repositories",
  sizes = { { rows = 30, cols = 110 } },
  args = { "-c", "luafile TESTS/sheets/fixtures/start_watch_users.lua" },
  steps = {
    {
      wait = [[_G.called("curl", "/users/octo/repos")]],
      timeout = 20000,
      note = "the first cycle lists the watched user's repositories",
    },
    {
      wait = [[_G.called("curl", "/repos/octo/alpha/traffic/clones") and _G.called("curl", "/repos/octo/beta/traffic/views")]],
      timeout = 20000,
      note = "and fetches both of them",
    },
    {
      wait = [[vim.tbl_contains(require("github_stats.config").get_repos(), "octo/beta")]],
      note = "the discovered repositories are tracked",
    },
    { keys = ":GithubStats summary clones<CR>" },
    {
      wait = [[_G.floattext():find("octo/alpha", 1, true) and _G.floattext():find("octo/beta", 1, true)]],
      timeout = 10000,
      note = "the summary lists both, without the user naming them",
    },
  },
  manual = { "once with a real GITHUB_TOKEN and a real account in watch_users: its public repositories show up" },
}

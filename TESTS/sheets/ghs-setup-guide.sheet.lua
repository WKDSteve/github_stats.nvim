-- Feature sheet: the setup guide on the first start of a second machine -- `:GithubStats setup`, the user picks remote
-- mode, the guide finds the GitHub login and the existing data repository through `gh`, clones it, sees the secret
-- is set and starts the workflow. `gh` is the stand-in fixtures/fake_github.lua, the data repository a local bare
-- repository (nothing reaches GitHub).
return {
  id = "ghs.setup-guide",
  feature = "github_stats.setup-guide",
  title = "The setup guide on a second machine: remote mode, clone the existing data repository",
  sizes = { { rows = 30, cols = 120 } },
  args = { "-c", "luafile TESTS/sheets/fixtures/start_setup_guide.lua" },
  steps = {
    -- On a real first start the guide opens by itself; it asks for a UI at VimEnter, and a sheet's UI attaches after
    -- VimEnter (manual line below), so here the user opens it.
    { keys = ":GithubStats setup<CR>" },
    {
      wait = [[_G.floattext():find("Where should the GitHub traffic history live?", 1, true)]],
      timeout = 10000,
      note = "the guide asks where the history should live",
    },
    { keys = "<CR>", note = "remote (the first, recommended choice)" },
    {
      wait = [[_G.floattext():find("me/github-stats-vault", 1, true)]],
      timeout = 20000,
      note = "it asks for the data repository, the login from gh filled in",
    },
    { expect = [[_G.called("gh", "user")]], note = "the login came from gh api user" },
    { input = "<CR>", note = "accept the suggested name" },
    {
      wait = [[_G.floattext():find("me/github-stats-vault exists. Clone it", 1, true)]],
      timeout = 20000,
      note = "gh repo view finds the existing repository; the guide offers to clone it",
    },
    { keys = "y" },
    {
      wait = [[_G.floattext():find("Start the workflow now", 1, true)]],
      timeout = 30000,
      note = "cloned, the secret is there (gh secret list): the guide offers the first run",
    },
    {
      expect = [[_G.called("gh", "clone") and _G.called("gh", "secret")]],
      note = "through gh repo clone and gh secret list",
    },
    { keys = "y" },
    {
      wait = [[_G.floattext():find("Remote mode is set up: me/github-stats-vault", 1, true)]],
      timeout = 20000,
      note = "the workflow started, the guide says what is set up",
    },
    { expect = [[_G.called("gh", "workflow")]], note = "through gh workflow run" },
    {
      expect = [[require("github_stats.remote").active()]],
      note = "and the plugin reads the history from the clone now",
    },
  },
  manual = {
    "the first start after installing (nothing in the spec): the guide opens by itself after about 1.5 s",
    ":GithubStats setup on the very first machine with a real GitHub account: it creates the data repository and sets the secret",
  },
}

-- Feature sheet: remote mode on a new machine -- the data repository named in the spec is cloned on the first start
-- (through `gh`), `:GithubStats sync` pulls what the workflow pushed since, `:GithubStats fetch` starts the
-- workflow instead of fetching here. `gh` is the stand-in fixtures/fake_github.lua, the data repository a local bare
-- repository (git runs for real, nothing reaches GitHub).
return {
  id = "ghs.remote",
  feature = "github_stats.remote",
  title = "Remote mode: clone on first start, :GithubStats sync, fetch starts the workflow",
  sizes = { { rows = 30, cols = 110 } },
  args = { "-c", "luafile TESTS/sheets/fixtures/start_remote.lua" },
  steps = {
    {
      wait = [[_G.noted("Cloned the data repository me/vault")]],
      timeout = 30000,
      note = "the first start clones the data repository",
    },
    {
      expect = [[_G.called("gh", "clone") and vim.fn.filereadable(_G.clone .. "/config.json") == 1]],
      note = "through gh repo clone",
    },
    { keys = ":GithubStats show me/proj clones<CR>" },
    { wait = [[_G.floattext():find("Total Count: 4", 1, true)]], note = "the history is the data repository's" },
    { lua = [[_G.closefloats(); _G.forget(); _G.publish("2026-10-11", 6)]], note = "the workflow pushes a new day" },
    { keys = ":GithubStats sync<CR>" },
    { wait = [[_G.noted("me/vault: new data pulled")]], timeout = 30000, note = "sync pulls it" },
    { keys = ":GithubStats show me/proj clones<CR>" },
    { wait = [[_G.floattext():find("Total Count: 10", 1, true)]], note = "and the new day is counted" },
    { lua = [[_G.closefloats(); _G.forget()]] },
    { keys = ":GithubStats sync<CR>", note = "again, nothing new" },
    { wait = [[_G.noted("me/vault: already up to date")]], timeout = 30000 },
    { lua = [[_G.forget()]] },
    { keys = ":GithubStats fetch<CR>", note = "fetch in remote mode" },
    {
      wait = [[_G.noted("Workflow started") and _G.called("gh", "workflow")]],
      timeout = 20000,
      note = "starts the data repository's workflow instead of fetching here",
    },
    { expect = [[#_G.calls("curl") == 0]], note = "this machine never asks the traffic API" },
  },
  manual = {
    ":GithubStats setup with a real GitHub account: the guide creates the data repository, sets the secret and runs the workflow",
  },
}

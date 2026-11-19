-- Feature sheet: the headless command line (scripts/github_stats.lua) -- `collect` fetches, archives and writes the
-- digests, `report` prints the history as JSON, a missing token is exit 2. Run in the editor through
-- `github_stats.cli.run` (what the script calls), so testing perf sees its processes. The GitHub API is the stand-in
-- fixtures/fake_github.lua, the token a dummy in an environment variable of the child.
return {
  id = "ghs.cli",
  feature = "github_stats.cli",
  title = "scripts/github_stats.lua collect and report",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.fake_github()
        _G.dir = vim.fn.tempname(); vim.fn.mkdir(_G.dir, "p")
        vim.env.GHS_SHEET_TOKEN = "sheet-dummy-token"
        _G.base = { "--repos=me/proj", "--config-dir=" .. _G.dir, "--digest-dir=" .. _G.dir .. "/digest" }]],
    },
    { lua = [[_G.run_cli(vim.list_extend({ "collect", "--force", "--token-env=GHS_SHEET_TOKEN" }, _G.base))]] },
    { wait = [[_G.cli_code ~= nil]], timeout = 30000, note = "collect runs to its end" },
    {
      expect = [[_G.cli_code == 0 and _G.cli_out:find("fetched 4 metrics, 0 errors", 1, true) ~= nil]],
      note = "exit 0, all four metrics fetched",
    },
    { expect = [[#_G.calls("curl") == 4]], note = "from the stand-in, one request each" },
    { expect = [[_G.cli_out:find("digests: 1 written", 1, true) ~= nil]], note = "and the digest written" },
    { lua = [[_G.run_cli(vim.list_extend({ "report", "--format=json" }, _G.base))]] },
    { wait = [[_G.cli_code ~= nil]], timeout = 10000 },
    {
      expect = [[_G.cli_code == 0 and vim.json.decode(_G.cli_out) ~= nil and _G.cli_out:find("me/proj", 1, true) ~= nil]],
      note = "report prints the history of me/proj as JSON",
    },
    { expect = [[#_G.calls("curl") == 4]], note = "report never fetches" },
    { lua = [[_G.run_cli(vim.list_extend({ "collect", "--force", "--token-env=GHS_NO_SUCH_TOKEN" }, _G.base))]] },
    { wait = [[_G.cli_code ~= nil]], timeout = 10000 },
    {
      expect = [[_G.cli_code == 2 and _G.cli_err:find("no GitHub token", 1, true) ~= nil]],
      note = "without a token: exit 2 and why",
    },
  },
  manual = {
    "nvim --headless -u NONE -l scripts/github_stats.lua collect with a real GITHUB_TOKEN, as the data repository's workflow runs it",
  },
}

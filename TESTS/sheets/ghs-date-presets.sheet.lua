-- Feature sheet: named date ranges -- a user-defined preset typed at the dashboard's custom range prompt (`T`)
-- narrows what the dashboard counts; a name nobody defined is refused.
return {
  id = "ghs.date-presets",
  feature = "github_stats.date-presets",
  title = "A custom date preset at the dashboard's T prompt",
  sizes = { { rows = 40, cols = 130 } },
  -- the T prompt is input(): it must really wait for what the sheet types
  prompts = "real",
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    {
      lua = [[require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" }, background = { enabled = false },
        date_presets = { custom = { october_window = function() return "2026-10-10", "2026-10-12" end } } })]],
      note = "a preset of the user's own: three days of October",
    },
    { keys = ":GithubStats dashboard<CR>" },
    { wait = [[_G.wintext():find("me/proj", 1, true)]], note = "the dashboard is open" },
    { input = "T", note = "custom range" },
    { input = "<C-u>october_window<CR>" },
    {
      wait = [[_G.wintext():find("Range:october_window", 1, true)]],
      timeout = 5000,
      note = "the header names the preset",
    },
    {
      expect = [[_G.wintext():find("12 clones", 1, true) ~= nil]],
      note = "and counts only its three days (3 x 4 clones)",
    },
    { lua = [[_G.forget()]] },
    { input = "T" },
    { input = "<C-u>no_such_preset<CR>" },
    { wait = [[_G.noted("Unrecognized time range: 'no_such_preset'")]], note = "an unknown name is refused" },
  },
}

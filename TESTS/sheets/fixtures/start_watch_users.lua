-- TESTS/sheets/fixtures/start_watch_users.lua -- the startup of ghs-watch-users.sheet.lua (`-c luafile ...`): the
-- plugin is set up like a user config does it, before VimEnter, with one watched user and no repository listed.
-- VimEnter then starts the background cycle, which discovers the user's repositories and fetches them. The sheet's
-- UI attaches after VimEnter, and a first cycle that finds no UI is skipped on purpose (background.has_ui), so the
-- first cycle waits 2 s instead of the default 1 s: room for the attach on a loaded CI machine.
dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
_G.fake_github()
_G.dir = vim.fn.tempname()
require("github_stats").setup({
  config_dir = _G.dir,
  repos = {},
  watch_users = { "octo" },
  token_source = "file",
  token_file = _G.token_file,
  background = { initial_delay_ms = 2000 },
})

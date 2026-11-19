-- TESTS/sheets/fixtures/start_remote.lua -- the startup of ghs-remote.sheet.lua (`-c luafile ...`): a new machine
-- whose spec names the data repository (`storage = { repo = ... }`), not cloned yet; the data repository is the
-- local bare repository of data_repo.lua. VimEnter then clones it, as on a real first start.
dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
_G.fake_github()
dofile(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/data_repo.lua")
_G.clone = vim.fn.tempname()
require("github_stats").setup({
  storage = { mode = "remote", repo = "me/vault", dir = _G.clone, sync_on_start = false },
})

-- TESTS/sheets/fixtures/start_setup_guide.lua -- the startup of ghs-setup-guide.sheet.lua (`-c luafile ...`): the
-- first start after installing, nothing decided on this machine (remote mode by default, no data repository known).
-- The user's data repository already exists (made on another machine): the local bare repository of data_repo.lua.
dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
_G.fake_github()
dofile(vim.fn.getcwd() .. "/TESTS/sheets/fixtures/data_repo.lua")
require("github_stats").setup({})

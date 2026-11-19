-- TESTS/sheets/fixtures/data_repo.lua -- a data repository for the remote-mode sheets, as a local bare repository
-- (never GitHub): `_G.origin` (bare), `_G.seed` (the workflow's side, `_G.publish` commits and pushes a day of clones
-- of me/proj), one day already published. The stand-in `gh repo clone` (fake_github.lua) clones `_G.origin`.
-- Needs _helpers.lua and `_G.fake_github()` first.
local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
_G.origin = base .. "/origin.git"
_G.seed = base .. "/seed"
_G.git(base, { "init", "--quiet", "--bare", "-b", "main", _G.origin })
_G.git(base, { "init", "--quiet", "-b", "main", _G.seed })

---Commit one day of clones of me/proj into the seed and push it to the bare origin (what the workflow does daily).
---@param date string YYYY-MM-DD
---@param count integer
function _G.publish(date, count)
  local file = ("%s/data/me_proj/clones/%sT00-00-00.json"):format(_G.seed, date)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  local day = { timestamp = date .. "T00:00:00Z", count = count, uniques = 1 }
  vim.fn.writefile({ vim.json.encode({ timestamp = date .. "T00:00:00Z", data = { clones = { day } } }) }, file)
  _G.git(_G.seed, { "add", "-A" })
  _G.git(_G.seed, { "commit", "--quiet", "-m", "collect " .. date })
  _G.git(_G.seed, { "push", "--quiet", "origin", "main" })
end

vim.fn.writefile({ vim.json.encode({ repos = { "me/proj" } }) }, _G.seed .. "/config.json")
_G.git(_G.seed, { "remote", "add", "origin", _G.origin })
_G.publish("2026-10-10", 4)
vim.fn.writefile({ _G.origin }, _G.fake_state .. "/origin.txt")

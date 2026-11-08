-- TESTS/sheets/_helpers.lua -- what every github_stats test sheet needs in its child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's first step runs it with `dofile`, the child's cwd is
-- the project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The plugin runs for real on a throwaway data directory seeded with two months of clones and views of one
-- repository ("me/proj"). Nothing goes to GitHub: no command a sheet runs fetches.

vim.o.swapfile = false
vim.opt.shortmess:append("I")

_G.notes = {}
vim.notify = function(msg)
  _G.notes[#_G.notes + 1] = tostring(msg)
end

---Whether a notification so far holds `text` (plain).
---@param text string
---@return boolean
function _G.noted(text)
  for _, n in ipairs(_G.notes) do
    if n:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Forget the notifications so far.
function _G.forget()
  _G.notes = {}
end

---The text of every floating window, joined.
---@return string
function _G.floattext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      out[#out + 1] = table.concat(lines, "\n")
    end
  end
  return table.concat(out, "\n")
end

---Close every floating window.
function _G.closefloats()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
end

---Set the plugin up on a fresh data directory and seed it.
function _G.boot()
  _G.dir = vim.fn.tempname()
  vim.fn.mkdir(_G.dir, "p")
  require("github_stats").setup({ config_dir = _G.dir, repos = { "me/proj" } })
  local storage = require("github_stats.storage")
  for _, metric in ipairs({ "clones", "views" }) do
    local days = {}
    for _, date in ipairs({ "2026-09-10", "2026-09-11", "2026-10-10", "2026-10-11", "2026-10-12" }) do
      days[#days + 1] = { timestamp = date .. "T00:00:00Z", count = 4, uniques = 2 }
    end
    storage.write_metric("me/proj", metric, { [metric] = days })
  end
end

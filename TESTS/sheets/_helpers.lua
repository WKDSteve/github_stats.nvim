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

---The text of every floating window, its title included (a dialog's question is often the title), joined.
---@return string
function _G.floattext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= "" then
      if type(cfg.title) == "table" then
        for _, chunk in ipairs(cfg.title) do
          out[#out + 1] = type(chunk) == "table" and tostring(chunk[1]) or tostring(chunk)
        end
      elseif type(cfg.title) == "string" then
        out[#out + 1] = cfg.title
      end
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      out[#out + 1] = table.concat(lines, "\n")
    end
  end
  return table.concat(out, "\n")
end

---The text of every visible window (floats and splits), joined.
---@return string
function _G.wintext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
    out[#out + 1] = table.concat(lines, "\n")
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

---Send `curl` and `gh` to the stand-in TESTS/sheets/fixtures/fake_github.lua (redirect.lua says why and how). Its
---calls are logged in `_G.fake_state`, `_G.calls()` reads them. Also writes a token file with a dummy token, so the
---plugin has one without the user's real GITHUB_TOKEN (which a sheet child never sees).
function _G.fake_github()
  local root = vim.fn.getcwd() .. "/TESTS/sheets/fixtures"
  _G.fake_state = vim.fn.tempname()
  vim.fn.mkdir(_G.fake_state, "p")
  _G.token_file = _G.fake_state .. "/token"
  vim.fn.writefile({ "sheet-dummy-token" }, _G.token_file)
  local text = table.concat(vim.fn.readfile(root .. "/redirect.lua"), "\n")
  assert(load(text, "=ghs_redirect"))(_G.fake_state, root .. "/fake_github.lua")
end

---The calls the stand-in saw so far, `{ program, argv }` each, of `program` only when given.
---@param program? string "curl"|"gh"
---@return { program: string, argv: string[] }[]
function _G.calls(program)
  local out = {}
  local files = vim.fn.glob(_G.fake_state .. "/calls/*.json", true, true)
  table.sort(files)
  for _, path in ipairs(files) do
    local ok, call = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if ok and type(call) == "table" and (not program or call.program == program) then
      out[#out + 1] = call
    end
  end
  return out
end

---Whether a call of the stand-in had an argument containing `text` (plain).
---@param program string
---@param text string
---@return boolean
function _G.called(program, text)
  for _, call in ipairs(_G.calls(program)) do
    for _, a in ipairs(call.argv) do
      if a:find(text, 1, true) then
        return true
      end
    end
  end
  return false
end

---Run git in `dir` (a sheet's preparation: a local repository, never the network); raises on failure.
---@param dir string
---@param args string[]
function _G.git(dir, args)
  local cmd = { "git", "-c", "user.name=sheet", "-c", "user.email=sheet@example.test", "-c", "commit.gpgsign=false" }
  vim.list_extend(cmd, { "-C", dir })
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
end

---Run scripts/github_stats.lua's command line in this editor (`github_stats.cli.run`, what the script calls), on
---the main loop; `_G.cli_code` is its exit code once done, `_G.cli_out`/`_G.cli_err` what it printed. In the editor
---and not as `nvim -l`: testing perf's trace does not follow into a child `nvim -l`. stdout and stderr go to files
---meanwhile (an embedded editor's stdout is its RPC channel).
---@param argv string[]
function _G.run_cli(argv)
  _G.cli_code, _G.cli_out, _G.cli_err = nil, nil, nil
  vim.schedule(function()
    local out, err = vim.fn.tempname(), vim.fn.tempname()
    local stdout, stderr = io.stdout, io.stderr
    io.stdout, io.stderr = assert(io.open(out, "w")), assert(io.open(err, "w"))
    local ok, code = pcall(require("github_stats.cli").run, argv)
    io.stdout:close()
    io.stderr:close()
    io.stdout, io.stderr = stdout, stderr
    _G.cli_out = table.concat(vim.fn.readfile(out), "\n")
    _G.cli_err = table.concat(vim.fn.readfile(err), "\n") .. (ok and "" or tostring(code))
    _G.cli_code = ok and code or -1
  end)
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

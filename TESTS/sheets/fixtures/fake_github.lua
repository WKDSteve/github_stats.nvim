-- TESTS/sheets/fixtures/fake_github.lua -- the stand-in for `curl` and `gh` in the test sheets, run as
-- `nvim -n -i NONE --headless -u NONE -l fake_github.lua <state-dir> <curl|gh> <argv...>` (redirect.lua builds that
-- command line). Nothing reaches GitHub: `curl` answers the GitHub REST endpoints the plugin asks for with local data
-- (a 200 with headers, as `curl -i` prints it), `gh repo clone` clones the local bare repository named in
-- `<state-dir>/origin.txt`, `gh api user` answers "me", `gh repo view` says the repository exists, `gh secret list`
-- lists the workflow's secret, every other `gh` call succeeds silently. Each call is one
-- JSON file in `<state-dir>/calls/` (`{ "program": ..., "argv": [...] }`), which a sheet reads (`_G.calls()`).
local state, program = arg[1], arg[2]
local argv = {}
for i = 3, #arg do
  argv[#argv + 1] = arg[i]
end

-- One file per call: the fetch starts four of these at once, and appends of parallel processes to one shared file
-- lose lines on Windows. The name sorts by start time (the pid keeps two in the same nanosecond apart).
vim.fn.mkdir(state .. "/calls", "p")
local name = ("%s/calls/%020d-%d.json"):format(state, vim.uv.hrtime(), vim.uv.os_getpid())
local log = io.open(name, "w")
if log then
  log:write(vim.json.encode({ program = program, argv = argv }))
  log:close()
end

---@param days integer
---@return string
local function day(days)
  return os.date("!%Y-%m-%d", os.time() - days * 86400) .. "T00:00:00Z"
end

---@param key string "clones"|"views"
---@param count integer per day
local function traffic(key, count)
  local list = {}
  for d = 3, 1, -1 do
    list[#list + 1] = { timestamp = day(d), count = count, uniques = 1 }
  end
  return { count = 3 * count, uniques = 3, [key] = list }
end

---The body for a GitHub API URL, nil for one this stand-in does not know (a 404).
---@param url string
---@return table|nil
local function answer(url)
  local path = url:gsub("^https?://[^/]+", ""):gsub("%?.*$", "")
  if path:match("^/repos/[^/]+/[^/]+/traffic/clones$") then
    return traffic("clones", 5)
  elseif path:match("^/repos/[^/]+/[^/]+/traffic/views$") then
    return traffic("views", 7)
  elseif path:match("/traffic/popular/referrers$") then
    return {
      { referrer = "news.example.test", count = 12, uniques = 5 },
      { referrer = "search.example.test", count = 4, uniques = 2 },
    }
  elseif path:match("/traffic/popular/paths$") then
    return { { path = "/me/proj", title = "proj", count = 9, uniques = 4 } }
  elseif path:match("^/users/[^/]+/repos$") then
    local user = path:match("^/users/([^/]+)/repos$")
    -- one page: fewer than per_page entries end the listing
    return { { full_name = user .. "/alpha" }, { full_name = user .. "/beta" } }
  elseif path == "/rate_limit" then
    return { resources = { core = { limit = 5000, remaining = 4999, reset = 0 } } }
  end
  return nil
end

if program == "curl" then
  local url
  for _, a in ipairs(argv) do
    if a:match("^https?://") then
      url = a
    end
  end
  local body = url and answer(url)
  local status = body and "200 OK" or "404 Not Found"
  local text = vim.json.encode(body or { message = "Not Found" })
  local out = {}
  if vim.tbl_contains(argv, "-i") then
    out[#out + 1] = "HTTP/1.1 " .. status .. "\n"
    out[#out + 1] = "content-type: application/json; charset=utf-8\n"
    out[#out + 1] = "x-ratelimit-limit: 5000\n"
    out[#out + 1] = "x-ratelimit-remaining: 4999\n"
    out[#out + 1] = "\n"
  end
  out[#out + 1] = text
  io.stdout:write(table.concat(out))
  os.exit(0)
end

if program == "gh" then
  if argv[1] == "repo" and argv[2] == "clone" then
    local fd = io.open(state .. "/origin.txt", "r")
    local origin = fd and vim.trim(fd:read("*a")) or ""
    if fd then
      fd:close()
    end
    if origin == "" then
      io.stderr:write("fake gh: no origin.txt in the state folder\n")
      os.exit(1)
    end
    local res = vim.system({ "git", "clone", "--quiet", origin, argv[4] }, { text = true }):wait()
    io.stderr:write(res.stderr or "")
    os.exit(res.code)
  end
  if argv[1] == "api" and argv[2] == "user" then
    io.stdout:write("me\n")
  elseif argv[1] == "repo" and argv[2] == "view" then
    -- the data repository exists (the setup guide then offers to clone it)
    io.stdout:write(vim.json.encode({ name = (argv[3] or ""):gsub("^.*/", "") }), "\n")
  elseif argv[1] == "secret" and argv[2] == "list" then
    io.stdout:write(vim.json.encode({ { name = "GH_STATS_TOKEN" } }), "\n")
  end
  os.exit(0)
end

io.stderr:write("fake_github: unknown program " .. tostring(program) .. "\n")
os.exit(2)

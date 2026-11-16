---@module 'github_stats.digest'
---@brief Per-repository traffic digest for other programs to read
---@description
--- Publishes one small JSON file per tracked repository (`digest/<owner_repo>.json`)
--- plus a pointer file (`root.json`), so that another process -- a desktop
--- app, another Neovim plugin -- can show this plugin's traffic without
--- re-implementing its semantics (dedupe by day, today excluded, archive,
--- trend) and without ever seeing a token. The file format is a contract:
--- see `docs/FEATURES/DIGEST.md`.
---
--- Deliberately UI-free. `require("github_stats")` loads the dashboard at
--- module load and the dashboard needs `ui.nvim`; a reader that probes for the
--- plugin by requiring the top-level module would report "not installed" for
--- someone who has the plugin but not its UI dependency. This module needs
--- only `config`, `storage`, `analytics` and `lib.nvim`, so it can be probed
--- on its own, and `digest_dir()` answers before `setup()` has run.
---
--- Two locations, on purpose. The raw history lives in the (synced) Neovim
--- config, so both of a user's machines share one dataset. The digest is
--- *derived* and rewritten in place, so in a synced folder two machines would
--- overwrite each other; it goes to a local, per-machine directory
--- (`digest_dir`, default `stdpath("data")/github_stats.nvim`) and is rebuilt
--- from the history whenever the history is newer (`M.stale`).

local config = require("github_stats.config")
local storage = require("github_stats.storage")
local analytics = require("github_stats.analytics")
local fs_json = require("lib.nvim.fs.json")

local M = {}

local uv = vim.uv or vim.loop
local fn = vim.fn

---Schema version written into every file. A reader must refuse a higher one.
M.SCHEMA = 1

local DEFAULT_DAILY_DAYS = 400
-- GitHub reports the top 10 referrers and paths; nothing here widens that.
local TOP_N = 10
local SNAPSHOT_METRICS = { "clones", "views", "referrers", "paths" }
-- Beyond 2^53 a Lua number no longer counts by ones; a reader with integer
-- fields would choke on the exponent form long before that.
local MAX_INT = 2 ^ 53
local MAX_REFERRER_CHARS = 200
local MAX_PATH_CHARS = 500
local MAX_TITLE_CHARS = 300

---Outcome of the most recent `M.write` (for `:GithubStats debug`); nil until one ran.
---@type GHStats.Digest.WriteResult?
M.last_result = nil

---Error raised by the last deferred write (`M.write_later`), if it raised.
---@type string?
M.last_error = nil

---@internal
---Forward slashes only. The values end up in JSON read by other programs and
---compared as strings, and Windows accepts "/" everywhere.
---@param path string
---@return string
local function slashes(path)
  local out = path:gsub("\\", "/")
  return out
end

---@internal
---A count as a non-negative integer, whatever the file contained.
---@param value any
---@return integer
local function count_of(value)
  local n = tonumber(value)
  if not n or n ~= n or n < 0 then
    return 0
  end
  return math.floor(math.min(n, MAX_INT))
end

---@internal
---@param date any
---@return boolean
local function is_iso_date(date)
  return type(date) == "string" and date:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

---@internal
---One decimal is all a trend arrow needs, and a stable value keeps the
---changed-only comparison from seeing float noise as a change.
---@param n number
---@return number
local function round1(n)
  return math.floor(n * 10 + 0.5) / 10
end

---@internal
---Truncate by characters, so a multi-byte character is never cut in half.
---@param str string
---@param max integer
---@return string
local function clip(str, max)
  return fn.strcharpart(str, 0, max)
end

---Default location of the local, per-machine digest area.
---@return string
function M.default_dir()
  return slashes(fn.stdpath("data")) .. "/github_stats.nvim"
end

---Where digests are written. Works before `setup()` (it then names the
---default), which is what lets another program ask this module for the
---location without a running plugin.
---@return string
function M.digest_dir()
  local cfg = config.get()
  local custom = cfg and cfg.digest_dir
  if type(custom) == "string" and custom ~= "" then
    return slashes(fn.expand(custom))
  end
  return M.default_dir()
end

---The pointer file. Always at the default place, even when `digest_dir` is
---overridden -- that is the point: it names where the digests really are.
---@return string
function M.root_path()
  return M.default_dir() .. "/root.json"
end

---@internal
---@return integer
local function daily_days()
  local cfg = config.get()
  local n = cfg and cfg.digest_daily_days
  if type(n) == "number" and n >= 1 then
    return math.floor(n)
  end
  return DEFAULT_DAILY_DAYS
end

---File name (without extension) a repository's digest is stored under.
---@param repo string "owner/name"
---@return string
function M.file_stem(repo)
  return storage.sanitize_repo_name(repo)
end

---Path of a repository's digest file.
---@param repo string "owner/name"
---@return string
function M.digest_file(repo)
  return M.digest_dir() .. "/digest/" .. M.file_stem(repo) .. ".json"
end

---Where the stale check keeps what it learnt between Neovim sessions. Private to this plugin (readers ignore
---it), next to `root.json` because that place is always local to the machine, even when `digest_dir` points
---into the synced history.
---@return string
function M.memo_path()
  return M.default_dir() .. "/stale-memo.json"
end

---@internal
---Per repository: the directory signature of the last listing and what it found (`newest_fetch`), and the
---signature of the digest file last read and the `fetched` it held (`digest_fetched`). Every entry is only
---used while its signature still matches what is on disk, so an outdated one costs a re-read, never a wrong
---answer. Loaded from `M.memo_path()` on first use: the first check of a session is the common case (the
---background cycle runs about four times per session), and without the file it listed every history
---directory and decoded every digest again.
---@type table<string, { key: string?, fetched: string?, digest_key: string?, digest_fetched: string|false|nil }>?
local fetch_memo = nil
local memo_dirty = false

---@internal
---@return table<string, table>
local function memo()
  if fetch_memo then
    return fetch_memo
  end
  fetch_memo = {}
  local ok, stored = pcall(fs_json.read, M.memo_path())
  if ok and type(stored) == "table" and stored.schema == 1 and type(stored.repos) == "table" then
    for repo, entry in pairs(stored.repos) do
      if type(repo) == "string" and type(entry) == "table" then
        fetch_memo[repo] = {
          key = type(entry.key) == "string" and entry.key or nil,
          fetched = type(entry.fetched) == "string" and entry.fetched or nil,
          digest_key = type(entry.digest_key) == "string" and entry.digest_key or nil,
          digest_fetched = type(entry.digest_fetched) == "string" and entry.digest_fetched or false,
        }
      end
    end
  end
  return fetch_memo
end

---@internal
---@param repo string
---@return table
local function memo_entry(repo)
  local all = memo()
  local entry = all[repo]
  if not entry then
    entry = {}
    all[repo] = entry
  end
  return entry
end

---@internal
---Persist the memo when a check learnt something. A failed write only costs the next session a re-read.
---@return nil
local function save_memo()
  if not memo_dirty or not fetch_memo then
    return
  end
  memo_dirty = false
  pcall(fs_json.write, M.memo_path(), { schema = 1, repos = fetch_memo })
end

---@internal
---Identity of a file as far as "did it change?" goes. An atomic write (temp file + rename) gives a new file,
---so the inode changes along with the mtime even on a file system with a coarse clock.
---@param path string
---@return string?
local function file_key(path)
  local st = uv.fs_stat(path)
  if not st or st.type ~= "file" then
    return nil
  end
  return ("%s:%s:%d.%d:%d"):format(path, tostring(st.ino), st.mtime.sec, st.mtime.nsec, st.size)
end

---@internal
---The `fetched` a repository's digest file holds; false when the file is missing, unreadable or has none.
---Decoded only when the file changed since the last look (a 400-day digest is about 20 KB of JSON, and the
---stale check used to decode every one of them on every check).
---@param repo string
---@param path string
---@return string|false
local function digest_fetched(repo, path)
  local key = file_key(path)
  if not key then
    return false
  end
  local entry = memo_entry(repo)
  if entry.digest_key == key then
    return entry.digest_fetched or false
  end
  local existing = fs_json.read(path)
  local fetched = type(existing) == "table" and type(existing.fetched) == "string" and existing.fetched or false
  entry.digest_key, entry.digest_fetched = key, fetched
  memo_dirty = true
  return fetched
end

---@internal
---Turn a history file stamp (`2026-09-25T10-30-00`, UTC) into ISO 8601.
---@param stamp string
---@return string
local function stamp_to_iso(stamp)
  local date, h, m, s = stamp:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d)%-(%d%d)%-(%d%d)$")
  return string.format("%sT%s:%s:%sZ", date, h, m, s)
end

---@internal
---Newest fetch of a repository, read from file *names* only -- a directory
---listing, no JSON decode, and no dependence on mtimes (which a sync tool may
---rewrite). This is what makes the stale check cheap enough for startup.
---@param repo string
---@return string? # ISO 8601 (UTC), nil when nothing was ever fetched
local function newest_fetch(repo)
  -- A directory whose mtime did not move gained no snapshot file: the listing of the history (hundreds of files
  -- per repository, every `stale` check of the background cycle) is only repeated when one of them moved. A
  -- changed mtime only costs the listing again, so a sync tool rewriting mtimes cannot make the answer wrong.
  local signature = {}
  for _, metric in ipairs(SNAPSHOT_METRICS) do
    local dir = storage.get_metric_dir(repo, metric)
    local st = uv.fs_stat(dir)
    signature[#signature + 1] = dir .. (st and st.mtime and (":%d.%d"):format(st.mtime.sec, st.mtime.nsec) or ":none")
  end
  local key = table.concat(signature, "|")
  local entry = memo_entry(repo)
  if entry.key == key then
    return entry.fetched
  end
  local newest
  for _, metric in ipairs(SNAPSHOT_METRICS) do
    local handle = uv.fs_scandir(storage.get_metric_dir(repo, metric))
    while handle do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local stamp = name:match("^(%d%d%d%d%-%d%d%-%d%dT%d%d%-%d%d%-%d%d)%.json$")
      if stamp and (not newest or stamp > newest) then
        newest = stamp
      end
    end
  end
  local fetched = newest and stamp_to_iso(newest) or nil
  entry.key, entry.fetched = key, fetched
  memo_dirty = true
  return fetched
end

---@internal
---Sums over the last `days` complete days, using the plugin's own range
---parser so the window means what the dashboard's `7d`/`30d`/`90d` mean.
---`uniques` is the sum of the daily uniques, not a distinct-visitor count
---(the same approximation the dashboard makes).
---@param daily table<string, {count: integer, uniques: integer}>
---@param days integer
---@return GHStats.Digest.Window
local function window(daily, days)
  local from = analytics.parse_time_range(days .. "d")
  local count, uniques = 0, 0
  for date, stats in pairs(daily) do
    if date >= from then
      count = count + stats.count
      uniques = uniques + stats.uniques
    end
  end
  return { count = count, uniques = uniques }
end

---@internal
---@param daily table<string, {count: integer, uniques: integer}>
---@return GHStats.Digest.Metric
local function metric_block(daily)
  local block = { d7 = window(daily, 7), d30 = window(daily, 30), d90 = window(daily, 90) }
  local trend = analytics.trend_over(daily, 7)
  if trend then
    block.trend = round1(trend)
  end
  return block
end

---@internal
---`[date, count, uniques]` tuples, oldest first, at most `keep` of them.
---@param daily table<string, {count: integer, uniques: integer}>
---@param keep integer
---@return table[]
local function daily_series(daily, keep)
  local dates = vim.tbl_keys(daily)
  table.sort(dates)
  local out = {}
  for i = math.max(1, #dates - keep + 1), #dates do
    local stats = daily[dates[i]]
    out[#out + 1] = { dates[i], stats.count, stats.uniques }
  end
  return out
end

---@internal
---Aggregated days of one metric with every field validated. Analytics drops
---today and dedupes by day; what is left is cleaned here so nothing malformed
---that slipped into a stored file reaches a reader.
---@param repo string
---@param metric "clones"|"views"
---@return table<string, {count: integer, uniques: integer}>? daily
---@return string? err
local function clean_daily(repo, metric)
  local stats, err = analytics.query_metric({ repo = repo, metric = metric, time_range = "all" })
  if not stats then
    return nil, err
  end
  local daily = {}
  for date, day in pairs(stats.daily_breakdown) do
    if is_iso_date(date) then
      daily[date] = { count = count_of(day.count), uniques = count_of(day.uniques) }
    end
  end
  return daily, nil
end

---@internal
---Whether a metric has ever been fetched. Referrers and paths are a single
---snapshot, so "no snapshot" (unknown) must not be written as "an empty top
---10" (GitHub said nobody referred anything).
---@param repo string
---@param metric string
---@return boolean
local function has_snapshot(repo, metric)
  local history = storage.read_metric_history(repo, metric)
  return #history > 0
end

---@internal
---@param repo string
---@return table[]?
local function referrer_list(repo)
  if not has_snapshot(repo, "referrers") then
    return nil
  end
  local list, err = analytics.get_top_referrers(repo, TOP_N)
  if err then
    return nil
  end
  local out = {}
  for _, item in ipairs(list) do
    if type(item) == "table" and type(item.referrer) == "string" then
      out[#out + 1] = {
        referrer = clip(item.referrer, MAX_REFERRER_CHARS),
        count = count_of(item.count),
        uniques = count_of(item.uniques),
      }
    end
  end
  return out
end

---@internal
---@param repo string
---@return table[]?
local function path_list(repo)
  if not has_snapshot(repo, "paths") then
    return nil
  end
  local list, err = analytics.get_top_paths(repo, TOP_N)
  if err then
    return nil
  end
  local out = {}
  for _, item in ipairs(list) do
    if type(item) == "table" and type(item.path) == "string" then
      out[#out + 1] = {
        path = clip(item.path, MAX_PATH_CHARS),
        title = type(item.title) == "string" and clip(item.title, MAX_TITLE_CHARS) or nil,
        count = count_of(item.count),
        uniques = count_of(item.uniques),
      }
    end
  end
  return out
end

---Build the digest of one repository from the stored history.
---
---Every field is copied by name from analytics' own results: the payload is a
---whitelist, so nothing else in the configuration (a token, a path) can end up
---in it.
---@param repo string "owner/name"
---@return GHStats.Digest? digest
---@return string? err # "no history" is not an error worth a warning, callers may skip it
function M.build(repo)
  if type(repo) ~= "string" or repo == "" then
    return nil, "repository required"
  end

  local views, views_err = clean_daily(repo, "views")
  if not views then
    return nil, views_err
  end
  local clones, clones_err = clean_daily(repo, "clones")
  if not clones then
    return nil, clones_err
  end

  local referrers = referrer_list(repo)
  local paths = path_list(repo)
  local fetched = newest_fetch(repo)

  if not fetched and next(views) == nil and next(clones) == nil and not referrers and not paths then
    return nil, "no history"
  end

  local first, last
  for _, daily in ipairs({ views, clones }) do
    for date in pairs(daily) do
      first = (not first or date < first) and date or first
      last = (not last or date > last) and date or last
    end
  end

  local keep = daily_days()
  return {
    schema = M.SCHEMA,
    repo = repo,
    generated = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    fetched = fetched,
    span = first and { from = first, to = last } or nil,
    views = metric_block(views),
    clones = metric_block(clones),
    daily = { views = daily_series(views, keep), clones = daily_series(clones, keep) },
    referrers = referrers,
    paths = paths,
  }
end

---@internal
---Equal apart from `generated` -- the timestamp must not turn an identical
---digest into a "change", or every fetch would touch every file's mtime, which
---is what a reader's cache keys on.
---@param a table
---@param b table
---@return boolean
local function same_content(a, b)
  local left, right = vim.deepcopy(a), vim.deepcopy(b)
  left.generated, right.generated = nil, nil
  return vim.deep_equal(left, right)
end

---@internal
---Write `payload` to `path` (atomically, via `lib.nvim.fs.json`) unless the
---file already holds the same content.
---@param path string
---@param payload table
---@param ignore_generated boolean
---@return "written"|"unchanged"|"error" outcome
---@return string? err
local function write_if_changed(path, payload, ignore_generated)
  local existing = fs_json.read(path)
  if type(existing) == "table" then
    local equal = ignore_generated and same_content(existing, payload) or vim.deep_equal(existing, payload)
    if equal then
      return "unchanged", nil
    end
  end
  local ok, err = fs_json.write(path, payload)
  if not ok then
    return "error", err
  end
  return "written", nil
end

---@internal
---@param path string
---@return boolean
local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

---Write (or refresh) `root.json`: the pointer that names where the digests are
---and which repositories have one.
---
---`repos` lists only repositories whose digest file exists, gathered from the
---previous root, the currently tracked repositories and `extra`; a repository
---that is not listed has no digest (not tracked, or nothing fetched yet).
---Nothing is written until at least one digest exists.
---@param extra? string[] Repositories to consider besides the tracked ones
---@return "written"|"unchanged"|"skipped"|"error" outcome
---@return string? err
function M.write_root(extra)
  local candidates = {}
  local previous = fs_json.read(M.root_path())
  if type(previous) == "table" and type(previous.repos) == "table" then
    for repo in pairs(previous.repos) do
      candidates[#candidates + 1] = repo
    end
  end
  vim.list_extend(candidates, config.get_repos())
  vim.list_extend(candidates, extra or {})

  local repos, any = {}, false
  for _, repo in ipairs(candidates) do
    if type(repo) == "string" and repos[repo] == nil and is_file(M.digest_file(repo)) then
      repos[repo] = M.file_stem(repo)
      any = true
    end
  end
  if not any then
    return "skipped", nil
  end

  local data_dir = config.get_storage_root()
  local payload = {
    schema = M.SCHEMA,
    digest_dir = M.digest_dir(),
    data_dir = data_dir and slashes(data_dir) or nil,
    repos = repos,
  }
  return write_if_changed(M.root_path(), payload, false)
end

---Build and write the digests of `repos`, then refresh `root.json`.
---
---A repository whose digest is unchanged is left alone. A repository with no
---history is skipped, not an error. One repository failing never stops the
---others.
---@param repos string[]
---@param opts? { skip_root?: boolean }  `skip_root`: leave `root.json` and `last_result` to the caller (`write_later` writes slice by slice)
---@return GHStats.Digest.WriteResult
function M.write(repos, opts)
  ---@type GHStats.Digest.WriteResult
  local result = { written = {}, unchanged = {}, skipped = {}, errors = {} }

  for _, repo in ipairs(repos or {}) do
    local payload, build_err = M.build(repo)
    if not payload then
      if build_err == "no history" then
        result.skipped[#result.skipped + 1] = repo
      else
        result.errors[repo] = build_err or "unknown error"
      end
    else
      local outcome, err = write_if_changed(M.digest_file(repo), payload, true)
      if outcome == "error" then
        result.errors[repo] = err or "unknown error"
      else
        local bucket = outcome == "written" and result.written or result.unchanged
        bucket[#bucket + 1] = repo
      end
    end
  end

  save_memo()
  if opts and opts.skip_root then
    return result
  end

  local _, root_err = M.write_root(repos)
  if root_err then
    result.errors["root.json"] = root_err
  end

  M.last_result = result
  return result
end

---Rebuild every tracked repository's digest.
---@return GHStats.Digest.WriteResult
function M.write_all()
  return M.write(config.get_repos())
end

---Whether any tracked repository's digest is missing or was built from older
---history than the history now on disk.
---
---The case this exists for: the history is synced between two machines, this
---machine's digest is not. A fetch on the other one makes this one skip its own
---for the interval, so nothing here would rebuild the digest -- it would stay
---behind although the data is new. Cheap on purpose: while nothing changed it is
---one `stat` per history directory and per digest file; a directory is listed and
---a digest decoded only after it changed, and what was learnt survives the
---session (`M.memo_path()`).
---@return boolean stale
---@return string? repo # The first repository found out of date
function M.stale()
  local stale, out_of_date = false, nil
  local dir = M.digest_dir() .. "/digest/"
  for _, repo in ipairs(config.get_repos()) do
    local fetched = newest_fetch(repo)
    if fetched and digest_fetched(repo, dir .. M.file_stem(repo) .. ".json") ~= fetched then
      stale, out_of_date = true, repo
      break
    end
  end
  save_memo()
  return stale, out_of_date
end

---Rebuild everything if the digests are out of date; otherwise only make sure
---`root.json` is in place. Meant for the start of the background cycle.
---@return GHStats.Digest.WriteResult?
function M.refresh_if_stale()
  if M.stale() then
    return M.write_all()
  end
  M.write_root()
  return nil
end

---Write the digests of `repos` on later turns of the event loop, and never raise.
---@description
--- What the fetch paths call. A digest failure must not fail or slow a fetch,
--- so this is deferred out of the fetch's own callback and wrapped in `pcall`;
--- what went wrong is kept in `M.last_result` / `M.last_error` for
--- `:GithubStats debug`, not notified. Building a digest reads a repository's
--- whole history, so the work is cut into slices: one repository per loop turn
--- (the 836 ms the editor thread used to lose in one go, measured by the
--- telemetry of 2026-11-01), then `root.json`.
---@param repos string[]
---@return nil
function M.write_later(repos)
  if #repos == 0 then
    return
  end
  ---@type GHStats.Digest.WriteResult
  local result = { written = {}, unchanged = {}, skipped = {}, errors = {} }
  local failure ---@type string?
  local index = 0

  local function step()
    index = index + 1
    if index > #repos then
      local ok, err = pcall(function()
        local _, root_err = M.write_root(repos)
        if root_err then
          result.errors["root.json"] = root_err
        end
      end)
      if not ok then
        failure = failure or tostring(err)
      end
      M.last_result = result
      M.last_error = failure
      return
    end
    local ok, part = pcall(M.write, { repos[index] }, { skip_root = true })
    if ok and type(part) == "table" then
      for _, key in ipairs({ "written", "unchanged", "skipped" }) do
        vim.list_extend(result[key], part[key])
      end
      result.errors = vim.tbl_extend("force", result.errors, part.errors)
    elseif not ok then
      failure = failure or tostring(part)
    end
    vim.schedule(step)
  end

  vim.schedule(step)
end

return M

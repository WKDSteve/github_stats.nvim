---@module 'github_stats.cli'
---@brief The commands of `scripts/github_stats.lua`: collect and report without a running editor.
---@description
--- GitHub keeps traffic (clones, views) for 14 days only, so the history is only complete when something
--- collects it regularly -- also on a day no editor is opened. This is that something, for a scheduler or CI:
---
---     nvim --headless -u NONE -l scripts/github_stats.lua collect [--force] [--format=json]
---     nvim --headless -u NONE -l scripts/github_stats.lua report [--repos=owner/a,owner/b] [--format=json]
---
--- `collect` runs what one background cycle of the editor runs (discovery from `watch_users`, the fetch with its
--- interval gate, retention, the digests) and waits until all of it is done. `report` prints what the history holds,
--- as the digest contract computes it (`docs/FEATURES/DIGEST.md`); it never touches the network.
---
--- The configuration is the plugin's `config.json` (default: `stdpath("config")/lua/plugins/github-stats`). Options
--- passed to `setup()` in the editor config are not seen here; the few that matter come as flags.
---
--- Exit codes: 0 done, 1 a fetch or digest error (the rest was still collected), 2 usage or configuration, 3 the
--- environment (no `curl`, the run did not finish within `--timeout`).

local M = {}

local USAGE = [[
usage: nvim --headless -u NONE -l scripts/github_stats.lua <command> [options]

commands:
  collect   fetch the traffic of every tracked repository (respects fetch_interval_hours unless --force), run
            retention, write the digests; waits until all of it is done
  report    print the traffic the history holds (7/30/90 complete days, trend), never fetches
  help      this text

options:
  --repos=<owner/name,...>   these repositories instead of the configured ones (and no watch_users discovery)
  --config-dir=<dir>         the folder of config.json (default: stdpath("config")/lua/plugins/github-stats)
  --data-dir=<dir>           the history (default: <config-dir>/data)
  --digest-dir=<dir>         collect: where the digests go (default: stdpath("data")/github_stats.nvim)
                             (with any of the three folder options, root.json -- the pointer other programs
                             follow to the editor's digests -- is left alone)
  --force                    collect: fetch even when fetch_interval_hours has not elapsed
  --timeout=<seconds>        collect: give up after this long (default 600), exit 3
  --format=text|json         default text
  --quiet                    collect: no warnings on stderr (the result and the exit code stay)

exit: 0 done, 1 a fetch or digest error, 2 usage/configuration, 3 environment (curl missing, timeout)]]

---@class GHStats.Cli.Opts
---@field command string
---@field repos? string[]
---@field config_dir? string
---@field data_dir? string
---@field digest_dir? string
---@field force boolean
---@field timeout_s integer
---@field format "text"|"json"
---@field quiet boolean

local FLAGS = {
  ["--force"] = "force",
  ["--quiet"] = "quiet",
}

local VALUES = {
  ["--repos"] = "repos",
  ["--config-dir"] = "config_dir",
  ["--data-dir"] = "data_dir",
  ["--digest-dir"] = "digest_dir",
  ["--timeout"] = "timeout",
  ["--format"] = "format",
}

---@param out file*
---@param text string
local function say(out, text)
  out:write(text, "\n")
end

---Parse the arguments.
---@param argv string[]
---@return GHStats.Cli.Opts|nil opts
---@return string|nil err
function M.parse(argv)
  ---@type GHStats.Cli.Opts
  local opts = { command = "", force = false, timeout_s = 600, format = "text", quiet = false }
  for _, a in ipairs(argv) do
    local key, value = a:match("^(%-%-[%w%-]+)=(.*)$")
    if FLAGS[a] then
      opts[FLAGS[a]] = true
    elseif key and VALUES[key] then
      local name = VALUES[key]
      if value == "" then
        return nil, ("%s needs a value"):format(key)
      end
      if name == "repos" then
        local list = {}
        for repo in value:gmatch("[^,]+") do
          repo = vim.trim(repo)
          if not repo:match("^[%w._-]+/[%w._-]+$") then
            return nil, ("--repos: '%s' is not owner/name"):format(repo)
          end
          list[#list + 1] = repo
        end
        opts.repos = list
      elseif name == "timeout" then
        local n = tonumber(value)
        if not n or n <= 0 or n ~= math.floor(n) then
          return nil, "--timeout needs a whole number of seconds above 0"
        end
        opts.timeout_s = n
      elseif name == "format" then
        if value ~= "text" and value ~= "json" then
          return nil, "--format is text or json"
        end
        opts.format = value
      else
        opts[name] = value
      end
    elseif a:sub(1, 1) == "-" then
      return nil, ("unknown option %s"):format(a)
    elseif opts.command == "" then
      opts.command = a
    else
      return nil, ("unexpected argument %s"):format(a)
    end
  end
  return opts, nil
end

---Load config.json (and the flags that stand in for setup() options).
---@param opts GHStats.Cli.Opts
---@return boolean ok
---@return string|nil err
local function init_config(opts)
  local setup = { config_dir = opts.config_dir, data_dir = opts.data_dir, digest_dir = opts.digest_dir }
  if opts.repos then
    setup.repos = opts.repos
    setup.watch_users = {}
  end
  return require("github_stats.config").init(setup)
end

---@param value any
---@return string
local function json(value)
  return vim.json.encode(value)
end

---A map for JSON: an empty one is `{}`, not `[]`.
---@param t table
---@return table
local function map(t)
  return next(t) ~= nil and t or vim.empty_dict()
end

---@param n integer|nil
---@return string
local function num(n)
  return tostring(n or 0)
end

---@param trend number|nil
---@return string
local function trend_text(trend)
  if type(trend) ~= "number" then
    return "-"
  end
  return ("%+.0f%%"):format(trend)
end

---`report`: the digest of each tracked repository, built from the history (nothing is written).
---@param opts GHStats.Cli.Opts
---@return integer code
local function report(opts)
  local config = require("github_stats.config")
  local digest = require("github_stats.digest")
  local repos = config.get_repos()

  local items, skipped, errors = {}, {}, {}
  for _, repo in ipairs(repos) do
    local payload, err = digest.build(repo)
    if payload then
      items[#items + 1] = payload
    elseif err == "no history" then
      skipped[#skipped + 1] = repo
    else
      errors[repo] = err or "unknown error"
    end
  end

  if opts.format == "json" then
    say(io.stdout, json({ schema = digest.SCHEMA, repos = items, skipped = skipped, errors = map(errors) }))
  else
    say(
      io.stdout,
      ("%-40s %10s %10s %7s %10s %10s %7s"):format(
        "repository",
        "views 7d",
        "views 30d",
        "trend",
        "clones 7d",
        "clones 30d",
        "trend"
      )
    )
    for _, d in ipairs(items) do
      say(
        io.stdout,
        ("%-40s %10s %10s %7s %10s %10s %7s"):format(
          d.repo,
          num(d.views.d7.count),
          num(d.views.d30.count),
          trend_text(d.views.trend),
          num(d.clones.d7.count),
          num(d.clones.d30.count),
          trend_text(d.clones.trend)
        )
      )
    end
    if #skipped > 0 then
      say(io.stdout, ("no history yet: %s"):format(table.concat(skipped, ", ")))
    end
    for repo, err in pairs(errors) do
      say(io.stderr, ("error: %s: %s"):format(repo, err))
    end
  end
  return next(errors) and 1 or 0
end

---Wait until `done()` is true or the timeout passes.
---@param timeout_s integer
---@param done fun(): boolean
---@return boolean finished
local function wait(timeout_s, done)
  return vim.wait(timeout_s * 1000, done, 50) == true
end

---`collect`: one background cycle, run to its end.
---@param opts GHStats.Cli.Opts
---@return integer code
local function collect(opts)
  local config = require("github_stats.config")

  if vim.fn.executable("curl") ~= 1 then
    say(io.stderr, "error: curl not found on PATH (every GitHub request goes through it)")
    return 3
  end
  local token, token_err = config.get_token()
  if not token then
    say(io.stderr, ("error: no GitHub token: %s (the traffic API needs push access)"):format(token_err or "not set"))
    return 2
  end

  -- The editor shows these as notifications; here warnings and errors go to stderr, the rest is the result below.
  ---@diagnostic disable-next-line: duplicate-set-field
  config.notify = function(message, level)
    if not opts.quiet and (level == "warn" or level == "error") then
      say(io.stderr, message)
    end
  end

  local discovery_errors = {}
  local cfg = config.get()
  local users = (not opts.repos and cfg and cfg.watch_users) or {}
  if #users > 0 then
    local discovered = false
    require("github_stats.repo_discovery").discover(users, function(names, errors)
      config.set_discovered_repos(names)
      discovery_errors = errors or {}
      discovered = true
    end)
    if not wait(opts.timeout_s, function()
      return discovered
    end) then
      say(io.stderr, ("error: discovering the repositories of watch_users took longer than %ds"):format(opts.timeout_s))
      return 3
    end
    for user, err in pairs(discovery_errors) do
      config.notify(("[github-stats] Failed to discover repos for '%s': %s"):format(user, err), "warn")
    end
  end

  -- root.json sits at one fixed place and names where the digests are, for every reader. A run on other folders
  -- than the editor's (a trial, a second history) writes its digests but must not repoint it.
  local own_folders = opts.config_dir ~= nil or opts.data_dir ~= nil or opts.digest_dir ~= nil

  -- First what every background cycle does first: the history is synced between machines, the digest is not, so a
  -- fetch on the other machine leaves this one's digests behind while the interval keeps this run from fetching.
  local digest = require("github_stats.digest")
  local refresh_ok, refreshed = pcall(function()
    if not digest.stale() then
      return nil
    end
    return digest.write(config.get_repos(), { skip_root = own_folders })
  end)
  if not refresh_ok then
    config.notify(("[github-stats] Rebuilding the stale digests failed: %s"):format(tostring(refreshed)), "warn")
  end

  ---@type GHStats.FetchSettled|nil
  local settled
  require("github_stats.fetcher").fetch_all(opts.force, nil, {
    background = true,
    skip_root = own_folders,
    on_settled = function(s)
      settled = s
    end,
  })
  if not wait(opts.timeout_s, function()
    return settled ~= nil
  end) then
    say(io.stderr, ("error: the fetch did not finish within %ds"):format(opts.timeout_s))
    return 3
  end
  ---@cast settled GHStats.FetchSettled

  local summary = settled.summary
  local digest_errors = settled.digest and settled.digest.errors or {}
  local failed = not refresh_ok
    or next(summary.errors) ~= nil
    or next(digest_errors) ~= nil
    or settled.digest_error ~= nil
    or next(discovery_errors) ~= nil

  if opts.format == "json" then
    say(
      io.stdout,
      json({
        fetched = #summary.success,
        success = summary.success,
        errors = map(summary.errors),
        discovery_errors = map(discovery_errors),
        retention = settled.retention,
        digest = settled.digest,
        digest_error = settled.digest_error,
        root_written = settled.digest ~= nil and not own_folders,
        refreshed = refresh_ok and refreshed and refreshed.written or nil,
        timestamp = summary.timestamp,
      })
    )
  else
    if #summary.success == 0 and not next(summary.errors) then
      say(io.stdout, "nothing fetched (fetch_interval_hours has not elapsed; --force fetches anyway)")
    else
      say(io.stdout, ("fetched %d metrics, %d errors"):format(#summary.success, vim.tbl_count(summary.errors)))
    end
    for key, err in pairs(summary.errors) do
      say(io.stderr, ("error: %s: %s"):format(key, err))
    end
    if refresh_ok and refreshed and #refreshed.written > 0 then
      say(io.stdout, ("stale digests rebuilt: %d"):format(#refreshed.written))
    end
    if settled.retention then
      say(io.stdout, ("retention: archived %d day(s)"):format(settled.retention.archived or 0))
    end
    if settled.digest then
      say(io.stdout, ("digests: %d written, %d unchanged"):format(#settled.digest.written, #settled.digest.unchanged))
      if own_folders then
        say(io.stdout, "root.json left alone (--config-dir, --data-dir or --digest-dir given)")
      end
      for repo, err in pairs(digest_errors) do
        say(io.stderr, ("error: digest %s: %s"):format(repo, err))
      end
    end
    if settled.digest_error then
      say(io.stderr, ("error: digest: %s"):format(settled.digest_error))
    end
  end
  return failed and 1 or 0
end

---Run a command line; returns the exit code.
---@param argv string[]
---@return integer code
function M.run(argv)
  local opts, err = M.parse(argv)
  if not opts then
    say(io.stderr, ("error: %s"):format(err))
    say(io.stderr, USAGE)
    return 2
  end
  if opts.command == "" or opts.command == "help" or opts.command == "--help" then
    say(opts.command == "" and io.stderr or io.stdout, USAGE)
    return opts.command == "" and 2 or 0
  end
  if opts.command ~= "collect" and opts.command ~= "report" then
    say(io.stderr, ("error: unknown command %s"):format(opts.command))
    say(io.stderr, USAGE)
    return 2
  end

  local ok, init_err = init_config(opts)
  if not ok then
    say(io.stderr, ("error: configuration: %s"):format(init_err or "unknown"))
    return 2
  end

  if opts.command == "report" then
    return report(opts)
  end
  return collect(opts)
end

M.USAGE = USAGE

return M

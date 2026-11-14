---@module 'github_stats.health'
---@brief Neovim healthcheck integration
---@description
--- Implements :checkhealth github_stats functionality.
--- Validates configuration, dependencies, and API connectivity.
--- Cross-platform support for Windows, macOS, Linux.

local config = require("github_stats.config")
local cross_executable = require("lib.nvim.cross.executable")

local M = {}

local fn = vim.fn
local health = vim.health
local str_format = string.format
local tbl_concat = table.concat

---@internal
---Check if command exists (cross-platform)
---@param cmd string Command name
---@return boolean # True if command is available
local function command_exists(cmd)
  return cross_executable.exists(cmd)
end

---@internal
---Validate repository name format
---@param repo string Repository identifier
---@return boolean, string? # Valid flag, error message
local function validate_repo_format(repo)
  if type(repo) ~= "string" then
    return false, "Not a string"
  end

  if not repo:match("^[^/]+/[^/]+$") then
    return false, "Must be in 'owner/repo' format"
  end

  return true, nil
end

---@internal
---Check configuration file
---@description
--- Reads back whatever `setup()` already loaded via `config.init(opts)`,
--- rather than calling `config.init()` again here with no arguments: that
--- second, opts-less call used to re-resolve PATHS from scratch (dropping
--- any `config_dir`/`data_dir` override) and only re-applies setup options
--- when `next(opts) ~= nil` -- which is never true for an empty call -- so
--- running `:checkhealth` silently reverted the session to config.json-over-
--- defaults for its remaining lifetime.
---@return boolean, string # Success flag, message
local function check_config()
  local cfg = config.get()
  if not cfg then
    return false, "Configuration not loaded -- call require('github_stats').setup() first"
  end

  local has_static_repos = #(cfg.repos or {}) > 0
  local has_watch_users = cfg.watch_users and #cfg.watch_users > 0

  -- Check repos: either an explicit list, or usernames to auto-discover from
  if not has_static_repos and not has_watch_users then
    return false, "No repositories configured (set 'repos' or 'watch_users'). Edit config.json or plugin initialization."
  end

  -- Validate each explicitly configured repo (discovered repos are
  -- validated implicitly, since they come straight from the GitHub API)
  for i, repo in ipairs(cfg.repos or {}) do
    local valid, repo_err = validate_repo_format(repo)
    if not valid then
      return false, str_format("Invalid repo[%d] '%s': %s", i, repo, repo_err)
    end
  end

  if has_watch_users then
    return true,
      str_format(
        "Configuration valid (%d explicit repos, watching users: %s)",
        #(cfg.repos or {}),
        table.concat(cfg.watch_users, ", ")
      )
  end

  return true, str_format("Configuration valid (%d repos)", #(cfg.repos or {}))
end

---@internal
---Check token availability
---@return boolean, string # Success flag, message
local function check_token()
  local token, err = config.get_token()
  if not token then
    return false, str_format("Token error: %s", err)
  end

  if #token < 10 then
    return false, "Token appears invalid (too short)"
  end

  return true, str_format("Token available (%d chars, source: %s)", #token, config.get().token_source)
end

---@internal
---Check storage paths
---@return boolean, string # Success flag, message
local function check_storage()
  local storage_root = config.get_storage_root()

  -- Check if path exists
  local stat = vim.uv.fs_stat(storage_root)
  if not stat then
    -- Try to create
    local ok, err = pcall(fn.mkdir, storage_root, "p")
    if not ok then
      return false, str_format("Failed to create storage directory: %s", err)
    end
    return true, str_format("Storage directory created: %s", storage_root)
  end

  if stat.type ~= "directory" then
    return false, str_format("Storage path exists but is not a directory: %s", storage_root)
  end

  return true, str_format("Storage directory accessible: %s", storage_root)
end

---@internal
---Nearest existing ancestor of `path` (the path itself if it exists).
---@param path string
---@return string? existing
---@return table? stat
local function nearest_existing(path)
  local current = path
  while current and current ~= "" do
    local stat = vim.uv.fs_stat(current)
    if stat then
      return current, stat
    end
    local parent = vim.fs.dirname(current)
    if not parent or parent == current then
      break
    end
    current = parent
  end
  return nil, nil
end

---@internal
---Report the digest other programs read (github_stats.digest): the two
---options, whether the directory can be written, whether `root.json` is in
---place and points where the digests are, and whether the digests lag the
---history.
local function check_digest()
  local digest = require("github_stats.digest")
  local cfg = config.get()

  if cfg and cfg.digest_dir ~= nil and (type(cfg.digest_dir) ~= "string" or cfg.digest_dir == "") then
    health.error("digest_dir must be a non-empty string", { "Set digest_dir to a directory path, or remove it" })
  end
  local days = cfg and cfg.digest_daily_days
  if days ~= nil and (type(days) ~= "number" or days < 1) then
    health.error("digest_daily_days must be a number >= 1", { "Set digest_daily_days to e.g. 400" })
  end

  local dir = digest.digest_dir()
  local existing, stat = nearest_existing(dir)
  if not existing or not stat or stat.type ~= "directory" then
    health.error(str_format("Digest directory cannot be created: %s", dir), { "Check digest_dir" })
  elseif not vim.uv.fs_access(existing, "W") then
    health.error(str_format("Digest directory is not writable: %s (checked %s)", dir, existing), { "Check digest_dir" })
  else
    health.ok(str_format("Digest directory writable: %s", dir))
  end

  local root, root_err = require("lib.nvim.fs.json").read(digest.root_path())
  if type(root) ~= "table" then
    if vim.uv.fs_stat(digest.root_path()) then
      health.error(str_format("root.json unreadable: %s", tostring(root_err)), { "Run :GithubStats digest to rewrite it" })
    else
      health.info(str_format("root.json not written yet (%s) -- it appears with the first digest", digest.root_path()))
    end
  elseif root.digest_dir ~= dir then
    health.warn(
      str_format("root.json points to %s but the digest directory is %s", tostring(root.digest_dir), dir),
      { "Run :GithubStats digest to rewrite it" }
    )
  else
    local n = type(root.repos) == "table" and vim.tbl_count(root.repos) or 0
    health.ok(str_format("root.json in place (%d repositories with a digest)", n))
  end

  local ok_stale, stale, repo = pcall(digest.stale)
  if not ok_stale then
    health.warn(str_format("Could not compare the digest with the history: %s", tostring(stale)))
  elseif stale then
    health.warn(
      str_format("Digest is behind the stored history (first: %s)", tostring(repo)),
      { "Run :GithubStats digest (the history is synced between machines, the digest is not)" }
    )
  else
    health.ok("Digest is up to date with the stored history")
  end
end

---@internal
---Check curl availability (cross-platform)
---@return boolean, string # Success flag, message
local function check_curl()
  if not command_exists("curl") then
    return false, "curl not found in PATH"
  end

  -- Argv form, so no shell is involved and no platform branch is needed. The
  -- previous io.popen ran a shell string and therefore had to carry one --
  -- `2>nul` on Windows against `2>&1` elsewhere -- purely to silence stderr
  -- that curl --version does not write in the first place.
  local version_output = vim.fn.system({ "curl", "--version" })
  if vim.v.shell_error ~= 0 then
    return false, "Failed to execute curl --version"
  end

  local version = version_output:match("curl (%d+%.%d+%.%d+)")
  if version then
    return true, str_format("curl available (version %s)", version)
  end

  return true, "curl available (version unknown)"
end

--- lib.nvim commit that added `lib.nvim.net.github`, the client `api.lua` sends every request
--- through (its `max_bytes` handling in net.curl dates from 8e9a608, which is older).
local LIB_NET_GITHUB_SINCE = "ccd30b5 (2026-10-31)"

---@internal
---Whether the installed lib.nvim has `lib.nvim.net.github` and its requests turn `max_bytes`
---into `--max-filesize <n>`.
---
---`api.lua` hands every request to `lib.nvim.net.github` and `api_max_response_bytes` to it as
---`max_bytes`. A lib.nvim older than `LIB_NET_GITHUB_SINCE` has no such module, so no request can
---be sent at all; a client that ignores `max_bytes` would silently drop the response cap
---(fail-open). lib.nvim carries no version number, so this asks the client itself, through the
---same call `api.lua` uses (`request`): `vim.system` is replaced for that one call and only records
---the argv it is handed. Nothing is spawned and the completion callback never runs; `request`
---reaches `vim.system` synchronously (via net.curl's `fetch_raw`), so the real one is back before
---anything else can run.
---@return boolean ok
---@return string message
---@return "warn"|"error"|nil level How to report a failure: `error` when requests cannot work at all.
local function check_curl_max_bytes()
  local has_github, github = pcall(require, "lib.nvim.net.github")
  if not has_github then
    return false,
      str_format(
        "lib.nvim is too old: lib.nvim.net.github is missing, so no GitHub request can be sent (needs lib.nvim %s or newer)",
        LIB_NET_GITHUB_SINCE
      ),
      "error"
  end
  local probe_bytes = "4096"
  local argv
  local real_system = vim.system
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd)
    argv = cmd
    return {}
  end
  local call_ok, call_err = pcall(github.request, "https://probe.invalid/", {
    max_bytes = tonumber(probe_bytes),
  }, function() end)
  vim.system = real_system

  if type(argv) ~= "table" then
    return false,
      str_format("Could not inspect the lib.nvim curl client: %s", call_ok and "no command built" or tostring(call_err)),
      "warn"
  end
  for i, arg in ipairs(argv) do
    if arg == "--max-filesize" and argv[i + 1] == probe_bytes then
      return true, "lib.nvim curl client enforces api_max_response_bytes (max_bytes -> --max-filesize)"
    end
  end
  return false,
    str_format(
      "lib.nvim is too old: net.curl ignores max_bytes, so api_max_response_bytes is NOT enforced (needs lib.nvim %s or newer)",
      LIB_NET_GITHUB_SINCE
    ),
    "warn"
end

---@internal
---Test API connectivity synchronously with timeout
---
---Goes through `lib.nvim.net.curl` (the transport under `lib.nvim.net.github`,
---which `api.lua` uses for every live request) instead of hand-building a curl command: an earlier version
---interpolated the token straight into a shell string executed via
---`fn.system(string)`, which both ran through a shell unnecessarily (a repo
---name in `url` was interpolated right along with it) and put the token in
---the process argv, visible to any other process on the machine for the
---call's lifetime. `bearer_token` in `lib.nvim.net.curl` instead feeds curl
---the header via `-K -` (stdin), never argv.
---@return boolean, string, number # Success flag, message, duration_ms
local function check_api_sync()
  local repos = config.get_repos()
  if #repos == 0 then
    return false, "No repositories to test", 0
  end

  local test_repo = repos[1]
  local token, token_err = config.get_token()

  if not token then
    return false, str_format("Cannot test API: %s", token_err), 0
  end

  local url = str_format("https://api.github.com/repos/%s/traffic/clones", test_repo)
  local curl = require("lib.nvim.net.curl")

  local start_time = vim.uv.hrtime()

  local ok, response = curl.fetch_raw_blocking(url, {
    headers = { Accept = "application/vnd.github+json", ["X-GitHub-Api-Version"] = "2022-11-28" },
    bearer_token = token,
    timeout_ms = 10000,
  })

  local duration_ms = math.floor((vim.uv.hrtime() - start_time) / 1000000)

  if not ok then
    if duration_ms >= 10000 then
      return false, "API test timed out (10s)", duration_ms
    else
      return false, str_format("curl failed: %s", tostring(response)), duration_ms
    end
  end

  ---@cast response Lib.Net.Curl.RawResponse
  local code_num = response.status

  if code_num == 200 then
    -- Verify we got valid JSON
    if response.body and response.body ~= "" then
      local json_ok, _ = pcall(vim.json.decode, response.body)
      if json_ok then
        return true, str_format("API connectivity confirmed (tested %s)", test_repo), duration_ms
      else
        return false, "API returned invalid JSON", duration_ms
      end
    else
      return false, "API returned empty response", duration_ms
    end
  elseif code_num == 401 then
    return false, "API test failed: 401 Unauthorized (check token permissions)", duration_ms
  elseif code_num == 403 then
    return false, "API test failed: 403 Forbidden (rate limit or token issue)", duration_ms
  elseif code_num == 404 then
    return false, str_format("API test failed: 404 Not Found (check repository name: %s)", test_repo), duration_ms
  else
    return false, str_format("API test failed: HTTP %d", code_num), duration_ms
  end
end

---Main health check entry point
function M.check()
  vim.health.start("GitHub Stats Configuration")

  -- Check config
  local config_ok, config_msg = check_config()
  if config_ok then
    health.ok(config_msg)
  else
    health.error(config_msg)
  end

  -- Check token
  local token_ok, token_msg = check_token()
  if token_ok then
    health.ok(token_msg)
  else
    health.error(token_msg, {
      "Set GITHUB_TOKEN environment variable",
      "Or configure token_file in config.json",
      "Get token from: https://github.com/settings/tokens",
    })
  end

  health.start("GitHub Stats Background")

  do
    local cfg = config.get()
    local background_enabled = not cfg or not cfg.background or cfg.background.enabled ~= false
    if background_enabled then
      health.ok("Background fetch enabled (silent; only errors are notified)")
    else
      health.info("Background fetch disabled (background.enabled = false) - manual :GithubStats fetch only")
    end

    if cfg and cfg.watch_users and #cfg.watch_users > 0 then
      health.ok(str_format("Auto-discovering repos for: %s", table.concat(cfg.watch_users, ", ")))
    else
      health.info("No watch_users configured - only explicitly listed repos are tracked")
    end
  end

  health.start("GitHub Stats Dependencies")

  -- ui.nvim: github_stats/init.lua's own module-top-level
  -- `M.dashboard = require("github_stats.dashboard")` pulls in ui.contextmenu
  -- the instant anything does `require("github_stats")`, even before
  -- setup() runs -- no fallback, so a missing ui.nvim breaks the plugin at
  -- load time rather than degrading.
  if pcall(require, "ui.kit") then
    health.ok("ui.nvim found (dashboard note popups, right-click context menu)")
  else
    health.error("ui.nvim not found -- require('github_stats') will fail to load", {
      "Install WKDSteve/ui.nvim.",
    })
  end

  -- Check curl (cross-platform)
  local curl_ok, curl_msg = check_curl()
  if curl_ok then
    health.ok(curl_msg)
  else
    health.error(curl_msg, {
      "Linux/Debian/Ubuntu: sudo apt install curl",
      "macOS: brew install curl",
      "Windows: curl is included since Windows 10 build 1803",
      "Windows (manual): Download from https://curl.se/windows/",
    })
  end

  local cap_ok, cap_msg, cap_level = check_curl_max_bytes()
  if cap_ok then
    health.ok(cap_msg)
  else
    health[cap_level or "warn"](cap_msg, {
      "Update WKDSteve/lib.nvim (e.g. :Lazy update lib.nvim, or move a pinned lockfile entry forward)",
    })
  end

  -- pdfport.nvim: optional, only the PDF export variants need it
  if pcall(require, "pdfport") then
    health.ok("pdfport.nvim found (PDF export of reports)")
  else
    health.info("pdfport.nvim not installed: PDF export is unavailable (optional)")
  end

  health.start("GitHub Stats Storage")

  -- Where the history lives (github_stats.remote)
  local remote = require("github_stats.remote")
  local current = remote.current()
  if current then
    local status = remote.status(current)
    if status == "ready" then
      health.ok(("remote mode: data repository %s, clone in %s"):format(current.repo or "?", current.dir))
    elseif status == "local" then
      health.ok("local mode: this Neovim fetches into its own folder")
    -- Neither state needs the user to act (UI-57): the clone happens by itself, and until the guide has run the
    -- plugin fetches locally.
    elseif status == "clone" then
      health.info(("remote mode: %s is not cloned yet (it is cloned on the next start)"):format(current.repo))
    else
      health.info("remote mode is not set up yet: fetching locally meanwhile (:GithubStats setup)")
    end
  end

  -- Check storage
  local storage_ok, storage_msg = check_storage()
  if storage_ok then
    health.ok(storage_msg)
  else
    health.error(storage_msg)
  end

  health.start("GitHub Stats Digest")
  check_digest()

  health.start("GitHub Stats API Connectivity")

  -- Synchronous API check with timeout
  if config_ok and token_ok and curl_ok then
    health.info("Testing API connection (max 10 seconds)...")

    local api_ok, api_msg, duration_ms = check_api_sync()
    local duration_str = str_format("%.2fs", duration_ms / 1000)

    if api_ok then
      health.ok(str_format("%s (took %s)", api_msg, duration_str))
    else
      health.error(str_format("%s (took %s)", api_msg, duration_str), {
        "Check network connectivity",
        "Verify token has 'repo' permission",
        "Confirm repository name in config.json",
        "Check firewall/proxy settings",
        "Try: :GithubStats debug for detailed diagnostics",
      })
    end
  else
    health.warn("Skipping API test due to previous errors")
  end

  health.start("GitHub Stats Dashboard")

  do
    local cfg = config.get()
    local dashboard_cfg = cfg and cfg.dashboard

    if not dashboard_cfg then
      health.warn("Dashboard configuration not found", {
        "Add dashboard section to config.json",
        "See documentation for default configuration",
      })
    elseif type(dashboard_cfg.enabled) ~= "boolean" then
      health.error("dashboard.enabled must be boolean", { "Set dashboard.enabled to true or false in config.json" })
    elseif not dashboard_cfg.enabled then
      health.info("Dashboard disabled by configuration")
    else
      health.ok("Dashboard enabled")

      -- 0 is the documented off switch, so it cannot be reported as an error
      -- alongside "must be >= 10" -- that combination made the one value the
      -- docs tell you to use fail :checkhealth.
      local refresh = dashboard_cfg.refresh_interval_seconds
      local DEFAULT_DASHBOARD = require("github_stats.config.DEFAULTS").dashboard
      local default_refresh = DEFAULT_DASHBOARD.refresh_interval_seconds
      local default_trend_window = DEFAULT_DASHBOARD.trend_window_days
      if refresh ~= nil and type(refresh) ~= "number" then
        health.error(
          "dashboard.refresh_interval_seconds must be number",
          { "Set dashboard.refresh_interval_seconds to 0 or a number >= 10 in config.json" }
        )
      elseif refresh == 0 then
        health.info("Auto-refresh disabled by configuration")
      elseif refresh ~= nil and refresh < 10 then
        health.error(
          "dashboard.refresh_interval_seconds must be 0 (disabled) or >= 10",
          { "Set dashboard.refresh_interval_seconds to 0 or a number >= 10 in config.json" }
        )
      else
        health.ok(str_format("Auto-refresh: every %d seconds", refresh or default_refresh))
      end

      local trend_window = dashboard_cfg.trend_window_days
      if trend_window ~= nil and (type(trend_window) ~= "number" or trend_window < 1) then
        health.error(
          "dashboard.trend_window_days must be a number >= 1",
          { "Set dashboard.trend_window_days to a number >= 1 in config.json" }
        )
      else
        health.ok(
          str_format(
            "Trend window: last %d day(s) vs the %d before",
            trend_window or default_trend_window,
            trend_window or default_trend_window
          )
        )
      end

      if dashboard_cfg.keybindings == nil then
        health.error("Dashboard keybindings not configured", { "Add a dashboard.keybindings table to config.json" })
      elseif type(dashboard_cfg.keybindings) ~= "table" then
        health.error("dashboard.keybindings must be table", { "Set dashboard.keybindings to a table in config.json" })
      else
        local essential_keys = { "navigate_down", "navigate_up", "quit" }
        local missing_keys = {}

        for _, key in ipairs(essential_keys) do
          if not dashboard_cfg.keybindings[key] then
            table.insert(missing_keys, key)
          end
        end

        if #missing_keys > 0 then
          health.warn(
            str_format("Missing keybindings: %s", tbl_concat(missing_keys, ", ")),
            { "Add missing keybindings to dashboard.keybindings in config" }
          )
        else
          health.ok("All essential keybindings configured")
        end
      end
    end
  end

  require("lib.nvim.bindings.usercmd.composer").checkhealth("GithubStats")
end

return M

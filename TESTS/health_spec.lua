---@diagnostic disable: undefined-global

-- Specs for github_stats.health -- the :checkhealth report.
--
-- `vim.health` is replaced by a recorder, so the report is read back as data
-- instead of as terminal output, and the config module is replaced wholesale
-- for deterministic get()/get_repos()/get_token() responses and a storage
-- root under tmp_dir, independent of whatever setup() a real session ran.
-- The API probe goes through a stubbed `lib.nvim.net.curl`, so no request
-- leaves the machine here either.

describe("health", function()
  local health_mod
  local tmp_dir
  local report
  local real_health, real_curl, real_config, real_health_mod
  local real_modules
  local cfg, token, token_err
  local curl_responder

  ---Every message of the given kind, in order.
  ---@param kind "ok"|"info"|"warn"|"error"
  ---@return string[]
  local function messages(kind)
    local out = {}
    for _, entry in ipairs(report) do
      if entry.kind == kind then
        out[#out + 1] = entry.message
      end
    end
    return out
  end

  ---Whether any message of `kind` contains `needle`.
  ---@param kind "ok"|"info"|"warn"|"error"
  ---@param needle string
  ---@return boolean
  local function reported(kind, needle)
    for _, message in ipairs(messages(kind)) do
      if message:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  before_each(function()
    report = {}
    real_modules = {}
    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    token, token_err = "ghp_0123456789abcdef", nil
    cfg = {
      repos = { "user/alpha" },
      watch_users = {},
      token_source = "env",
      background = { enabled = true },
      dashboard = {
        enabled = true,
        refresh_interval_seconds = 300,
        trend_window_days = 7,
        keybindings = { navigate_down = "j", navigate_up = "k", quit = "q" },
      },
    }
    curl_responder = function()
      return true, { status = 200, body = '{"count":1}' }
    end

    real_health = vim.health
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.health = {
      start = function(name)
        report[#report + 1] = { kind = "start", message = name }
      end,
      ok = function(message)
        report[#report + 1] = { kind = "ok", message = message }
      end,
      info = function(message)
        report[#report + 1] = { kind = "info", message = message }
      end,
      warn = function(message)
        report[#report + 1] = { kind = "warn", message = message }
      end,
      error = function(message)
        report[#report + 1] = { kind = "error", message = message }
      end,
    }

    real_curl = package.loaded["lib.nvim.net.curl"]
    package.loaded["lib.nvim.net.curl"] = {
      fetch_raw_blocking = function(url, opts)
        return curl_responder(url, opts)
      end,
    }

    real_config = package.loaded["github_stats.config"]
    package.loaded["github_stats.config"] = {
      get = function()
        return cfg
      end,
      get_repos = function()
        return cfg and cfg.repos or {}
      end,
      get_token = function()
        -- Mirrors the real module: with no loaded config there is no token
        -- either, which is what keeps check_token() off the nil config.
        if not cfg then
          return nil, "Configuration not loaded"
        end
        return token, token_err
      end,
      get_storage_root = function()
        return tmp_dir .. "/data"
      end,
      notify = function() end,
    }

    -- The digest section reads through github_stats.digest and .storage; both
    -- capture the config module at load, so they are loaded fresh here, under
    -- the stub above, and put back afterwards.
    for _, name in ipairs({ "github_stats.digest", "github_stats.storage", "github_stats.analytics" }) do
      real_modules[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    cfg.digest_dir = tmp_dir .. "/digests"
    require("github_stats.digest").default_dir = function()
      return tmp_dir .. "/default"
    end

    -- net.github captures net.curl at load: loaded fresh, it sits on the stub above (or on
    -- whatever client a case puts there before calling check()).
    real_modules["lib.nvim.net.github"] = package.loaded["lib.nvim.net.github"]
    package.loaded["lib.nvim.net.github"] = nil

    real_health_mod = package.loaded["github_stats.health"]
    package.loaded["github_stats.health"] = nil
    health_mod = require("github_stats.health")
  end)

  after_each(function()
    vim.health = real_health
    package.loaded["lib.nvim.net.curl"] = real_curl
    package.loaded["github_stats.config"] = real_config
    package.loaded["github_stats.health"] = real_health_mod
    -- Never leave the copy bound to this file's curl stub behind (pairs skips a nil original).
    package.loaded["lib.nvim.net.github"] = nil
    for name, module in pairs(real_modules) do
      package.loaded[name] = module
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("configuration", function()
    it("reports a healthy configuration", function()
      health_mod.check()

      assert.is_true(reported("ok", "Configuration valid (1 repos)"))
    end)

    -- LUA-87: check_config() must read back whatever setup() already loaded
    -- rather than calling config.init() again with no arguments -- that used
    -- to re-resolve PATHS from scratch and silently drop setup()'s opts, so
    -- there is no longer an init_ok/init_err path here for it to report.
    it("reports a config that loaded as nil", function()
      cfg = nil

      health_mod.check()

      assert.is_true(reported("error", "Configuration not loaded"))
      assert.is_true(reported("error", "Token error: Configuration not loaded"))
      assert.is_true(reported("warn", "Skipping API test due to previous errors"))
    end)

    it("insists on repos or watch_users", function()
      cfg.repos = {}

      health_mod.check()

      -- Not an error: the default list is empty, nothing is broken until the user chooses (conformance K6).
      assert.is_true(reported("warn", "No repositories configured yet"))
      assert.is_false(reported("error", "No repositories configured"))
    end)

    it("accepts watch_users alone, and names the users", function()
      cfg.repos = {}
      cfg.watch_users = { "acme", "globex" }

      health_mod.check()

      assert.is_true(reported("ok", "watching users: acme, globex"))
      assert.is_true(reported("ok", "Auto-discovering repos for: acme, globex"))
    end)

    it("rejects a repo that is not in owner/repo form", function()
      cfg.repos = { "user/alpha", "just-a-name" }

      health_mod.check()

      assert.is_true(reported("error", "Invalid repo[2] 'just-a-name': Must be in 'owner/repo' format"))
    end)

    it("says so when no users are watched", function()
      health_mod.check()

      assert.is_true(reported("info", "No watch_users configured"))
    end)
  end)

  describe("token", function()
    it("reports length and source, never the token itself", function()
      health_mod.check()

      assert.is_true(reported("ok", "Token available (20 chars, source: env)"))
      assert.is_false(reported("ok", token))
    end)

    it("reports a missing token", function()
      token, token_err = nil, "Environment variable GITHUB_TOKEN not set or empty"

      health_mod.check()

      assert.is_true(reported("error", "Token error: Environment variable GITHUB_TOKEN not set"))
    end)

    it("rejects an implausibly short token", function()
      token, token_err = "abc", nil

      health_mod.check()

      assert.is_true(reported("error", "Token appears invalid (too short)"))
    end)
  end)

  describe("remote mode", function()
    local real_remote

    before_each(function()
      real_remote = package.loaded["github_stats.remote"]
      package.loaded["github_stats.remote"] = {
        active = function()
          return true
        end,
        current = function()
          return { mode = "remote", repo = "me/data", dir = tmp_dir .. "/vault", pull_interval_minutes = 60 }
        end,
        status = function()
          return "ready"
        end,
        COLLECT_REF = "collect-2026.11.14",
        workflow_outdated = function()
          return true, "main"
        end,
      }
      package.loaded["github_stats.health"] = nil
      health_mod = require("github_stats.health")
    end)

    after_each(function()
      package.loaded["github_stats.remote"] = real_remote
    end)

    it("needs no token, no curl and no API probe on this machine: info, never an error", function()
      token, token_err = nil, "Environment variable GITHUB_TOKEN not set or empty"
      curl_responder = function()
        error("remote mode must not probe the API")
      end

      health_mod.check()

      assert.is_true(reported("info", "not needed in remote mode"))
      assert.is_false(reported("error", "Token error"))
      assert.is_true(reported("info", "Skipped in remote mode"))
      assert.is_true(reported("ok", "pulls the data repository every 60 min"))
      assert.is_true(reported("ok", "remote mode: data repository me/data"))
      -- an older pin still collects: info, not warn
      assert.is_true(reported("info", "its workflow runs github_stats.nvim at main"))
    end)
  end)

  describe("background", function()
    it("reports the cycle as enabled by default", function()
      health_mod.check()

      assert.is_true(reported("ok", "Background fetch enabled"))
    end)

    it("reports it as disabled when switched off", function()
      cfg.background = { enabled = false }

      health_mod.check()

      assert.is_true(reported("info", "Background fetch disabled"))
    end)
  end)

  describe("storage", function()
    it("creates the storage directory when it is missing", function()
      health_mod.check()

      assert.is_true(reported("ok", "Storage directory created"))
      assert.equals(1, vim.fn.isdirectory(tmp_dir .. "/data"))
    end)

    it("accepts an existing storage directory", function()
      vim.fn.mkdir(tmp_dir .. "/data", "p")

      health_mod.check()

      assert.is_true(reported("ok", "Storage directory accessible"))
    end)

    it("rejects a storage path that is a file", function()
      vim.fn.mkdir(tmp_dir, "p")
      vim.fn.writefile({ "not a directory" }, tmp_dir .. "/data")

      health_mod.check()

      assert.is_true(reported("error", "Storage path exists but is not a directory"))
    end)
  end)

  describe("digest", function()
    local function seed_history()
      local dir = tmp_dir .. "/data/user_alpha/views"
      vim.fn.mkdir(dir, "p")
      require("lib.nvim.fs.json").write(dir .. "/2026-01-05T12-00-00.json", {
        timestamp = "2026-01-05T12:00:00Z",
        data = { views = {} },
      })
      require("github_stats.storage").invalidate()
    end

    it("reports a digest directory that can be written", function()
      health_mod.check()

      assert.is_true(reported("ok", "Digest directory writable: "))
    end)

    it("reports one that cannot be created", function()
      vim.fn.mkdir(tmp_dir, "p")
      vim.fn.writefile({ "a file" }, tmp_dir .. "/blocker")
      cfg.digest_dir = tmp_dir .. "/blocker/sub"

      health_mod.check()

      assert.is_true(reported("error", "Digest directory cannot be created"))
    end)

    it("rejects nonsense options", function()
      cfg.digest_dir = ""
      cfg.digest_daily_days = 0

      health_mod.check()

      assert.is_true(reported("error", "digest_dir must be a non-empty string"))
      assert.is_true(reported("error", "digest_daily_days must be a number >= 1"))
    end)

    it("says root.json is not there yet rather than failing", function()
      health_mod.check()

      assert.is_true(reported("info", "root.json not written yet"))
      assert.is_false(#messages("error") > 0 and reported("error", "root.json"))
    end)

    it("accepts a root.json that points at the digest directory", function()
      require("lib.nvim.fs.json").write(tmp_dir .. "/default/root.json", {
        schema = 1,
        digest_dir = (tmp_dir .. "/digests"):gsub("\\", "/"),
        repos = { ["user/alpha"] = "user_alpha" },
      })

      health_mod.check()

      assert.is_true(reported("ok", "root.json in place (1 repositories with a digest)"))
    end)

    it("warns about a root.json that points elsewhere", function()
      require("lib.nvim.fs.json").write(tmp_dir .. "/default/root.json", {
        schema = 1,
        digest_dir = tmp_dir .. "/elsewhere",
        repos = { ["user/alpha"] = "user_alpha" },
      })

      health_mod.check()

      assert.is_true(reported("warn", "root.json points to "))
    end)

    it("reports an unreadable root.json as an error", function()
      vim.fn.mkdir(tmp_dir .. "/default", "p")
      vim.fn.writefile({ "{ not json" }, tmp_dir .. "/default/root.json")

      health_mod.check()

      assert.is_true(reported("error", "root.json unreadable"))
    end)

    it("is content while the digest is up to date", function()
      health_mod.check()

      assert.is_true(reported("ok", "Digest is up to date with the stored history"))
    end)

    it("warns when the stored history is newer than the digest", function()
      seed_history()

      health_mod.check()

      assert.is_true(reported("warn", "Digest is behind the stored history (first: user/alpha)"))
    end)
  end)

  describe("dependencies", function()
    it("finds ui.nvim, which the plugin cannot load without", function()
      health_mod.check()

      assert.is_true(reported("ok", "ui.nvim found"))
    end)

    it("names the curl version it found", function()
      health_mod.check()

      -- `curl --version` is a local subprocess, not a request; the version
      -- string itself is whatever the machine has.
      assert.is_true(reported("ok", "curl available"))
    end)

    it("reports curl missing from PATH", function()
      local cross = require("lib.nvim.cross.executable")
      local real_exists = cross.exists
      ---@diagnostic disable-next-line: duplicate-set-field
      cross.exists = function(cmd)
        if cmd == "curl" then
          return false
        end
        return real_exists(cmd)
      end

      health_mod.check()

      cross.exists = real_exists
      assert.is_true(reported("error", "curl not found in PATH"))
    end)

    describe("lib.nvim response cap (max_bytes)", function()
      ---The real lib.nvim.net.curl, but with the stubbed fetch_raw_blocking of before_each on top,
      ---so the API probe still sends nothing.
      local function real_client_with_stubbed_probe()
        package.loaded["lib.nvim.net.curl"] = nil
        local real = require("lib.nvim.net.curl")
        package.loaded["lib.nvim.net.curl"] = setmetatable({
          fetch_raw_blocking = function(url, opts)
            return curl_responder(url, opts)
          end,
        }, { __index = real })
      end

      it("confirms that the installed lib.nvim turns max_bytes into --max-filesize", function()
        real_client_with_stubbed_probe()
        local system_before = vim.system

        health_mod.check()

        assert.is_true(reported("ok", "lib.nvim curl client enforces api_max_response_bytes"))
        assert.is_false(reported("warn", "lib.nvim is too old"))
        assert.equals(system_before, vim.system, "the probe must put vim.system back")
      end)

      it("warns, naming the minimum lib.nvim, when the client ignores max_bytes", function()
        -- A client that builds the argv without ever looking at max_bytes.
        package.loaded["lib.nvim.net.curl"] = {
          fetch_raw_blocking = function(url, opts)
            return curl_responder(url, opts)
          end,
          fetch_raw = function(url, _, cb)
            vim.system({ "curl", "-sS", "-i", "-X", "GET", url }, { text = true }, cb)
          end,
        }
        local system_before = vim.system

        health_mod.check()

        assert.is_true(reported("warn", "lib.nvim is too old: net.curl ignores max_bytes"))
        assert.is_true(reported("warn", "ccd30b5"))
        assert.is_false(reported("ok", "lib.nvim curl client enforces"))
        assert.equals(system_before, vim.system, "the probe must put vim.system back")
      end)

      it("reports an error, naming the minimum lib.nvim, when lib.nvim.net.github is missing", function()
        -- What a lib.nvim before ccd30b5 does: the module api.lua sends every request through
        -- does not exist. package.preload is consulted before any searcher, so this stands in
        -- for the missing file.
        package.preload["lib.nvim.net.github"] = function()
          error("module 'lib.nvim.net.github' not found")
        end
        local ok, err = pcall(health_mod.check)
        package.preload["lib.nvim.net.github"] = nil
        assert.is_true(ok, tostring(err))

        assert.is_true(reported("error", "lib.nvim is too old: lib.nvim.net.github is missing"))
        assert.is_true(reported("error", "ccd30b5"))
        assert.is_false(reported("ok", "lib.nvim curl client enforces"))
      end)

      it("warns instead of failing when the client cannot be inspected", function()
        -- before_each's stub has no fetch_raw at all.
        health_mod.check()

        assert.is_true(reported("warn", "Could not inspect the lib.nvim curl client"))
        assert.is_true(reported("ok", "API connectivity confirmed"))
      end)
    end)
  end)

  describe("API connectivity", function()
    it("confirms a 200 with a decodable body", function()
      health_mod.check()

      assert.is_true(reported("ok", "API connectivity confirmed (tested user/alpha)"))
    end)

    it("rejects a 200 whose body is not JSON", function()
      curl_responder = function()
        return true, { status = 200, body = "<html>nope</html>" }
      end

      health_mod.check()

      assert.is_true(reported("error", "API returned invalid JSON"))
    end)

    it("rejects a 200 with an empty body", function()
      curl_responder = function()
        return true, { status = 200, body = "" }
      end

      health_mod.check()

      assert.is_true(reported("error", "API returned empty response"))
    end)

    it("names the well-known failure codes", function()
      local expected = {
        [401] = "401 Unauthorized",
        [403] = "403 Forbidden",
        [404] = "404 Not Found",
        [500] = "HTTP 500",
      }

      for status, needle in pairs(expected) do
        report = {}
        curl_responder = function()
          return true, { status = status, body = "" }
        end

        health_mod.check()

        assert.is_true(reported("error", needle), "no report for status " .. status)
      end
    end)

    it("reports a curl-level failure", function()
      curl_responder = function()
        return false, "could not resolve host"
      end

      health_mod.check()

      assert.is_true(reported("error", "curl failed: could not resolve host"))
    end)

    it("skips the probe entirely when an earlier check failed", function()
      token, token_err = nil, "no token"
      curl_responder = function()
        error("the API must not be probed without a token")
      end

      health_mod.check()

      assert.is_true(reported("warn", "Skipping API test due to previous errors"))
    end)
  end)

  describe("dashboard section", function()
    it("reports the refresh interval and trend window", function()
      health_mod.check()

      assert.is_true(reported("ok", "Dashboard enabled"))
      assert.is_true(reported("ok", "Auto-refresh: every 300 seconds"))
      assert.is_true(reported("ok", "Trend window: last 7 day(s) vs the 7 before"))
    end)

    it("warns when the dashboard section is missing altogether", function()
      cfg.dashboard = nil

      health_mod.check()

      assert.is_true(reported("warn", "Dashboard configuration not found"))
    end)

    it("insists that enabled is a boolean", function()
      cfg.dashboard.enabled = "yes"

      health_mod.check()

      assert.is_true(reported("error", "dashboard.enabled must be boolean"))
    end)

    it("says so when the dashboard is switched off", function()
      cfg.dashboard.enabled = false

      health_mod.check()

      assert.is_true(reported("info", "Dashboard disabled by configuration"))
    end)

    it("treats a refresh interval of 0 as the documented off switch, not an error", function()
      cfg.dashboard.refresh_interval_seconds = 0

      health_mod.check()

      assert.is_true(reported("info", "Auto-refresh disabled by configuration"))
      assert.is_false(reported("error", "refresh_interval_seconds"))
    end)

    it("rejects a refresh interval below 10 that is not 0", function()
      cfg.dashboard.refresh_interval_seconds = 5

      health_mod.check()

      assert.is_true(reported("error", "must be 0 (disabled) or >= 10"))
    end)

    it("rejects a non-numeric refresh interval", function()
      cfg.dashboard.refresh_interval_seconds = "often"

      health_mod.check()

      assert.is_true(reported("error", "dashboard.refresh_interval_seconds must be number"))
    end)

    it("falls back to the shipped default when the interval is unset", function()
      cfg.dashboard.refresh_interval_seconds = nil
      local default = require("github_stats.config.DEFAULTS").dashboard.refresh_interval_seconds

      health_mod.check()

      assert.is_true(reported("ok", string.format("Auto-refresh: every %d seconds", default)))
    end)

    it("rejects a trend window below one day", function()
      cfg.dashboard.trend_window_days = 0

      health_mod.check()

      assert.is_true(reported("error", "dashboard.trend_window_days must be a number >= 1"))
    end)

    it("insists on a keybindings table", function()
      cfg.dashboard.keybindings = nil
      health_mod.check()
      assert.is_true(reported("error", "Dashboard keybindings not configured"))

      report = {}
      cfg.dashboard.keybindings = "j/k"
      health_mod.check()
      assert.is_true(reported("error", "dashboard.keybindings must be table"))
    end)

    it("names the essential keybindings that are missing", function()
      cfg.dashboard.keybindings = { navigate_down = "j" }

      health_mod.check()

      assert.is_true(reported("warn", "Missing keybindings: navigate_up, quit"))
    end)

    it("is happy once all essential keybindings exist", function()
      health_mod.check()

      assert.is_true(reported("ok", "All essential keybindings configured"))
    end)
  end)
end)

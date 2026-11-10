---@diagnostic disable: undefined-global

-- Specs for github_stats.fetcher -- the orchestration layer between the API
-- client and storage.
--
-- `github_stats.api` is replaced in package.loaded before fetcher is required,
-- so no request leaves the machine; what is exercised here is fetcher's own
-- behaviour: the fetch-interval gate and its last_fetch.json bookkeeping, the
-- per-repo fan-out, the success/error summary, and which of its notifications
-- a silent background cycle is allowed to emit.

describe("fetcher", function()
  local fetcher, config, storage
  local tmp_dir
  local real_api
  local api_calls
  local api_responder
  local notices

  ---@param pred fun(): boolean
  local function wait_for(pred)
    vim.wait(2000, pred, 5)
  end

  ---@param kind? string only count notifications whose message contains this
  ---@return integer
  local function notice_count(kind)
    if not kind then
      return #notices
    end
    local n = 0
    for _, entry in ipairs(notices) do
      if entry.message:find(kind, 1, true) then
        n = n + 1
      end
    end
    return n
  end

  ---Give `repos` (default: the two of the default config) stored data, so that they count as
  ---"already fetched" for the interval gate.
  ---@param repos? string[]
  local function seed_data(repos)
    for _, repo in ipairs(repos or { "owner/alpha", "owner/beta" }) do
      assert.is_true((storage.write_metric(repo, "clones", { count = 1 })))
    end
  end

  before_each(function()
    api_calls = {}
    -- Default: every metric comes back with a plausible traffic payload.
    api_responder = function()
      return { count = 1, uniques = 1, clones = {} }, nil
    end

    real_api = package.loaded["github_stats.api"]
    package.loaded["github_stats.api"] = {
      fetch_metric_async = function(repo, metric, callback)
        api_calls[#api_calls + 1] = { repo = repo, metric = metric }
        vim.schedule(function()
          callback(api_responder(repo, metric))
        end)
      end,
    }

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.retention",
      "github_stats.fetcher",
    }) do
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")

    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" } })

    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    storage = require("github_stats.storage")
    fetcher = require("github_stats.fetcher")
  end)

  after_each(function()
    package.loaded["github_stats.api"] = real_api
    for _, name in ipairs({ "github_stats.config", "github_stats.fetcher", "github_stats.storage" }) do
      package.loaded[name] = nil
    end
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("fetch_repo", function()
    it("asks for all four metrics and stores each successful one", function()
      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      assert.equals(4, #api_calls)
      assert.equals(4, #success)
      assert.equals(0, vim.tbl_count(errors))

      local history = storage.read_metric_history("owner/alpha", "clones")
      assert.equals(1, #history)
      assert.equals(1, history[1].data.count)
    end)

    it("keys an API error by repo/metric instead of storing anything", function()
      api_responder = function(_, metric)
        if metric == "views" then
          return nil, "GitHub API error: Forbidden"
        end
        return { count = 1 }, nil
      end

      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      assert.equals(3, #success)
      assert.equals("GitHub API error: Forbidden", errors["owner/alpha/views"])
      assert.equals(0, #storage.read_metric_history("owner/alpha", "views"))
    end)

    it("reports a storage failure as an error for that metric", function()
      local real_write = storage.write_metric
      ---@diagnostic disable-next-line: duplicate-set-field
      storage.write_metric = function(_, metric)
        if metric == "paths" then
          return false, "disk on fire"
        end
        return true, nil
      end

      local success, errors
      fetcher.fetch_repo("owner/alpha", function(s, e)
        success, errors = s, e
      end)
      wait_for(function()
        return success ~= nil
      end)

      storage.write_metric = real_write

      assert.equals(3, #success)
      assert.equals("disk on fire", errors["owner/alpha/paths"])
    end)
  end)

  describe("fetch_all", function()
    it("warns and does nothing when no repositories are configured", function()
      config.init({ config_dir = tmp_dir, repos = {} })

      fetcher.fetch_all(true)
      vim.wait(50)

      assert.equals(0, #api_calls)
      assert.equals(1, notice_count("No repositories configured"))
    end)

    -- ERR-03: a passed callback documents completion, so it must fire even
    -- when there is nothing to fetch -- otherwise a caller waiting on it
    -- (dashboard/actions.refresh_all's on_done, the right-click menu's
    -- force_refresh wrapper) hangs forever with no way to tell "still
    -- running" from "decided not to run".
    it("still invokes the callback when there are no repositories to fetch", function()
      config.init({ config_dir = tmp_dir, repos = {} })

      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.same({}, summary.success)
      assert.same({}, summary.errors)
      assert.is_not_nil(summary.timestamp)
      -- Not an actual fetch attempt, so the real last_fetch_summary (if any)
      -- must not be overwritten by this no-op.
      assert.is_nil(fetcher.last_fetch_summary)
    end)

    it("fetches every configured repository and summarises the result", function()
      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(8, #api_calls)
      assert.equals(8, #summary.success)
      assert.equals(0, vim.tbl_count(summary.errors))
      assert.is_not_nil(summary.timestamp)
      assert.equals(summary, fetcher.last_fetch_summary)
      assert.equals(1, notice_count("Successfully fetched 8 metrics"))
    end)

    it("keeps at most max_parallel_fetches repositories in flight and still fetches all", function()
      local repos = {}
      for i = 1, 7 do
        repos[i] = "owner/repo" .. i
      end
      config.init({ config_dir = tmp_dir, repos = repos, max_parallel_fetches = 2 })

      -- Responses arrive a few ms later, so repositories genuinely overlap and
      -- an uncapped fan-out would show all seven in flight at once.
      local pending, in_flight, peak = {}, 0, 0
      package.loaded["github_stats.api"].fetch_metric_async = function(repo, metric, callback)
        api_calls[#api_calls + 1] = { repo = repo, metric = metric }
        if not pending[repo] then
          pending[repo] = 4
          in_flight = in_flight + 1
          peak = math.max(peak, in_flight)
        end
        vim.defer_fn(function()
          pending[repo] = pending[repo] - 1
          if pending[repo] == 0 then
            in_flight = in_flight - 1
          end
          callback({ count = 1, uniques = 1, clones = {} }, nil)
        end, 5)
      end

      local calls, summary = 0, nil
      fetcher.fetch_all(true, function(s)
        calls = calls + 1
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)
      vim.wait(30)

      assert.equals(2, peak)
      assert.equals(1, calls)
      assert.equals(28, #api_calls)
      assert.equals(28, #summary.success)
      assert.equals(7, vim.tbl_count(pending))
      assert.equals(1, notice_count("Successfully fetched 28 metrics"))
    end)

    -- vim.system throws when a spawn fails (curl gone, process limit, AV
    -- blocking it). Past the first batch such a spawn runs from a completion
    -- callback: the failure must count as that repository's error and the
    -- queue must go on, not strand the rest of the list and the callback.
    it("finishes the queue when a repository's fetch throws while starting", function()
      local repos = {}
      for i = 1, 5 do
        repos[i] = "owner/repo" .. i
      end
      config.init({ config_dir = tmp_dir, repos = repos, max_parallel_fetches = 2 })

      package.loaded["github_stats.api"].fetch_metric_async = function(repo, metric, callback)
        if repo == "owner/repo4" then
          error("spawn failed: ENOENT")
        end
        api_calls[#api_calls + 1] = { repo = repo, metric = metric }
        vim.defer_fn(function()
          callback({ count = 1, uniques = 1, clones = {} }, nil)
        end, 5)
      end

      local calls, summary = 0, nil
      fetcher.fetch_all(true, function(s)
        calls = calls + 1
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)
      vim.wait(30)

      assert.is_not_nil(summary)
      assert.equals(1, calls)
      assert.equals(16, #summary.success)
      assert.equals(1, vim.tbl_count(summary.errors))
      assert.truthy(tostring(summary.errors["owner/repo4"]):find("spawn failed: ENOENT", 1, true))
      assert.equals(1, notice_count("Fetched 16 metrics, 1 errors"))
    end)

    it("records the fetch timestamp so the interval gate has something to read", function()
      local done = false
      fetcher.fetch_all(true, function()
        done = true
      end)
      wait_for(function()
        return done
      end)

      local stamp = require("lib.nvim.fs.json").read(tmp_dir .. "/last_fetch.json")
      assert.is_not_nil(stamp)
      assert.is_true(stamp.timestamp <= os.time())
    end)

    it("skips an unforced fetch while the interval has not elapsed", function()
      seed_data()
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      fetcher.fetch_all(false)
      vim.wait(50)

      assert.equals(0, #api_calls)
      assert.equals(1, notice_count("Fetch interval not elapsed"))
    end)

    describe("a newly added repository inside the interval", function()
      local function stamp_now()
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })
      end

      it("is fetched at once, an existing one is left alone", function()
        seed_data({ "owner/alpha" })
        stamp_now()

        local summary
        fetcher.fetch_all(false, function(s)
          summary = s
        end)
        wait_for(function()
          return summary ~= nil
        end)

        assert.equals(4, #api_calls)
        for _, call in ipairs(api_calls) do
          assert.equals("owner/beta", call.repo)
        end
        assert.equals(4, #summary.success)
        assert.equals(1, #storage.read_metric_history("owner/beta", "clones"))
      end)

      it("names the new repositories in one info message", function()
        seed_data({ "owner/alpha" })
        stamp_now()

        local done = false
        fetcher.fetch_all(false, function()
          done = true
        end)
        wait_for(function()
          return done
        end)

        assert.equals(1, notice_count("Fetching 1 new repository: owner/beta"))
        assert.equals(0, notice_count("Fetch interval not elapsed"))
      end)

      it("does not move the regular interval: last_fetch.json stays as it was", function()
        seed_data({ "owner/alpha" })
        local before = os.time() - 3600
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = before })

        local done = false
        fetcher.fetch_all(false, function()
          done = true
        end)
        wait_for(function()
          return done
        end)

        local stamp = require("lib.nvim.fs.json").read(tmp_dir .. "/last_fetch.json")
        assert.equals(before, stamp.timestamp)
      end)

      it("is announced in a background cycle too, but nothing else is", function()
        seed_data({ "owner/alpha" })
        stamp_now()

        local done = false
        fetcher.fetch_all(false, function()
          done = true
        end, { background = true })
        wait_for(function()
          return done
        end)

        assert.equals(1, notice_count("new repository"))
        assert.equals(0, notice_count("Starting fetch"))
        assert.equals(0, notice_count("Successfully fetched"))
      end)

      it("fetches nothing when every repository already has data", function()
        seed_data()
        stamp_now()
        fetcher.fetch_all(false, nil, { background = true })
        vim.wait(50)
        assert.equals(0, #api_calls)
        assert.equals(0, notice_count("new repository"))
      end)
    end)

    -- Same ERR-03 callback-completion guarantee as the "no repositories"
    -- case above, for the other early-return path.
    it("still invokes the callback when the interval has not elapsed", function()
      seed_data()
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      local summary
      fetcher.fetch_all(false, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.same({}, summary.success)
      assert.same({}, summary.errors)
    end)

    it("runs an unforced fetch once the interval has elapsed", function()
      -- `repos` must be repeated: config.init() merges over the config.json it
      -- wrote on the first call, whose `repos` is the shipped default list.
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" }, fetch_interval_hours = 1 })
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() - 7200 })

      local summary
      fetcher.fetch_all(false, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(8, #api_calls)
    end)

    it("fetch_due answers the interval gate and how far along it is", function()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha" }, fetch_interval_hours = 3 })
      vim.fn.delete(tmp_dir .. "/last_fetch.json")
      local due, info = fetcher.fetch_due()
      assert.is_true(due)
      assert.is_nil(info)

      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() - 3600 })
      due, info = fetcher.fetch_due()
      assert.is_false(due)
      assert.equals(3, info.interval_hours)
      assert.is_true(math.abs(info.since_hours - 1) < 0.1)

      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() - 4 * 3600 })
      due = fetcher.fetch_due()
      assert.is_true(due)
    end)

    it("stays quiet about the interval when notify_fetch is off", function()
      seed_data()
      config.init({ config_dir = tmp_dir, repos = { "owner/alpha", "owner/beta" }, notify_fetch = false })
      require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

      fetcher.fetch_all(false)
      vim.wait(50)

      assert.equals(0, notice_count("Fetch interval not elapsed"))
    end)

    describe("digest", function()
      local real_digest, written

      before_each(function()
        real_digest = package.loaded["github_stats.digest"]
        written = nil
        package.loaded["github_stats.digest"] = {
          write_later = function(repos)
            written = repos
          end,
        }
      end)

      after_each(function()
        package.loaded["github_stats.digest"] = real_digest
      end)

      it("is published for every repository that got data, once the fetch is done", function()
        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end)
        wait_for(function()
          return summary ~= nil
        end)

        assert.same({ "owner/alpha", "owner/beta" }, written)
      end)

      it("leaves out a repository whose every metric failed", function()
        api_responder = function(repo)
          if repo == "owner/beta" then
            return nil, "boom"
          end
          return { count = 1 }, nil
        end

        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end)
        wait_for(function()
          return summary ~= nil
        end)

        assert.same({ "owner/alpha" }, written)
      end)

      it("is not touched when the interval has not elapsed and nothing was fetched", function()
        seed_data()
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

        local summary
        fetcher.fetch_all(false, function(s)
          summary = s
        end)
        wait_for(function()
          return summary ~= nil
        end)

        assert.is_nil(written)
      end)
    end)

    describe("on_settled", function()
      local real_digest, writes, later

      before_each(function()
        real_digest = package.loaded["github_stats.digest"]
        writes, later = {}, nil
        package.loaded["github_stats.digest"] = {
          write = function(repos, o)
            writes[#writes + 1] = { repos = repos, skip_root = o and o.skip_root }
            return { written = repos, unchanged = {}, skipped = {}, errors = {} }
          end,
          write_later = function(repos)
            later = repos
          end,
        }
      end)

      after_each(function()
        package.loaded["github_stats.digest"] = real_digest
      end)

      it("comes after the callback, with the digests written at once instead of later", function()
        local order = {}
        local settled
        fetcher.fetch_all(true, function()
          order[#order + 1] = "callback"
        end, {
          on_settled = function(s)
            order[#order + 1] = "settled"
            settled = s
          end,
        })
        wait_for(function()
          return settled ~= nil
        end)

        assert.same({ "callback", "settled" }, order)
        assert.equals(8, #settled.summary.success)
        assert.same({ "owner/alpha", "owner/beta" }, settled.digest.written)
        assert.equals(1, #writes)
        assert.is_false(writes[1].skip_root)
        assert.is_nil(later)
      end)

      it("passes skip_root on to the digest", function()
        local settled
        fetcher.fetch_all(true, nil, {
          skip_root = true,
          on_settled = function(s)
            settled = s
          end,
        })
        wait_for(function()
          return settled ~= nil
        end)
        assert.is_true(writes[1].skip_root)
      end)

      it("reports a raising digest instead of failing the fetch", function()
        package.loaded["github_stats.digest"].write = function()
          error("disk full")
        end
        local settled
        fetcher.fetch_all(true, nil, {
          on_settled = function(s)
            settled = s
          end,
        })
        wait_for(function()
          return settled ~= nil
        end)
        assert.matches("disk full", settled.digest_error)
        assert.is_nil(settled.digest)
        assert.equals(8, #settled.summary.success)
      end)

      it("is called on the early return too (interval not elapsed), with the summary only", function()
        seed_data()
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })
        local settled
        fetcher.fetch_all(false, nil, {
          on_settled = function(s)
            settled = s
          end,
        })
        wait_for(function()
          return settled ~= nil
        end)
        assert.same({}, settled.summary.success)
        assert.is_nil(settled.digest)
        assert.equals(0, #writes)
      end)
    end)

    it("counts errors in the summary and warns about them", function()
      api_responder = function(repo)
        if repo == "owner/beta" then
          return nil, "boom"
        end
        return { count = 1 }, nil
      end

      local summary
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      wait_for(function()
        return summary ~= nil
      end)

      assert.equals(4, #summary.success)
      assert.equals(4, vim.tbl_count(summary.errors))
      assert.equals(1, notice_count("Fetched 4 metrics, 4 errors"))
      assert.equals(0, notice_count("Successfully fetched"))
    end)

    describe("background mode", function()
      it("suppresses the start and success notifications", function()
        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end, { background = true })
        wait_for(function()
          return summary ~= nil
        end)

        assert.equals(8, #api_calls)
        assert.equals(0, notice_count("Starting fetch"))
        assert.equals(0, notice_count("Successfully fetched"))
      end)

      it("still reports errors, so real problems are not hidden", function()
        api_responder = function()
          return nil, "boom"
        end

        local summary
        fetcher.fetch_all(true, function(s)
          summary = s
        end, { background = true })
        wait_for(function()
          return summary ~= nil
        end)

        assert.equals(1, notice_count("8 errors"))
      end)

      it("suppresses the 'no repositories' warning too", function()
        config.init({ config_dir = tmp_dir, repos = {} })

        fetcher.fetch_all(false, nil, { background = true })
        vim.wait(50)

        assert.equals(0, notice_count("No repositories configured"))
      end)

      it("suppresses the interval notice", function()
        seed_data()
        require("lib.nvim.fs.json").write(tmp_dir .. "/last_fetch.json", { timestamp = os.time() })

        fetcher.fetch_all(false, nil, { background = true })
        vim.wait(50)

        assert.equals(0, notice_count("Fetch interval not elapsed"))
      end)
    end)
  end)

  describe("convenience entry points", function()
    it("auto_fetch does not force, manual_fetch passes its flag through", function()
      local forced = {}
      local real_fetch_all = fetcher.fetch_all
      ---@diagnostic disable-next-line: duplicate-set-field
      fetcher.fetch_all = function(force)
        forced[#forced + 1] = force
      end

      fetcher.auto_fetch()
      fetcher.manual_fetch(true)
      fetcher.manual_fetch(false)

      fetcher.fetch_all = real_fetch_all

      assert.same({ false, true, false }, forced)
    end)
  end)
end)

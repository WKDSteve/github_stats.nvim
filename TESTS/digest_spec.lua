---@diagnostic disable: undefined-global

-- Specs for github_stats.digest -- the per-repository file other programs read.
--
-- Nothing here touches the network: history is written straight into a
-- temporary data directory in the same on-disk layout the fetcher produces,
-- and the digest is read back from where it was published. The digest's
-- "default" location (root.json) is redirected into the temp directory too,
-- so no spec writes into a real stdpath("data").
--
-- Fixture days sit 2..14 days back, never on the boundary: `analytics` drops
-- "today" by the *local* calendar while the windows are counted in UTC, and a
-- fixture on the edge of either would make these specs depend on the hour the
-- suite runs at.

describe("digest", function()
  local config, storage, digest, json
  local tmp_dir
  local real_default_dir
  local REPO = "owner/alpha"
  local DAY = 86400

  ---@param offset integer days back from today (UTC)
  ---@return string
  local function date_str(offset)
    return os.date("!%Y-%m-%d", os.time() - offset * DAY)
  end

  ---@param path string
  ---@return string
  local function read_raw(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*a")
    f:close()
    return content
  end

  ---One stored fetch of clones/views: a day each for offsets 2..14.
  ---@param repo string
  ---@param metric "clones"|"views"
  ---@param stamp string file stem, e.g. "2026-01-01T12-00-00"
  ---@param count integer
  local function write_daily_fetch(repo, metric, stamp, count)
    local items = {}
    for offset = 14, 2, -1 do
      items[#items + 1] = { timestamp = date_str(offset) .. "T00:00:00Z", count = count, uniques = 2 }
    end
    local dir = storage.get_metric_dir(repo, metric)
    vim.fn.mkdir(dir, "p")
    json.write(dir .. "/" .. stamp .. ".json", {
      timestamp = stamp:gsub("(%d%d)%-(%d%d)%-(%d%d)$", "%1:%2:%3") .. "Z",
      data = { [metric] = items },
    })
    storage.invalidate()
  end

  ---@param repo string
  ---@param metric "referrers"|"paths"
  ---@param stamp string
  ---@param items table[]
  local function write_snapshot(repo, metric, stamp, items)
    local dir = storage.get_metric_dir(repo, metric)
    vim.fn.mkdir(dir, "p")
    json.write(dir .. "/" .. stamp .. ".json", { timestamp = "x", data = items })
    storage.invalidate()
  end

  ---A repository with a full set of stored history.
  ---@param repo string
  ---@param stamp? string
  local function seed(repo, stamp)
    stamp = stamp or (date_str(1) .. "T12-00-00")
    write_daily_fetch(repo, "views", stamp, 10)
    write_daily_fetch(repo, "clones", stamp, 4)
    write_snapshot(repo, "referrers", stamp, { { referrer = "google.com", count = 9, uniques = 5 } })
    write_snapshot(repo, "paths", stamp, { { path = "/owner/alpha", title = "alpha", count = 7, uniques = 3 } })
  end

  ---@param repo? string
  ---@return table
  local function published(repo)
    return assert(json.read(digest.digest_file(repo or REPO)))
  end

  local function fresh_modules()
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.digest",
    }) do
      package.loaded[name] = nil
    end
    config = require("github_stats.config")
    storage = require("github_stats.storage")
    digest = require("github_stats.digest")
    json = require("lib.nvim.fs.json")
  end

  before_each(function()
    fresh_modules()
    -- Forward slashes: the digest reports its paths that way on every platform.
    tmp_dir = vim.fn.tempname():gsub("\\", "/")
    vim.fn.delete(tmp_dir, "rf")
    config.init({
      config_dir = tmp_dir .. "/config",
      repos = { REPO, "owner/beta" },
      digest_dir = tmp_dir .. "/digests",
    })
    real_default_dir = digest.default_dir
    digest.default_dir = function()
      return tmp_dir .. "/default"
    end
  end)

  after_each(function()
    digest.default_dir = real_default_dir
    vim.env.GITHUB_TOKEN = nil
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  describe("locations", function()
    it("names the default place before setup() has run", function()
      fresh_modules()

      local expected = vim.fn.stdpath("data"):gsub("\\", "/") .. "/github_stats.nvim"
      assert.equals(expected, digest.digest_dir())
      assert.equals(expected .. "/root.json", digest.root_path())
    end)

    it("honours digest_dir and expands it", function()
      config.init({ config_dir = tmp_dir .. "/config", digest_dir = "~/somewhere/else" })

      local dir = digest.digest_dir()
      assert.is_nil(dir:find("~", 1, true))
      assert.equals("/somewhere/else", dir:sub(-15))
    end)

    it("names a repository's file by storage's own rule", function()
      assert.equals(tmp_dir .. "/digests/digest/owner_alpha.json", digest.digest_file("owner/alpha"))
      assert.equals("a_b%3Ac", digest.file_stem("a/b:c"))
      assert.equals("a_b_c", digest.file_stem("a/b_c"))
    end)

    it("is free of the UI: probing it must not load ui.nvim or the dashboard", function()
      for name in pairs(package.loaded) do
        if name == "ui" or name:find("^ui%.") or name == "github_stats.dashboard" then
          package.loaded[name] = nil
        end
      end
      fresh_modules()

      local leaked = {}
      for name in pairs(package.loaded) do
        if name == "ui" or name:find("^ui%.") or name == "github_stats.dashboard" or name == "github_stats" then
          leaked[#leaked + 1] = name
        end
      end
      assert.same({}, leaked)
    end)
  end)

  describe("build", function()
    it("summarises the stored history", function()
      seed(REPO)

      local d = assert(digest.build(REPO))

      assert.equals(1, d.schema)
      assert.equals(REPO, d.repo)
      assert.is_truthy(d.generated:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
      assert.equals(date_str(1) .. "T12:00:00Z", d.fetched)
      assert.same({ from = date_str(14), to = date_str(2) }, d.span)

      -- Offsets 2..7 are inside the 7-day window (6 days), 2..14 inside the 30- and 90-day ones (13 days).
      assert.same({ count = 60, uniques = 12 }, d.views.d7)
      assert.same({ count = 130, uniques = 26 }, d.views.d30)
      assert.same({ count = 130, uniques = 26 }, d.views.d90)
      assert.same({ count = 24, uniques = 12 }, d.clones.d7)
      assert.equals("number", type(d.views.trend))
    end)

    it("keeps one [date, count, uniques] tuple per stored day, oldest first", function()
      seed(REPO)

      local d = assert(digest.build(REPO))

      assert.equals(13, #d.daily.views)
      assert.same({ date_str(14), 10, 2 }, d.daily.views[1])
      assert.same({ date_str(2), 10, 2 }, d.daily.views[13])
      assert.same({ date_str(14), 4, 2 }, d.daily.clones[1])
    end)

    it("bounds the daily series by digest_daily_days", function()
      seed(REPO)
      config.init({
        config_dir = tmp_dir .. "/config",
        digest_dir = tmp_dir .. "/digests",
        digest_daily_days = 5,
      })

      local d = assert(digest.build(REPO))

      assert.equals(5, #d.daily.views)
      assert.equals(date_str(6), d.daily.views[1][1])
      assert.equals(date_str(2), d.daily.views[5][1])
      -- The windows are unaffected by how much daily detail is kept.
      assert.same({ count = 130, uniques = 26 }, d.views.d30)
    end)

    it("falls back to the default bound for a nonsense digest_daily_days", function()
      seed(REPO)
      config.init({ config_dir = tmp_dir .. "/config", digest_dir = tmp_dir .. "/digests", digest_daily_days = -3 })

      assert.equals(13, #assert(digest.build(REPO)).daily.views)
    end)

    it("copies the top referrers and paths, and only the known fields", function()
      seed(REPO)
      write_snapshot(REPO, "referrers", date_str(1) .. "T13-00-00", {
        { referrer = "google.com", count = 9, uniques = 5, extra = "ignored" },
        { referrer = "<img src=x onerror=alert(1)>", count = 2, uniques = 1 },
        { referrer = 42, count = 1, uniques = 1 },
      })

      local d = assert(digest.build(REPO))

      assert.same({
        { referrer = "google.com", count = 9, uniques = 5 },
        { referrer = "<img src=x onerror=alert(1)>", count = 2, uniques = 1 },
      }, d.referrers)
      assert.same({ { path = "/owner/alpha", title = "alpha", count = 7, uniques = 3 } }, d.paths)
    end)

    it("clips over-long strings by characters, never mid-character", function()
      seed(REPO)
      write_snapshot(REPO, "referrers", date_str(1) .. "T13-00-00", {
        { referrer = string.rep("ä", 500), count = 1, uniques = 1 },
      })

      local referrer = assert(digest.build(REPO)).referrers[1].referrer

      assert.equals(string.rep("ä", 200), referrer)
    end)

    it("leaves referrers and paths out when no snapshot was ever fetched (unknown, not empty)", function()
      write_daily_fetch(REPO, "views", date_str(1) .. "T12-00-00", 10)

      local d = assert(digest.build(REPO))

      assert.is_nil(d.referrers)
      assert.is_nil(d.paths)
    end)

    it("writes an empty top 10 as an empty list when a snapshot said so", function()
      seed(REPO)
      write_snapshot(REPO, "referrers", date_str(1) .. "T13-00-00", {})

      local d = assert(digest.build(REPO))

      assert.same({}, d.referrers)
    end)

    it("reports 'no history' for a repository that was never fetched", function()
      local d, err = digest.build(REPO)

      assert.is_nil(d)
      assert.equals("no history", err)
    end)

    it("rejects an empty repository name", function()
      local d, err = digest.build("")

      assert.is_nil(d)
      assert.is_truthy(err)
    end)

    it("survives malformed records in the history", function()
      seed(REPO)
      local dir = storage.get_metric_dir(REPO, "views")
      json.write(dir .. "/" .. date_str(1) .. "T14-00-00.json", {
        timestamp = 5,
        data = { views = { { timestamp = 7, count = "many" }, "junk", { timestamp = "not-a-date", count = 3 } } },
      })
      storage.invalidate()

      local d = assert(digest.build(REPO))

      assert.same({ count = 130, uniques = 26 }, d.views.d30)
      for _, entry in ipairs(d.daily.views) do
        assert.is_truthy(entry[1]:match("^%d%d%d%d%-%d%d%-%d%d$"))
      end
    end)
  end)

  describe("write", function()
    it("publishes a digest file and root.json", function()
      seed(REPO)

      local result = digest.write({ REPO })

      assert.same({ REPO }, result.written)
      assert.same({}, result.errors)
      assert.equals(REPO, published().repo)
      local root = assert(json.read(digest.root_path()))
      assert.equals(1, root.schema)
      assert.equals(tmp_dir .. "/digests", root.digest_dir)
      assert.equals((config.get_storage_root():gsub("\\", "/")), root.data_dir)
      assert.same({ [REPO] = "owner_alpha" }, root.repos)
    end)

    it("puts root.json at the default place even when digest_dir is overridden, and nothing else there", function()
      seed(REPO)

      digest.write({ REPO })

      assert.equals(1, vim.fn.filereadable(tmp_dir .. "/default/root.json"))
      assert.equals(1, vim.fn.filereadable(tmp_dir .. "/digests/digest/owner_alpha.json"))
      assert.equals(0, vim.fn.filereadable(tmp_dir .. "/digests/root.json"))
      assert.equals(0, vim.fn.filereadable(tmp_dir .. "/default/digest/owner_alpha.json"))
    end)

    it("leaves an unchanged digest alone, even though `generated` moves", function()
      seed(REPO)
      digest.write({ REPO })
      local path = digest.digest_file(REPO)
      local doc = published()
      doc.generated = "2000-01-01T00:00:00Z"
      json.write(path, doc)
      local before = vim.uv.fs_stat(path).mtime

      local result = digest.write({ REPO })

      assert.same({ REPO }, result.unchanged)
      assert.same({}, result.written)
      assert.equals("2000-01-01T00:00:00Z", published().generated)
      local after = vim.uv.fs_stat(path).mtime
      assert.equals(before.sec, after.sec)
      assert.equals(before.nsec, after.nsec)
    end)

    it("rewrites it when the data changed", function()
      seed(REPO)
      digest.write({ REPO })
      write_daily_fetch(REPO, "views", date_str(1) .. "T18-00-00", 20)

      local result = digest.write({ REPO })

      assert.same({ REPO }, result.written)
      assert.equals(20, published().views.d7.count / 6)
    end)

    it("leaves no temporary file behind", function()
      seed(REPO)
      seed("owner/beta")

      digest.write_all()

      local stray = vim.fn.glob(tmp_dir .. "/**/*.tmp", false, true)
      assert.same({}, stray)
    end)

    it("writes only the repositories it was asked for", function()
      seed(REPO)
      seed("owner/beta")

      digest.write({ REPO })

      assert.equals(1, vim.fn.filereadable(digest.digest_file(REPO)))
      assert.equals(0, vim.fn.filereadable(digest.digest_file("owner/beta")))
    end)

    it("skips a repository without history: no file, and no root.json for nothing", function()
      local result = digest.write({ REPO })

      assert.same({ REPO }, result.skipped)
      assert.equals(0, vim.fn.filereadable(digest.digest_file(REPO)))
      assert.equals(0, vim.fn.filereadable(digest.root_path()))
    end)

    it("keeps earlier repositories in root.json when a later write covers only one", function()
      seed(REPO)
      seed("owner/beta")
      digest.write({ REPO })

      digest.write({ "owner/beta" })

      local root = assert(json.read(digest.root_path()))
      assert.same({ [REPO] = "owner_alpha", ["owner/beta"] = "owner_beta" }, root.repos)
    end)

    it("drops a repository from root.json once its digest file is gone", function()
      seed(REPO)
      seed("owner/beta")
      digest.write_all()
      os.remove(digest.digest_file("owner/beta"))

      digest.write_root()

      assert.same({ [REPO] = "owner_alpha" }, assert(json.read(digest.root_path())).repos)
    end)

    it("reports one repository's failure without losing the others", function()
      seed(REPO)
      seed("owner/beta")
      local dir = storage.get_metric_dir(REPO, "views")
      vim.fn.writefile({ "{ this is not json" }, dir .. "/" .. date_str(1) .. "T15-00-00.json")
      storage.invalidate()

      local result = digest.write_all()

      assert.same({ "owner/beta" }, result.written)
      assert.is_truthy(result.errors[REPO])
      assert.equals(1, vim.fn.filereadable(digest.digest_file("owner/beta")))
    end)

    it("reports an unwritable directory as an error, not an exception", function()
      seed(REPO)
      vim.fn.mkdir(tmp_dir, "p")
      vim.fn.writefile({ "a file, not a directory" }, tmp_dir .. "/blocker")
      config.init({ config_dir = tmp_dir .. "/config", digest_dir = tmp_dir .. "/blocker/sub" })

      local ok, result = pcall(digest.write, { REPO })

      assert.is_true(ok)
      assert.is_truthy(result.errors[REPO])
      assert.same({}, result.written)
    end)

    it("never lets a token into the output", function()
      vim.env.GITHUB_TOKEN = "ghp_SECRET_TOKEN_0123456789"
      config.init({
        config_dir = tmp_dir .. "/config",
        repos = { REPO },
        digest_dir = tmp_dir .. "/digests",
        token_source = "env",
        token_file = tmp_dir .. "/token-file",
      })
      seed(REPO)

      digest.write_all()

      assert.is_nil(read_raw(digest.digest_file(REPO)):find("ghp_SECRET", 1, true))
      assert.is_nil(read_raw(digest.root_path()):find("ghp_SECRET", 1, true))
      assert.is_nil(read_raw(digest.digest_file(REPO)):find("token", 1, true))
    end)

    it("records the outcome for :GithubStats debug", function()
      seed(REPO)

      digest.write({ REPO })

      assert.same({ REPO }, digest.last_result.written)
    end)
  end)

  describe("write_later", function()
    it("writes on a later turn of the event loop, not inside the caller", function()
      seed(REPO)

      digest.write_later({ REPO })
      assert.equals(0, vim.fn.filereadable(digest.digest_file(REPO)))

      vim.wait(2000, function()
        return vim.fn.filereadable(digest.digest_file(REPO)) == 1
      end, 5)
      assert.equals(1, vim.fn.filereadable(digest.digest_file(REPO)))
    end)

    it("writes one repository per loop turn, then root.json", function()
      local other = "owner/beta"
      seed(REPO)
      seed(other)
      local real_write = digest.write
      local calls, seen_at_first_turn_end = 0, nil
      digest.write = function(repos, opts)
        calls = calls + 1
        if calls == 1 then
          -- queued before the slice schedules the next one: runs when the first turn is over
          vim.schedule(function()
            seen_at_first_turn_end = calls
          end)
        end
        return real_write(repos, opts)
      end

      digest.write_later({ REPO, other })
      vim.wait(2000, function()
        return digest.last_result ~= nil
      end, 5)

      assert.equals(2, calls)
      assert.equals(1, seen_at_first_turn_end)
      assert.same({ REPO, other }, digest.last_result.written)
      assert.equals(1, vim.fn.filereadable(digest.digest_file(other)))
      assert.equals(1, vim.fn.filereadable(digest.root_path()))
      assert.is_nil(digest.last_error)
    end)

    it("keeps going after one repository raised, and reports it", function()
      local other = "owner/beta"
      seed(REPO)
      seed(other)
      local real_write = digest.write
      digest.write = function(repos, opts)
        if repos[1] == REPO then
          error("boom")
        end
        return real_write(repos, opts)
      end

      digest.write_later({ REPO, other })
      vim.wait(2000, function()
        return digest.last_result ~= nil
      end, 5)

      assert.is_truthy(digest.last_error:find("boom", 1, true))
      assert.same({ other }, digest.last_result.written)
    end)

    it("does nothing for an empty list", function()
      digest.write_later({})

      vim.wait(50)
      assert.is_nil(digest.last_result)
    end)

    it("swallows an error raised inside the write", function()
      digest.write = function()
        error("boom")
      end

      digest.write_later({ REPO })
      vim.wait(2000, function()
        return digest.last_error ~= nil
      end, 5)

      assert.is_truthy(digest.last_error:find("boom", 1, true))
    end)
  end)

  describe("stale", function()
    it("is false while nothing was ever fetched", function()
      assert.is_false((digest.stale()))
    end)

    it("is true when history exists and no digest does, and names the repository", function()
      seed(REPO)

      local stale, repo = digest.stale()

      assert.is_true(stale)
      assert.equals(REPO, repo)
    end)

    it("is false right after the digests were built", function()
      seed(REPO)
      digest.write_all()

      assert.is_false((digest.stale()))
    end)

    it("turns true again when a newer fetch lands (the other machine fetched, and the history synced)", function()
      seed(REPO)
      digest.write_all()

      write_daily_fetch(REPO, "views", date_str(0) .. "T23-59-59", 10)

      assert.is_true((digest.stale()))
    end)

    it("lists the history again only when a snapshot directory changed", function()
      seed(REPO)
      digest.write_all()
      assert.is_false((digest.stale())) -- the listing is memoized now

      local real, listings = vim.uv.fs_scandir, 0
      vim.uv.fs_scandir = function(...)
        listings = listings + 1
        return real(...)
      end
      local ok, err = pcall(function()
        assert.is_false((digest.stale()))
        assert.equals(0, listings, "an unchanged history is not listed again")
        write_daily_fetch(REPO, "views", date_str(0) .. "T23-59-58", 10)
        assert.is_true((digest.stale()))
        assert.is_true(listings > 0, "a new snapshot file makes the next check list it")
      end)
      vim.uv.fs_scandir = real
      assert(ok, err)
    end)

    ---Count what `digest.stale()` does to the disk while `fn` runs: history listings and digest decodes.
    ---@param fn fun()
    ---@return integer listings
    ---@return integer decodes
    local function count_io(fn)
      local real_scandir, real_read = vim.uv.fs_scandir, json.read
      local listings, decodes = 0, 0
      vim.uv.fs_scandir = function(...)
        listings = listings + 1
        return real_scandir(...)
      end
      json.read = function(path, ...)
        if type(path) == "string" and path:find("/digest/", 1, true) then
          decodes = decodes + 1
        end
        return real_read(path, ...)
      end
      local ok, err = pcall(fn)
      vim.uv.fs_scandir, json.read = real_scandir, real_read
      assert(ok, err)
      return listings, decodes
    end

    ---A new Neovim session: every module loaded afresh, the same data and digest places.
    local function new_session()
      local default = digest.default_dir()
      fresh_modules()
      config.init({
        config_dir = tmp_dir .. "/config",
        repos = { REPO, "owner/beta" },
        digest_dir = tmp_dir .. "/digests",
      })
      digest.default_dir = function()
        return default
      end
    end

    it("decodes a digest only after it changed", function()
      seed(REPO)
      digest.write_all()
      assert.is_false((digest.stale()))

      local listings, decodes = count_io(function()
        assert.is_false((digest.stale()))
      end)
      assert.equals(0, listings)
      assert.equals(0, decodes, "an unchanged digest is not decoded again")

      local doc = published()
      doc.fetched = "2000-01-01T00:00:00Z"
      json.write(digest.digest_file(REPO), doc)
      local _, rereads = count_io(function()
        assert.is_true((digest.stale()), "a digest rewritten by someone else is read again")
      end)
      assert.equals(1, rereads)
    end)

    it("starts a new session without listing the history or decoding a digest", function()
      seed(REPO)
      digest.write_all()
      assert.is_false((digest.stale()))

      new_session()
      local listings, decodes = count_io(function()
        assert.is_false((digest.stale()))
      end)
      assert.equals(0, listings, "the first check of a session reuses what the last one learnt")
      assert.equals(0, decodes)
    end)

    it("still sees a fetch that landed between two sessions", function()
      seed(REPO)
      digest.write_all()
      assert.is_false((digest.stale()))

      write_daily_fetch(REPO, "views", date_str(0) .. "T23-59-57", 10)
      new_session()

      assert.is_true((digest.stale()))
    end)

    it("ignores a memo file it cannot use", function()
      seed(REPO)
      digest.write_all()
      vim.fn.mkdir(vim.fn.fnamemodify(digest.memo_path(), ":h"), "p")
      vim.fn.writefile({ "{ not json" }, digest.memo_path())

      new_session()
      assert.is_false((digest.stale()))
      json.write(digest.memo_path(), { schema = 1, repos = { [REPO] = { key = 3, digest_key = {}, fetched = 1 } } })
      new_session()
      assert.is_false((digest.stale()))
      write_daily_fetch(REPO, "views", date_str(0) .. "T23-59-56", 10)
      assert.is_true((digest.stale()))
    end)

    it("treats a digest from before `fetched` existed as stale", function()
      seed(REPO)
      digest.write_all()
      local doc = published()
      doc.fetched = nil
      json.write(digest.digest_file(REPO), doc)

      assert.is_true((digest.stale()))
    end)

    it("ignores the archive file and stray temp files when looking for the newest fetch", function()
      seed(REPO)
      digest.write_all()
      local dir = storage.get_metric_dir(REPO, "views")
      json.write(dir .. "/_archive.json", { timestamp = "2999-01-01T00:00:00Z", data = { views = {} } })
      vim.fn.writefile({ "{" }, dir .. "/2999-01-01T00-00-00.json.tmp")

      assert.is_false((digest.stale()))
    end)

    it("refresh_if_stale rebuilds when stale and stays quiet otherwise", function()
      seed(REPO)

      local first = digest.refresh_if_stale()
      local second = digest.refresh_if_stale()

      assert.same({ REPO }, first.written)
      assert.is_nil(second)
    end)
  end)

  describe(":GithubStats digest", function()
    it("rebuilds every tracked repository and says what it did", function()
      seed(REPO)
      local notices = {}
      config.notify = function(message, level)
        notices[#notices + 1] = { message = message, level = level }
      end
      package.loaded["github_stats.bindings.usrcmds.digest"] = nil

      require("github_stats.bindings.usrcmds.digest").execute({})

      assert.equals(1, vim.fn.filereadable(digest.digest_file(REPO)))
      assert.equals(1, #notices)
      assert.is_truthy(notices[1].message:find("1 written, 0 unchanged, 1 without history", 1, true))
      package.loaded["github_stats.bindings.usrcmds.digest"] = nil
    end)
  end)
end)

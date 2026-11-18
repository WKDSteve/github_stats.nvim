-- tests/date_presets_spec.lua
describe("date_presets", function()
  local date_presets

  before_each(function()
    date_presets = require("github_stats.date_presets")
  end)

  describe("builtin presets", function()
    it("resolves 'today' correctly", function()
      local start, end_date = date_presets.resolve("today")
      local expected = os.date("%Y-%m-%d")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected, start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected, end_date)
    end)

    it("resolves 'last_week' correctly", function()
      local start, end_date = date_presets.resolve("last_week")
      local now = os.time()
      local week_ago = now - (7 * 86400)

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(os.date("%Y-%m-%d", week_ago), start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(os.date("%Y-%m-%d", now), end_date)
    end)

    it("resolves 'this_month' correctly", function()
      local start, end_date = date_presets.resolve("this_month")
      local now = os.date("*t")
      local expected_start = string.format("%04d-%02d-01", now.year, now.month)
      local expected_end = os.date("%Y-%m-%d")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_start, start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(expected_end, end_date)
    end)
  end)

  describe("preset detection", function()
    it("identifies preset names", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(date_presets.is_preset("today"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(date_presets.is_preset("last_week"))
    end)

    it("rejects ISO dates", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("2025-01-01"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("2025-12-31"))
    end)

    it("rejects invalid strings", function()
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset("invalid"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset(""))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(date_presets.is_preset(nil))
    end)
  end)

  describe("custom presets", function()
    it("resolves custom preset correctly", function()
      -- Mock config with custom preset
      local config_stub = {
        date_presets = {
          enabled = true,
          custom = {
            test_preset = function()
              return "2025-01-01", "2025-12-31"
            end,
          },
        },
      }

      -- Temporarily override config.get()
      local config = require("github_stats.config")
      local original_get = config.get
      -- Test double over a typed module function; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      config.get = function()
        return config_stub
      end

      local start, end_date = date_presets.resolve("test_preset")

      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-01-01", start)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("2025-12-31", end_date)

      -- Restore original
      config.get = original_get
    end)

    it("handles custom preset errors", function()
      local config_stub = {
        date_presets = {
          enabled = true,
          custom = {
            broken_preset = function()
              error("Intentional error")
            end,
          },
        },
      }

      local config = require("github_stats.config")
      local original_get = config.get
      -- Test double over a typed module function; restored below.
      ---@diagnostic disable-next-line: duplicate-set-field
      config.get = function()
        return config_stub
      end

      local start, end_date, err = date_presets.resolve("broken_preset")

      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(start)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(end_date)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(err)
      ---@diagnostic disable-next-line: undefined-field
      assert.matches("failed", err)

      config.get = original_get
    end)
  end)
end)

---@diagnostic disable: undefined-global

-- The rest of date_presets.lua: the full builtin set, the preset catalogue
-- M.list() builds, and every way resolve() can refuse.
--
-- Config is left uninitialised on purpose in most of these: `config.get()` is
-- nil until setup() has run, and both list() and resolve() fall back to
-- config/DEFAULTS.lua rather than reading that as "presets are disabled".
describe("date_presets catalogue", function()
  local date_presets, config

  ---Point config.get() at `cfg` for the duration of `fn`.
  ---@param cfg table
  ---@param fn fun()
  local function with_config(cfg, fn)
    local original = config.get
    ---@diagnostic disable-next-line: duplicate-set-field
    config.get = function()
      return cfg
    end
    local ok, err = pcall(fn)
    config.get = original
    assert.is_true(ok, tostring(err))
  end

  before_each(function()
    date_presets = require("github_stats.date_presets")
    config = require("github_stats.config")
  end)

  describe("list", function()
    it("offers every shipped builtin, sorted", function()
      local presets = date_presets.list()
      local DEFAULTS = require("github_stats.config.DEFAULTS")

      assert.equals(#DEFAULTS.date_presets.builtins, #presets)
      for _, name in ipairs(DEFAULTS.date_presets.builtins) do
        assert.is_truthy(vim.tbl_contains(presets, name), "missing preset: " .. name)
      end

      local sorted = vim.deepcopy(presets)
      table.sort(sorted)
      assert.same(sorted, presets)
    end)

    it("includes custom presets alongside the builtins", function()
      with_config({
        date_presets = {
          enabled = true,
          builtins = { "today" },
          custom = { sprint = function() end },
        },
      }, function()
        assert.same({ "sprint", "today" }, date_presets.list())
      end)
    end)

    it("drops a builtin name that does not exist", function()
      with_config({
        date_presets = { enabled = true, builtins = { "today", "next_century" }, custom = {} },
      }, function()
        assert.same({ "today" }, date_presets.list())
      end)
    end)

    it("is empty when presets are disabled or absent", function()
      with_config({ date_presets = { enabled = false } }, function()
        assert.same({}, date_presets.list())
      end)
      with_config({}, function()
        assert.same({}, date_presets.list())
      end)
    end)
  end)

  describe("builtins", function()
    it("resolves each one to an ISO date pair that does not end in the future", function()
      local today = os.date("%Y-%m-%d")

      for _, name in ipairs(date_presets.list()) do
        local start_date, end_date, err = date_presets.resolve(name)

        assert.is_nil(err, name .. ": " .. tostring(err))
        assert.is_truthy(start_date:match("^%d%d%d%d%-%d%d%-%d%d$"), name .. " start: " .. tostring(start_date))
        assert.is_truthy(end_date:match("^%d%d%d%d%-%d%d%-%d%d$"), name .. " end: " .. tostring(end_date))
        assert.is_true(start_date <= end_date, name .. " runs backwards")
        assert.is_true(end_date <= today, name .. " ends in the future")
      end
    end)

    it("resolves 'yesterday' to a single past day", function()
      local expected = os.date("%Y-%m-%d", os.time() - 86400)
      local start_date, end_date = date_presets.resolve("yesterday")

      assert.equals(expected, start_date)
      assert.equals(expected, end_date)
    end)

    it("starts 'this_year' on January 1st", function()
      local start_date = date_presets.resolve("this_year")

      assert.equals(string.format("%04d-01-01", os.date("*t").year), start_date)
    end)

    it("starts 'this_quarter' on the first day of a quarter month", function()
      local start_date = date_presets.resolve("this_quarter")
      local month = tonumber(start_date:sub(6, 7))

      assert.is_truthy(vim.tbl_contains({ 1, 4, 7, 10 }, month), "not a quarter start: " .. start_date)
      assert.equals("01", start_date:sub(9, 10))
    end)

    -- Monday, not Sunday: get_week_start() says so in its own docstring.
    -- Worth knowing that analytics.rollup_weekly() groups Sunday-started
    -- weeks instead -- the two are independent features, but they do not
    -- agree on where a week begins.
    it("starts 'this_week' on a Monday", function()
      local start_date = date_presets.resolve("this_week")
      local y, m, d = start_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
      local wday = os.date("%w", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) }))

      assert.equals("1", wday)
    end)
  end)

  describe("resolve refusals", function()
    it("rejects an empty name", function()
      local _, _, err = date_presets.resolve("")
      assert.equals("Empty preset name", err)

      _, _, err = date_presets.resolve(nil)
      assert.equals("Empty preset name", err)
    end)

    it("rejects an unknown name", function()
      local _, _, err = date_presets.resolve("last_fortnight")

      assert.equals("Unknown preset: last_fortnight", err)
    end)

    it("says so when presets are switched off entirely", function()
      with_config({ date_presets = { enabled = false } }, function()
        local _, _, err = date_presets.resolve("today")
        assert.equals("Date presets are disabled", err)
      end)
    end)

    it("rejects a custom preset that is not a function", function()
      with_config({
        date_presets = { enabled = true, builtins = {}, custom = { broken = "not a function" } },
      }, function()
        local _, _, err = date_presets.resolve("broken")
        assert.equals("Custom preset 'broken' is not a function", err)
      end)
    end)

    it("rejects a custom preset that does not return two strings", function()
      with_config({
        date_presets = {
          enabled = true,
          builtins = {},
          custom = {
            half = function()
              return "2026-01-01"
            end,
          },
        },
      }, function()
        local _, _, err = date_presets.resolve("half")
        assert.equals("Custom preset 'half' did not return two strings", err)
      end)
    end)

    it("rejects a custom preset that returns something other than ISO dates", function()
      with_config({
        date_presets = {
          enabled = true,
          builtins = {},
          custom = {
            sloppy = function()
              return "01/01/2026", "31/12/2026"
            end,
          },
        },
      }, function()
        local _, _, err = date_presets.resolve("sloppy")
        assert.equals("Custom preset 'sloppy' returned invalid date format", err)
      end)
    end)
  end)

  describe("is_preset", function()
    it("recognizes a custom preset name too", function()
      with_config({
        date_presets = {
          enabled = true,
          builtins = { "today" },
          custom = { sprint = function() end },
        },
      }, function()
        assert.is_true(date_presets.is_preset("sprint"))
        assert.is_false(date_presets.is_preset("other"))
      end)
    end)
  end)
end)

describe("date_presets on a fixed day (lib.lua.time.presets)", function()
  -- Wednesday 2026-10-14, midday.
  local NOW = os.time({ year = 2026, month = 10, day = 14, hour = 12 })
  local expected = {
    today = { "2026-10-14", "2026-10-14" },
    yesterday = { "2026-10-13", "2026-10-13" },
    last_week = { "2026-10-07", "2026-10-14" },
    last_month = { "2026-09-14", "2026-10-14" },
    last_quarter = { "2026-07-16", "2026-10-14" },
    last_year = { "2025-10-14", "2026-10-14" },
    this_week = { "2026-10-12", "2026-10-14" },
    this_month = { "2026-10-01", "2026-10-14" },
    this_quarter = { "2026-10-01", "2026-10-14" },
    this_year = { "2026-01-01", "2026-10-14" },
  }

  it("every built-in names its first and last day", function()
    package.loaded["github_stats.date_presets"] = nil
    local date_presets = require("github_stats.date_presets")
    for name, days in pairs(expected) do
      local start, end_date, err = date_presets.resolve(name, NOW)
      assert.is_nil(err, name)
      assert.are.same(days, { start, end_date }, name)
    end
  end)
end)

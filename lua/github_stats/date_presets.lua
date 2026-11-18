---@module 'github_stats.date_presets'
---@brief Date range preset resolver and calculator
---@description
--- Provides predefined and user-defined date range presets for quick access to common time periods.
--- Supports built-in presets (today, last_week, etc.) and custom user-defined ranges.
--- All preset functions return ISO date strings (YYYY-MM-DD) for start and end dates.

local M = {}

local str_format = string.format
local lib_presets = require("lib.lua.time.presets")

---Resolve a lib range constructor to the first and the last day it covers.
---@param range fun(now: integer): LibTimeRange
---@param open? boolean the range ends at now (this_month, last_week, ...): it covers today even
---  when resolved at 00:00:00 sharp
---@return fun(now?: integer): string, string
local function days_of(range, open)
  return function(now)
    return lib_presets.dates(range(now or os.time()), open)
  end
end

---Rolling window: from the local midnight `n` days ago until today.
---@param n integer
---@return fun(now?: integer): string, string
local function rolling(n)
  return days_of(function(now)
    return lib_presets.days_ago(n, now) --[[@as LibTimeRange]]
  end, true)
end

---Built-in preset resolver functions: each returns the first and the last ISO day
---(`YYYY-MM-DD`, both included). The calendar is lib.nvim's `lib.lua.time.presets`
---(local midnights by calendar arithmetic, weeks from Monday).
---@type table<string, fun(now?: integer): string, string>
local BUILTIN_PRESETS = {
  today = days_of(lib_presets.today, true),
  yesterday = days_of(lib_presets.yesterday),
  -- The `last_*` presets are rolling windows ending today, not calendar units.
  last_week = rolling(7),
  last_month = rolling(30),
  last_quarter = rolling(90),
  last_year = rolling(365),
  this_week = days_of(lib_presets.this_week, true),
  this_month = days_of(lib_presets.this_month, true),
  this_quarter = days_of(lib_presets.this_quarter, true),
  this_year = days_of(lib_presets.this_year, true),
}

---Get list of all available preset names
---@return string[] # Array of preset names
function M.list()
  local config = require("github_stats.config")
  -- Same fallback `config/init.lua`'s own `get_retention()`/
  -- `get_notification_level()` already use: `config.get()` is nil until
  -- `M.init()` has run, and date presets are enabled by default, so "not
  -- initialized yet" must not read as "disabled".
  local cfg = config.get() or require("github_stats.config.DEFAULTS")

  if not cfg.date_presets or not cfg.date_presets.enabled then
    return {}
  end

  local presets = {}

  -- Add built-in presets if enabled
  if cfg.date_presets.builtins then
    for _, name in ipairs(cfg.date_presets.builtins) do
      if BUILTIN_PRESETS[name] then
        table.insert(presets, name)
      end
    end
  end

  -- Add custom presets
  if cfg.date_presets.custom then
    for name, _ in pairs(cfg.date_presets.custom) do
      table.insert(presets, name)
    end
  end

  table.sort(presets)
  return presets
end

---Resolve preset name to date range
---@param preset_name string Name of the preset
---@param now? integer Reference time of the built-in presets (default `os.time()`)
---@return string?, string?, string? # Start date, end date, or nil and error message
function M.resolve(preset_name, now)
  if not preset_name or preset_name == "" then
    return nil, nil, "Empty preset name"
  end

  local config = require("github_stats.config")
  -- See M.list() above for why this falls back to DEFAULT_CONFIG instead of
  -- treating "config.init() hasn't run yet" as "disabled".
  local cfg = config.get() or require("github_stats.config.DEFAULTS")

  if not cfg.date_presets or not cfg.date_presets.enabled then
    return nil, nil, "Date presets are disabled"
  end

  -- Try built-in presets first
  local builtin_resolver = BUILTIN_PRESETS[preset_name]
  if builtin_resolver then
    local ok, start_date, end_date = pcall(builtin_resolver, now)
    if ok then
      return start_date, end_date, nil
    else
      return nil, nil, str_format("Built-in preset '%s' failed: %s", preset_name, start_date)
    end
  end

  -- Try custom presets
  if cfg.date_presets.custom and cfg.date_presets.custom[preset_name] then
    local custom_resolver = cfg.date_presets.custom[preset_name]

    if type(custom_resolver) ~= "function" then
      return nil, nil, str_format("Custom preset '%s' is not a function", preset_name)
    end

    local ok, start_date, end_date = pcall(custom_resolver)
    if ok then
      -- Validate returned dates
      if type(start_date) ~= "string" or type(end_date) ~= "string" then
        return nil, nil, str_format("Custom preset '%s' did not return two strings", preset_name)
      end

      -- Validate ISO date format
      if not start_date:match("^%d%d%d%d%-%d%d%-%d%d$") or not end_date:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return nil, nil, str_format("Custom preset '%s' returned invalid date format", preset_name)
      end

      return start_date, end_date, nil
    else
      return nil, nil, str_format("Custom preset '%s' failed: %s", preset_name, start_date)
    end
  end

  return nil, nil, str_format("Unknown preset: %s", preset_name)
end

---Check if a string is a preset name (not an ISO date)
---@param str string String to check
---@return boolean # True if string is a preset name
function M.is_preset(str)
  if not str or str == "" then
    return false
  end

  -- If it matches ISO date format, it's not a preset
  if str:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return false
  end

  -- Check if it's in the list of available presets
  local presets = M.list()
  for _, preset in ipairs(presets) do
    if preset == str then
      return true
    end
  end

  return false
end

return M

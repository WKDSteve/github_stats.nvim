---@module 'github_stats.config'
---@brief Configuration management
---@description
--- Handles loading, validation, and access to user configuration.
--- Configuration is stored in `<config_dir>/config.json`: the data repository's clone in remote mode
--- (`github_stats.remote`), else `config_dir` (default `stdpath("config")/lua/plugins/github-stats`).
---
--- The values come from `lib.lua.config.new` with two layers on top of `DEFAULTS`, lowest first:
--- `"file"` (config.json, which the plugin writes on the first run) and `"setup"` (the table passed
--- to `setup()`, which wins: LUA-87). Every change recomputes the config from the defaults, so nothing
--- shares a table with `DEFAULTS` and an option dropped from `setup()` is gone. A key nobody knows or
--- a value of the wrong type is reported (with a did-you-mean hint) and left out, so the default
--- applies: this used to be "reported, but kept as given", which let a mistyped `token_source` reach
--- the fetcher. `config_dir` / `data_dir` are paths, not options: they are taken out of the setup
--- table before it becomes a layer.

local M = {}

local fn = vim.fn
local loop = vim.uv or vim.loop
local str_format = string.format

-- No prefix: every M.notify() call site already inlines its own
-- "[github-stats] " text, so a lib.nvim prefix here would double it.
local notifier = require("lib.nvim.notify").create("")

---@type GHStats.Config?
local config = nil

---Default configuration
---@type GHStats.Config
local DEFAULT_CONFIG = require("github_stats.config.DEFAULTS")

local lib_config = require("lib.lua.config")

---The two layers over `DEFAULT_CONFIG`. `token_file` and `digest_dir` have no default (unset means "not
---used" / `stdpath("data")/github_stats.nvim`), so they are allowed without one. `notify` is looked up
---when it is called, `M.notify` is defined further down.
local store = lib_config.new(DEFAULT_CONFIG, {
  name = "github_stats",
  layers = { "file", "setup" },
  optional = { token_file = "string", digest_dir = "string" },
  notify = function(message)
    M.notify("[github-stats] " .. message, "warn")
  end,
})

---Resolved paths. Empty until `M.setup()` fills them; every reader below
---runs after that, and says so with an `assert` rather than assuming it.
---@class GHStats.Config.Paths
---@field config_dir string?
---@field config_file string?
---@field data_dir string?

---@type GHStats.Config.Paths
local PATHS = {
  config_dir = nil,
  config_file = nil,
  data_dir = nil,
}

---@internal
---Get config directory path
---@param custom_path? string Custom config directory
---@return string
local function resolve_config_dir(custom_path)
  if custom_path then
    return fn.expand(custom_path)
  end

  local config_path = fn.stdpath("config")
  return config_path .. "/lua/plugins/github-stats"
end

---@internal
---Get data directory path
---@param custom_path? string Custom data directory
---@param config_dir string Config directory
---@return string
local function resolve_data_dir(custom_path, config_dir)
  if custom_path then
    return fn.expand(custom_path)
  end

  return config_dir .. "/data"
end

---@internal
---Create default config file if it doesn't exist
---@return boolean, string? # Success flag, error message
local function ensure_config_exists()
  local config_dir = assert(PATHS.config_dir, "setup() resolves the config paths first")
  local config_file = assert(PATHS.config_file, "setup() resolves the config paths first")

  -- Create directory if needed
  local stat = loop.fs_stat(config_dir)
  if not stat then
    local ok, err = pcall(fn.mkdir, config_dir, "p")
    if not ok then
      return false, str_format("Failed to create config directory: %s", err)
    end
  end

  -- Create default config if file doesn't exist
  stat = loop.fs_stat(config_file)
  if not stat then
    local ok, err = require("lib.nvim.fs.json").write(config_file, DEFAULT_CONFIG)
    if not ok then
      return false, str_format("Failed to create config file: %s", err)
    end
  end

  return true, nil
end

---@internal
---Read config.json into the `"file"` layer.
---@return boolean, string? # Success flag, error message
local function load_config_file()
  local parsed, err = require("lib.nvim.fs.json").read(PATHS.config_file)
  if type(parsed) ~= "table" then
    return false, str_format("Failed to load config.json: %s", err or "not an object")
  end
  store.layer("file", parsed)
  return true, nil
end

---Initialize configuration from setup() or config.json
---@param opts? GHStats.SetupOptions Setup options
---@return boolean, string? # Success flag, error message
function M.init(opts)
  opts = opts or {}

  -- Resolve paths
  PATHS.config_dir = resolve_config_dir(opts.config_dir)
  PATHS.config_file = PATHS.config_dir .. "/config.json"
  PATHS.data_dir = resolve_data_dir(opts.data_dir, PATHS.config_dir)

  -- Base: config.json when it exists, otherwise the defaults (creating the
  -- file on the way, as before).
  local stat = loop.fs_stat(PATHS.config_file)
  if not stat then
    local ok, err = ensure_config_exists()
    if not ok then
      return false, err
    end
  end

  local ok_file, err_file = load_config_file()
  if not ok_file then
    return false, err_file
  end

  -- setup() wins over the file.
  --
  -- It used to be the other way around, and only for `repos`: setup options
  -- were honoured *only* when `opts.repos` was non-empty, and dropped whole
  -- otherwise. So `setup({ dashboard = { header_width = 100 } })` silently did
  -- nothing as soon as a config.json existed -- which it always does, since
  -- the plugin writes one on first run. Explicit code beating a generated
  -- file is both the conventional order and the only one that makes every
  -- option reachable from setup().
  --
  -- The two paths are not options: they were merged into the config before
  -- (and showed up in `config.get()`), now only the options become the layer.
  local setup_opts = {}
  for key, value in pairs(opts) do
    if key ~= "config_dir" and key ~= "data_dir" then
      setup_opts[key] = value
    end
  end
  store.setup(next(setup_opts) ~= nil and setup_opts or nil)
  config = store.get()
  return true, nil
end

---What the layers dropped (unknown keys, values of the wrong type), for `:checkhealth`.
---@return string[]
function M.issues()
  return store.issues()
end

---Get storage root directory
---@return string
function M.get_storage_root()
  return PATHS.data_dir
end

---Get config directory
---@return string
function M.get_config_dir()
  return PATHS.config_dir
end

---Get current configuration
---@return GHStats.Config?
function M.get()
  return config
end

---@type string[]
local discovered_repos = {}

---Set the repositories discovered via `watch_users` (replaces any previous set)
---@param repos string[] Repository names ("owner/repo") discovered from watch_users
---@return nil
function M.set_discovered_repos(repos)
  discovered_repos = repos or {}
end

---Get list of repositories: the explicitly configured `repos` plus any
---repositories discovered via `watch_users`, deduped (explicit list first,
---so its configured order is preserved).
---@return string[]
function M.get_repos()
  if not config then
    return {}
  end

  local static_repos = config.repos or {}
  if #discovered_repos == 0 then
    -- Shallow copy: static_repos is the live config.repos array. Handing it
    -- out by reference lets a caller's in-place table.sort() (e.g.
    -- github_stats.dashboard.render, which sorts state.repos on every
    -- render) permanently reorder the stored config as a side effect.
    return vim.list_slice(static_repos)
  end

  local combined = {}
  for _, repo in ipairs(static_repos) do
    table.insert(combined, repo)
  end
  for _, repo in ipairs(discovered_repos) do
    table.insert(combined, repo)
  end

  return require("lib.lua.tables").dedup_list(combined)
end

---Get GitHub token from configured source
---@return string?, string? # Token or nil, error message
function M.get_token()
  if not config then
    return nil, "Configuration not loaded"
  end

  if config.token_source == "env" then
    local env_var = config.token_env_var or "GITHUB_TOKEN"
    local token = vim.env[env_var]
    if not token or token == "" then
      return nil, str_format("Environment variable %s not set or empty", env_var)
    end
    return token, nil
  elseif config.token_source == "file" then
    if not config.token_file then
      return nil, "token_file not specified in config"
    end

    local file_path = fn.expand(config.token_file)
    local ok, content = pcall(fn.readfile, file_path)
    if not ok then
      return nil, str_format("Failed to read token file: %s", content)
    end

    if #content == 0 then
      return nil, "Token file is empty"
    end

    local token = vim.trim(content[1])
    if token == "" then
      return nil, "Token is empty or whitespace"
    end

    return token, nil
  else
    return nil, str_format("Invalid token_source: %s", config.token_source)
  end
end

---Get retention settings (clones/views archive cutoff, referrers/paths
---prune window). Falls back to DEFAULT_CONFIG.retention before init() or if
---the loaded config omits the section entirely.
---@return GHStats.RetentionConfig
function M.get_retention()
  if not config or not config.retention then
    return lib_config.copy(DEFAULT_CONFIG.retention)
  end
  return config.retention
end

---Get notification level setting
---@return "all"|"errors"|"silent"
function M.get_notification_level()
  if not config then
    return "all"
  end
  return config.notification_level or "all"
end

---Send notification based on configured level
---@param message string Notification message
---@param level "info"|"warn"|"error" Log level
function M.notify(message, level)
  local notification_level = M.get_notification_level()

  -- Silent mode: no notifications at all
  if notification_level == "silent" then
    return
  end

  -- Errors-only mode: only show warnings and errors
  if notification_level == "errors" then
    if level ~= "warn" and level ~= "error" then
      return
    end
  end

  -- All mode: show everything (default)
  local vim_level = vim.log.levels.INFO
  if level == "warn" then
    vim_level = vim.log.levels.WARN
  elseif level == "error" then
    vim_level = vim.log.levels.ERROR
  end

  notifier.notify(message, vim_level)
end

return M

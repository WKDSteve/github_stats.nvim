---@module 'github_stats.api'
---@brief Asynchronous GitHub API client
---@description
--- Fetches traffic statistics from GitHub REST API.
--- Supports clones, views, referrers, and paths endpoints.
--- All operations are async (lib.nvim.net.github on net.curl) to avoid blocking UI.

local config = require("github_stats.config")
local github = require("lib.nvim.net.github")

local M = {}

local schedule = vim.schedule

---Available metric endpoints
---@type table<string, string>
local ENDPOINTS = {
  clones = "/repos/%s/traffic/clones",
  views = "/repos/%s/traffic/views",
  referrers = "/repos/%s/traffic/popular/referrers",
  paths = "/repos/%s/traffic/popular/paths",
}

---@internal
---Build the request path for a metric
---@param repo string Repository in "owner/repo" format
---@param metric string Metric type
---@return string|nil, string? # API path or nil, error message
local function build_path(repo, metric)
  local endpoint = ENDPOINTS[metric]
  if not endpoint then
    return nil, string.format("Unknown metric: %s", metric)
  end

  return string.format(endpoint, repo), nil
end

---@internal
---Request `path` via lib.nvim.net.github and reduce its result to this
---module's own (data, err) contract. The shared client carries the GitHub
---rules (a 3xx other than 304, a 4xx/5xx, a 200 whose body is a
---`{"message": ...}` error object, an exhausted rate limit and an
---undecodable body are all errors; the token goes through curl's `-K -`,
---never argv); its error text is passed on as is. Needs lib.nvim ccd30b5 or
---newer (health.lua checks it); a redirect is an error since 7ab808d.
---@param path string API path (`/repos/...`), resolved against the GitHub API base
---@param token string|nil GitHub token; the request is unauthenticated when nil
---@param callback fun(data: table|nil, err: string|nil)
local function fetch_json(path, token, callback)
  local cfg = config.get() or {}

  github.request(path, {
    token = token,
    timeout_ms = cfg.api_timeout_ms or 15000,
    max_bytes = cfg.api_max_response_bytes or (5 * 1024 * 1024),
  }, function(result, err)
    -- github.request already runs this on the main loop.
    if not result then
      callback(nil, err)
      return
    end
    callback(result.data, nil)
  end)
end

---Fetch metric data asynchronously
---@param repo string Repository identifier
---@param metric string Metric type
---@param callback fun(data: table|nil, error: string|nil) Completion callback
function M.fetch_metric_async(repo, metric, callback)
  -- Validate inputs
  if type(repo) ~= "string" or repo == "" then
    schedule(function()
      callback(nil, "Invalid repository identifier")
    end)
    return
  end

  if type(metric) ~= "string" or not ENDPOINTS[metric] then
    schedule(function()
      callback(nil, string.format("Invalid metric: %s", metric))
    end)
    return
  end

  -- Get token
  local token, token_err = config.get_token()
  if not token then
    schedule(function()
      callback(nil, string.format("Token error: %s", token_err))
    end)
    return
  end

  -- Build path
  local path, path_err = build_path(repo, metric)
  if not path then
    schedule(function()
      callback(nil, path_err)
    end)
    return
  end

  fetch_json(path, token, callback)
end

--- CDX: no in-repo callers (fetcher.lua fetches metrics individually); kept
--- as public API on `github_stats.api` since a user config could call it directly.
---Fetch all configured metrics for a repository
---@param repo string Repository identifier
---@param callback fun(results: table<string, {data: table|nil, error: string|nil}>) Completion callback
function M.fetch_all_metrics(repo, callback)
  local metrics = { "clones", "views", "referrers", "paths" }
  local results = {}
  local completed = 0

  local function check_completion()
    completed = completed + 1
    if completed == #metrics then
      schedule(function()
        callback(results)
      end)
    end
  end

  for _, metric in ipairs(metrics) do
    M.fetch_metric_async(repo, metric, function(data, err)
      results[metric] = { data = data, error = err }
      check_completion()
    end)
  end
end

---Maximum pages to follow when listing a user's repositories.
---
---100 repos/page, so the default 30 covers 3000 repos. Configurable because
---this cap *silently drops data*: past it, a watched user's later repos are
---simply not tracked, and nothing in the UI distinguishes that from the user
---not having them. `watch_users` on an account with more than 3000 public
---repos is unusual but not impossible.
---@return integer
local function max_user_repo_pages()
  local ok, cfg_mod = pcall(require, "github_stats.config")
  if not ok or type(cfg_mod.get) ~= "function" then
    return 30
  end
  local n = (cfg_mod.get() or {}).max_user_repo_pages
  return (type(n) == "number" and n > 0) and n or 30
end

---List all public repositories for a GitHub user, following pagination
---
---The paging itself (sequencing, page cap, keeping what arrived before a failing page) is
---`lib.nvim.net.paginate`; this only turns one page into its `full_name`s.
---@param username string GitHub username
---@param callback fun(repo_names: string[]|nil, err: string?) Completion callback
function M.list_user_repos(username, callback)
  if type(username) ~= "string" or username == "" then
    schedule(function()
      callback(nil, "Invalid username")
    end)
    return
  end

  -- Authenticate if a token is available (raises the rate limit); the
  -- endpoint itself works unauthenticated for public repos too.
  local token = config.get_token()

  require("lib.nvim.net.paginate").run({
    per_page = 100,
    max_pages = max_user_repo_pages(),
    fetch = function(page, done)
      local path = string.format("/users/%s/repos?per_page=100&page=%d", username, page)
      fetch_json(path, token, function(data, err)
        if not data then
          done(nil, err or "no data")
        elseif type(data) ~= "table" then
          done(nil, "Unexpected response shape (expected array)")
        else
          done(data)
        end
      end)
    end,
    on_done = function(r)
      local names = {}
      for _, repo in ipairs(r.items) do
        if type(repo) == "table" and type(repo.full_name) == "string" then
          table.insert(names, repo.full_name)
        end
      end
      if r.err and not r.partial then
        -- First page failed outright: propagate the error, nothing to return.
        callback(nil, r.err)
      else
        -- Complete, capped, or a later page failed after some succeeded: what we have.
        callback(names, r.err)
      end
    end,
  })
end

-- CDX: no in-repo callers; kept as public API on `github_stats.api` for
-- optional user-side monitoring.
---Rate limit info retrieval (optional, for monitoring)
---@param callback fun(data: table|nil, error: string|nil)
function M.get_rate_limit(callback)
  local token, token_err = config.get_token()
  if not token then
    schedule(function()
      callback(nil, token_err)
    end)
    return
  end

  fetch_json("/rate_limit", token, callback)
end

return M

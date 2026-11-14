---@module 'github_stats.remote.wizard'
---@brief The setup guide (`:GithubStats setup`, and once by itself on the first start): where the history lives, and everything remote mode needs.
---@description
--- A linear flow on `lib.nvim.ui.kit.async`: each question is a kit dialog, each step checks first whether it is
--- already done, so running the guide again resumes where it stopped (a missing secret, a clone on a new machine).
---
---   1. Where the history lives: remote (recommended), local, or later.
---   2. remote: the GitHub CLI (`gh`) is there and logged in.
---   3. The data repository: an existing one is cloned; a new one is created private, optionally with the local
---      history this machine already has; without one, the guide asks what to track (the login's public
---      repositories, a typed list, or nothing yet).
---      The workflow runs the code this plugin pins (`remote.COLLECT_REF`); an older pin is offered for an update.
---   4. The workflow's secret `GH_STATS_TOKEN`: set from the configured token, or the user does it (shown how).
---   5. Optionally the first run of the workflow, right now.
---
--- `M.ui` holds the dialog functions so specs can answer them; everything external runs through `remote.proc`.

local M = {}

local remote = require("github_stats.remote")
local proc = require("github_stats.remote.proc")

---The dialogs. Specs replace the fields.
M.ui = {
  select = function(opts)
    return require("lib.nvim.ui.kit.async").select(opts)
  end,
  input = function(opts)
    return require("lib.nvim.ui.kit.async").input(opts)
  end,
  confirm = function(opts)
    return require("lib.nvim.ui.kit.async").confirm(opts)
  end,
  note = function(opts)
    return require("lib.nvim.ui.kit").note(opts)
  end,
}

local TITLE = "github_stats.nvim setup"

local CHOICES = {
  "Remote: GitHub Actions collects daily, every machine pulls (recommended)",
  "Local: this Neovim fetches into its own folder",
  "Later",
}

---@type boolean
local running = false

---@param lines string[]
---@return nil
local function note(lines)
  M.ui.note({ title = TITLE, message = lines })
end

---@return nil
local function reload()
  local ok, gs = pcall(require, "github_stats")
  if ok and gs.reload_storage then
    gs.reload_storage()
  end
end

---@param cmd string[]
---@param opts? GHStats.Remote.ProcOpts
---@return GHStats.Remote.ProcResult
local function run(cmd, opts)
  return proc.run(cmd, opts)
end

---The GitHub login of `gh`, or nil and the lines that explain what is missing.
---@return string|nil login
---@return string[]|nil help
local function gh_login()
  if vim.fn.executable("gh") ~= 1 then
    return nil,
      {
        "Remote mode creates and reads the data repository with the GitHub CLI.",
        "",
        "  1. Install it: https://cli.github.com",
        "  2. Log in:     gh auth login",
        "  3. Run :GithubStats setup again.",
      }
  end
  local res = run({ "gh", "api", "user", "--jq", ".login" }, { timeout_ms = 30000 })
  local login = vim.trim(res.stdout)
  if not res.ok or login == "" then
    return nil,
      {
        "The GitHub CLI is not logged in (" .. proc.reason(res) .. ").",
        "",
        "  gh auth login",
        "",
        "Then run :GithubStats setup again.",
      }
  end
  return login, nil
end

---@param repo string
---@return boolean
local function repo_exists(repo)
  return run({ "gh", "repo", "view", repo, "--json", "name" }, { timeout_ms = 30000 }).ok
end

---@param repo string
---@return boolean|nil present nil when it could not be read
local function secret_present(repo)
  local res = run({ "gh", "secret", "list", "-R", repo, "--json", "name" }, { timeout_ms = 30000 })
  if not res.ok then
    return nil
  end
  local ok, list = pcall(vim.json.decode, res.stdout)
  if not ok or type(list) ~= "table" then
    return nil
  end
  for _, entry in ipairs(list) do
    if type(entry) == "table" and entry.name == remote.SECRET_NAME then
      return true
    end
  end
  return false
end

---Where this machine's history is when it fetches itself: offered for taking over into a new data repository.
---@return string|nil dir the folder, when it holds a history
---@return integer files
local function local_history()
  local config = require("github_stats.config")
  local dir = config.get_config_dir and config.get_config_dir()
  local data = config.get_storage_root and config.get_storage_root()
  if not dir or not data or vim.fn.isdirectory(data) == 0 then
    return nil, 0
  end
  local files = 0
  for _, kind in vim.fs.dir(data, { depth = math.huge }) do
    if kind == "file" then
      files = files + 1
    end
  end
  if files == 0 then
    return nil, 0
  end
  return dir, files
end

---Step 4: the workflow's secret.
---@param repo string
---@return boolean set the secret is there now
local function ensure_secret(repo)
  local present = secret_present(repo)
  if present then
    return true
  end
  local how = {
    "The workflow needs the secret " .. remote.SECRET_NAME .. ": a token that can read the traffic",
    "of your repositories (classic token: scope 'repo'; fine-grained: 'Administration: read').",
    "",
    "  gh secret set " .. remote.SECRET_NAME .. " -R " .. repo,
    "",
    "Then run :GithubStats setup again to start the first run.",
  }
  local token = require("github_stats.config").get_token()
  if not token then
    note(how)
    return false
  end
  local answer = M.ui.confirm({
    question = ("Set the secret %s of %s from the token this plugin uses?"):format(remote.SECRET_NAME, repo),
    choices = { "Use my token", "I set it myself" },
  })
  if answer ~= "Use my token" then
    note(how)
    return false
  end
  -- The token goes through stdin, never onto a command line.
  local res = run({ "gh", "secret", "set", remote.SECRET_NAME, "-R", repo }, { input = token, timeout_ms = 30000 })
  if not res.ok then
    note(vim.list_extend({ "Setting the secret failed: " .. proc.reason(res), "" }, how))
    return false
  end
  return true
end

---What a new data repository without a taken-over history tracks: all public repositories of the login
---(`watch_users`), a typed list (`repos`), or nothing yet.
---@param login string
---@return table|nil config values for the fresh config.json; nil when the user left the guide
local function choose_tracked(login)
  local choices = {
    ("All public repositories of %s (watch_users)"):format(login),
    "A list I type (owner/name, comma-separated)",
    "None yet: I edit config.json later",
  }
  local _, idx = M.ui.select({ title = "Which repositories should the workflow track?", selection = choices })
  if idx == nil then
    return nil
  end
  if idx == 1 then
    return { watch_users = { login } }
  end
  if idx == 3 then
    return {}
  end
  local typed, cancelled = M.ui.input({ prompt = "Repositories (owner/name, comma-separated)", default = "" })
  if cancelled or not typed then
    return nil
  end
  local repos, bad = {}, {}
  for name in typed:gmatch("[^,%s]+") do
    if remote.valid_repo(name) then
      repos[#repos + 1] = name
    else
      bad[#bad + 1] = name
    end
  end
  if #bad > 0 then
    note({ "Not owner/name: " .. table.concat(bad, ", "), "Run :GithubStats setup again." })
    return nil
  end
  return { repos = repos }
end

---Step 3: clone the existing data repository or create a new one. Returns the storage now in use.
---@param s GHStats.Storage
---@param repo string
---@param login string
---@return boolean ok
local function ensure_repository(s, repo, login)
  if vim.fn.isdirectory(s.dir .. "/.git") == 1 then
    return true
  end
  if repo_exists(repo) then
    local yes = M.ui.confirm({ question = ("%s exists. Clone it to %s?"):format(repo, s.dir) })
    if not yes then
      return false
    end
    local result = require("lib.nvim.ui.kit.async").await(function(deliver)
      remote.clone(vim.tbl_extend("force", {}, s, { repo = repo }), function(ok, err)
        deliver({ ok = ok, err = err })
      end)
    end)
    if not result.ok then
      note({ "Cloning " .. repo .. " failed:", "", "  " .. tostring(result.err) })
      return false
    end
    return true
  end

  local seed, files = local_history()
  local seed_dir = nil
  if seed then
    local answer = M.ui.confirm({
      question = ("Take over the history this machine already has (%d files in %s)?"):format(files, seed),
      choices = { "Take it over", "Start empty" },
    })
    if answer == nil then
      return false
    end
    seed_dir = answer == "Take it over" and seed or nil
  end
  -- A taken-over history brings its own config.json; a fresh one needs to know what to track.
  local tracked = nil
  if not seed_dir then
    tracked = choose_tracked(login)
    if tracked == nil then
      return false
    end
  end
  local yes = M.ui.confirm({
    question = ("Create the private repository %s (clone in %s)?"):format(repo, s.dir),
  })
  if not yes then
    return false
  end
  local ok, err, copied = require("github_stats.remote.create").create({
    repo = repo,
    dir = s.dir,
    seed_dir = seed_dir,
    config = tracked,
  })
  if not ok then
    note({ "Creating " .. repo .. " failed:", "", "  " .. tostring(err) })
    return false
  end
  if copied > 0 then
    require("github_stats.config").notify(("[github-stats] %d files of history taken over into %s"):format(copied, repo), "info")
  end
  return true
end

---Step 3b: the workflow runs the code this plugin pins (`remote.COLLECT_REF`); an older pin (or `main`, as the first
---data repositories had) is offered for an update. Declining keeps the workflow as it is.
---@param s GHStats.Storage
---@param repo string
---@return nil
local function ensure_pin(s, repo)
  local outdated, ref = remote.workflow_outdated(s)
  if not outdated then
    return
  end
  local yes = M.ui.confirm({
    question = ("The workflow of %s runs github_stats.nvim at %s. Pin it to %s?"):format(repo, tostring(ref), remote.COLLECT_REF),
  })
  if not yes then
    return
  end
  local result = require("lib.nvim.ui.kit.async").await(function(deliver)
    remote.update_workflow(s, function(ok, err)
      deliver({ ok = ok, err = err })
    end)
  end)
  if not result.ok then
    note({
      "Updating the workflow failed: " .. tostring(result.err),
      "",
      "Pushing a workflow file needs a token with the 'workflow' scope (gh auth refresh -s workflow).",
    })
  end
end

---The guide itself (inside a kit.async coroutine).
---@param opts { auto?: boolean }
---@return nil
local function flow(opts)
  local s = remote.current() or remote.resolve(nil)

  if remote.status(s) ~= "ready" then
    local _, idx = M.ui.select({ title = "Where should the GitHub traffic history live?", selection = CHOICES })
    if idx == nil or idx == 3 then
      remote.write_state({ deferred = true })
      if opts.auto then
        require("github_stats.config").notify("[github-stats] Setup postponed; :GithubStats setup whenever you like", "info")
      end
      return
    end
    if idx == 2 then
      remote.write_state({ mode = "local", deferred = false })
      reload()
      note({
        "Local mode: this Neovim fetches once a day into its own folder.",
        "Remote mode stays one command away: :GithubStats setup",
      })
      return
    end
  end

  local login, help = gh_login()
  if not login then
    note(help or {})
    return
  end

  local repo = s.repo or remote.repo_of(s)
  if not repo then
    local typed, cancelled = M.ui.input({
      prompt = "Data repository (owner/name)",
      default = login .. "/" .. remote.DEFAULT_REPO_NAME,
    })
    if cancelled or not typed then
      return
    end
    typed = vim.trim(typed)
    if not remote.valid_repo(typed) then
      note({ "Not a repository name: " .. typed, "It looks like owner/name." })
      return
    end
    repo = typed
  end

  if not ensure_repository(s, repo, login) then
    return
  end
  remote.write_state({ mode = "remote", repo = repo, dir = s.dir, deferred = false })
  reload()

  ensure_pin(s, repo)

  if not ensure_secret(repo) then
    return
  end

  local go = M.ui.confirm({ question = "Start the workflow now, so the first data arrives in a minute or two?" })
  if go then
    local res = run({ "gh", "workflow", "run", remote.WORKFLOW_FILE, "-R", repo }, { timeout_ms = 30000 })
    if not res.ok then
      note({ "Starting the workflow failed: " .. proc.reason(res), "It runs by itself every day at 04:23 UTC." })
      return
    end
  end
  note({
    "Remote mode is set up: " .. repo,
    "",
    "  - The workflow collects every day; this Neovim pulls on start and every hour.",
    "  - :GithubStats sync pulls now; :GithubStats fetch starts the workflow.",
    "  - On another machine: the same repository is found by :GithubStats setup,",
    "    or put storage = { repo = '" .. repo .. "' } into the plugin spec.",
  })
end

---Open the guide. `auto`: opened by itself on the first start (a dismissal is then remembered as "later").
---@param opts? { auto?: boolean }
---@return nil
function M.open(opts)
  if running then
    return
  end
  running = true
  proc.flow(function()
    local ok, err = pcall(flow, opts or {})
    running = false
    if not ok then
      require("github_stats.config").notify(("[github-stats] Setup failed: %s"):format(tostring(err)), "error")
    end
  end)
end

---Whether the guide should open by itself: remote mode by default, nothing decided on this machine yet, and a UI.
---@param s GHStats.Storage
---@return boolean
function M.should_auto_open(s)
  return s.mode == "remote"
    and not s.explicit_mode
    and remote.status(s) == "unset"
    and not s.deferred
    and #vim.api.nvim_list_uis() > 0
end

return M

---@diagnostic disable: undefined-global

-- Specs for github_stats.remote (where the history lives), remote.create (a new data repository) and
-- remote.wizard (the setup guide).
--
-- No process is started: `remote.proc.exec` is replaced by a script of answers, keyed by the command line. The state
-- file and the clone folder live below a temp folder (`remote.state_file`/`default_dir` are replaced too).

describe("remote", function()
  local remote, proc, tmp
  local real_exec, real_state_file, real_default_dir
  local calls, answers

  ---Answer a command whose line starts with `prefix` (joined by spaces).
  ---@param prefix string
  ---@param res table|fun(cmd: string[], opts: table|nil): table
  local function answer(prefix, res)
    answers[#answers + 1] = { prefix = prefix, res = res }
  end

  ---@param cmd string[]
  ---@return string
  local function line(cmd)
    return table.concat(cmd, " ")
  end

  local function fake_exec(cmd, opts, on_done)
    calls[#calls + 1] = { cmd = cmd, opts = opts }
    local text = line(cmd)
    for i = #answers, 1, -1 do
      local a = answers[i]
      if text:sub(1, #a.prefix) == a.prefix then
        local res = type(a.res) == "function" and a.res(cmd, opts) or a.res
        on_done(vim.tbl_extend("force", { ok = true, code = 0, stdout = "", stderr = "" }, res))
        return
      end
    end
    on_done({ ok = true, code = 0, stdout = "", stderr = "" })
  end

  ---@param prefix string
  ---@return table|nil
  local function call_of(prefix)
    for _, c in ipairs(calls) do
      if line(c.cmd):sub(1, #prefix) == prefix then
        return c
      end
    end
    return nil
  end

  before_each(function()
    for _, name in ipairs({
      "github_stats.remote",
      "github_stats.remote.proc",
      "github_stats.remote.create",
      "github_stats.remote.wizard",
    }) do
      package.loaded[name] = nil
    end
    tmp = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(tmp, "p")
    proc = require("github_stats.remote.proc")
    remote = require("github_stats.remote")
    real_exec = proc.exec
    real_state_file, real_default_dir = remote.state_file, remote.default_dir
    remote.state_file = function()
      return tmp .. "/state.json"
    end
    remote.default_dir = function()
      return tmp .. "/vault"
    end
    calls, answers = {}, {}
    proc.exec = fake_exec
  end)

  after_each(function()
    proc.exec = real_exec
    remote.state_file, remote.default_dir = real_state_file, real_default_dir
    remote.set_current(nil)
    vim.fn.delete(tmp, "rf")
  end)

  describe("resolve", function()
    it("is remote by default, and unset while no repository is known", function()
      local s, err = remote.resolve({}, {})
      assert.is_nil(err)
      assert.equals("remote", s.mode)
      assert.is_false(s.explicit_mode)
      assert.equals(tmp .. "/vault", s.dir)
      assert.equals(60, s.pull_interval_minutes)
      assert.equals("unset", remote.status(s))
    end)

    it("takes the mode alone as a string, or a table", function()
      assert.equals("local", remote.resolve({ storage = "local" }, {}).mode)
      local s = remote.resolve({ storage = { mode = "remote", repo = "me/data", pull_interval_minutes = 5 } }, {})
      assert.equals("remote", s.mode)
      assert.is_true(s.explicit_mode)
      assert.equals("me/data", s.repo)
      assert.equals(5, s.pull_interval_minutes)
      assert.equals("clone", remote.status(s))
    end)

    it("is local when setup() names its own folders (the user manages them)", function()
      assert.equals("local", remote.resolve({ config_dir = tmp .. "/cfg" }, {}).mode)
      assert.equals("local", remote.resolve({ data_dir = tmp .. "/data" }, {}).mode)
      assert.equals("remote", remote.resolve({ config_dir = tmp .. "/cfg", storage = "remote" }, {}).mode)
    end)

    it("falls back to the answer of the guide, below what setup() says", function()
      local state = { mode = "local", repo = "me/data", dir = tmp .. "/elsewhere", deferred = true }
      local s = remote.resolve({}, state)
      assert.equals("local", s.mode)
      assert.equals("me/data", s.repo)
      assert.equals(tmp .. "/elsewhere", s.dir)
      assert.is_true(s.deferred)
      assert.equals("remote", remote.resolve({ storage = "remote" }, state).mode)
    end)

    it("reports and ignores a wrong mode, repository or type", function()
      local s, err = remote.resolve({ storage = "cloud" }, {})
      assert.equals("remote", s.mode)
      assert.matches("storage.mode", err)
      local s2, err2 = remote.resolve({ storage = { repo = "no slash" } }, {})
      assert.is_nil(s2.repo)
      assert.matches("owner/name", err2)
      local _, err3 = remote.resolve({ storage = 42 }, {})
      assert.matches("string or a table", err3)
      assert.is_nil(remote.resolve({}, { repo = "bad repo" }).repo)
    end)

    it("is ready once the clone exists", function()
      vim.fn.mkdir(tmp .. "/vault/.git", "p")
      local s = remote.resolve({}, {})
      assert.equals("ready", remote.status(s))
      remote.set_current(s)
      assert.is_true(remote.active())
      remote.set_current(remote.resolve({ storage = "local" }, {}))
      assert.is_false(remote.active())
    end)
  end)

  describe("state file", function()
    it("merges, and a false value removes a key (deferred keeps false)", function()
      remote.write_state({ mode = "remote", repo = "me/data", deferred = true })
      remote.write_state({ repo = false, deferred = false })
      assert.same({ mode = "remote", deferred = false }, remote.read_state())
    end)
  end)

  describe("proc.run", function()
    it("blocks outside a coroutine and hands back the result", function()
      answer("git status", { stdout = "M config.json\n" })
      local res = proc.run({ "git", "status" })
      assert.is_true(res.ok)
      assert.equals("M config.json\n", res.stdout)
    end)

    it("suspends a kit.async coroutine until the command is done", function()
      answer("gh api", { stdout = "me\n" })
      local got
      proc.flow(function()
        got = proc.run({ "gh", "api", "user" }).stdout
      end)
      assert.equals("me\n", got)
    end)

    it("runs a real process: exit code, stdout and stderr arrive (the stub-free path)", function()
      proc.exec = real_exec
      local script = tmp .. "/echo.lua"
      vim.fn.writefile({
        "local got = io.stdin:read('*a')",
        "io.stdout:write('in=' .. got)",
        "io.stderr:write('err')",
        "os.exit(got == 'fail' and 3 or 0)",
      }, script)
      local cmd = { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", script }
      local bad = proc.run(cmd, { input = "fail", timeout_ms = 30000 })
      local fine = proc.run(cmd, { input = "secret", timeout_ms = 30000 })
      proc.exec = fake_exec
      assert.is_false(bad.ok)
      assert.equals(3, bad.code)
      assert.matches("err", bad.stderr)
      assert.is_true(fine.ok, fine.stderr)
      assert.equals("in=secret", fine.stdout)
    end)

    it("names the first line of what a failed command said", function()
      assert.equals("fatal: no", proc.reason({ ok = false, code = 1, stdout = "", stderr = "fatal: no\nmore" }))
      assert.equals("exit code 3", proc.reason({ ok = false, code = 3, stdout = "", stderr = "" }))
    end)
  end)

  describe("sync", function()
    local real_invalidate, real_refresh, invalidated

    before_each(function()
      vim.fn.mkdir(tmp .. "/vault/.git", "p")
      remote.set_current(remote.resolve({ storage = { repo = "me/data" } }, {}))
      local storage = require("github_stats.storage")
      real_invalidate = storage.invalidate
      invalidated = 0
      storage.invalidate = function()
        invalidated = invalidated + 1
      end
      local digest = require("github_stats.digest")
      real_refresh = digest.refresh_if_stale
      digest.refresh_if_stale = function() end
    end)

    after_each(function()
      require("github_stats.storage").invalidate = real_invalidate
      require("github_stats.digest").refresh_if_stale = real_refresh
    end)

    it("pulls fast-forward only, and drops what was read when something arrived", function()
      local head = 0
      answer("git -C " .. tmp .. "/vault rev-parse HEAD", function()
        head = head + 1
        return { stdout = "sha" .. head }
      end)
      local result
      remote.sync(function(ok, err, changed)
        result = { ok = ok, err = err, changed = changed }
      end, true)
      assert.same({ ok = true, changed = true }, result)
      assert.is_not_nil(call_of("git -C " .. tmp .. "/vault pull --ff-only"))
      assert.is_nil(call_of("git -C " .. tmp .. "/vault commit"))
      assert.equals(1, invalidated)
    end)

    it("commits and pushes a changed config.json first, rebased onto the workflow's commits", function()
      answer("git -C " .. tmp .. "/vault status --porcelain -- config.json", { stdout = " M config.json\n" })
      local done
      remote.sync(function(ok)
        done = ok
      end, true)
      assert.is_true(done)
      local commit = assert(call_of("git -C " .. tmp .. "/vault commit"))
      assert.equals("config.json", commit.cmd[#commit.cmd])
      assert.is_not_nil(call_of("git -C " .. tmp .. "/vault pull --rebase"))
      assert.is_not_nil(call_of("git -C " .. tmp .. "/vault push"))
      assert.equals(0, invalidated)
    end)

    it("reports a failed pull and keeps what was there", function()
      answer("git -C " .. tmp .. "/vault pull", { ok = false, code = 1, stderr = "fatal: not possible to fast-forward" })
      local result
      remote.sync(function(ok, err)
        result = { ok = ok, err = err }
      end, true)
      assert.is_false(result.ok)
      assert.matches("fast%-forward", result.err)
      assert.equals(0, invalidated)
    end)

    it("runs one sync at a time: a second caller gets the running one's result, git is asked once", function()
      local pending
      answer("git -C " .. tmp .. "/vault pull", function()
        return { held = true }
      end)
      local real = proc.exec
      proc.exec = function(cmd, opts, on_done)
        if line(cmd):find(" pull ", 1, true) and not pending then
          calls[#calls + 1] = { cmd = cmd, opts = opts }
          pending = function()
            on_done({ ok = true, code = 0, stdout = "", stderr = "" })
          end
          return
        end
        real(cmd, opts, on_done)
      end
      local results = {}
      remote.sync(function(ok)
        results[#results + 1] = ok
      end, true)
      remote.sync(function(ok)
        results[#results + 1] = ok
      end, true)
      assert.same({}, results)
      pending()
      assert.same({ true, true }, results)
      local pulls = 0
      for _, c in ipairs(calls) do
        if line(c.cmd):find(" pull ", 1, true) then
          pulls = pulls + 1
        end
      end
      assert.equals(1, pulls)
      -- and the next one starts afresh
      remote.sync(function(ok)
        results[#results + 1] = ok
      end, true)
      assert.equals(3, #results)
    end)

    it("leaves compacting to the workflow: :GithubStats compact only runs as a dry run", function()
      local retention = require("github_stats.retention")
      local real_run = retention.run_all
      local runs = {}
      retention.run_all = function(opts)
        runs[#runs + 1] = opts.dry_run
        return { archived = 0, compacted_deleted = 0, pruned_deleted = 0, freed_bytes = 0, errors = {} }
      end
      package.loaded["github_stats.bindings.usrcmds.compact"] = nil
      local compact = require("github_stats.bindings.usrcmds.compact")
      compact.execute({ args = "" })
      compact.execute({ args = "dry-run" })
      retention.run_all = real_run
      assert.same({ true }, runs)
    end)

    it("refuses without a data repository", function()
      remote.set_current(remote.resolve({ storage = "local" }, {}))
      local result
      remote.sync(function(ok, err)
        result = { ok = ok, err = err }
      end, true)
      assert.is_false(result.ok)
      assert.matches("setup", result.err)
    end)
  end)

  describe("fetcher in remote mode", function()
    it("pulls instead of fetching: no request, an empty summary", function()
      vim.fn.mkdir(tmp .. "/vault/.git", "p")
      remote.set_current(remote.resolve({ storage = { repo = "me/data" } }, {}))
      local real_api = package.loaded["github_stats.api"]
      local requests = 0
      package.loaded["github_stats.api"] = {
        fetch_metric_async = function()
          requests = requests + 1
        end,
      }
      package.loaded["github_stats.fetcher"] = nil
      local fetcher = require("github_stats.fetcher")
      local summary, repo_result
      fetcher.fetch_all(true, function(s)
        summary = s
      end)
      fetcher.fetch_repo("me/x", function(success, errors)
        repo_result = { success, errors }
      end)
      package.loaded["github_stats.api"] = real_api
      package.loaded["github_stats.fetcher"] = nil
      assert.equals(0, requests)
      assert.same({}, summary.success)
      assert.same({ {}, {} }, repo_result)
      assert.is_not_nil(call_of("git -C " .. tmp .. "/vault pull --ff-only"))
    end)
  end)

  describe("create.scaffold", function()
    it("writes the workflow with every placeholder filled, and takes a history over without its .git", function()
      local seed = tmp .. "/seed"
      vim.fn.mkdir(seed .. "/data/me_x/clones", "p")
      vim.fn.mkdir(seed .. "/.git", "p")
      vim.fn.writefile({ "{}" }, seed .. "/data/me_x/clones/2026-11-01T00-00-00.json")
      vim.fn.writefile({ '{"repos":["me/x"]}' }, seed .. "/config.json")
      vim.fn.writefile({ "x" }, seed .. "/.git/HEAD")
      vim.fn.writefile({ "# mine" }, seed .. "/README.md")

      local dir = tmp .. "/new"
      local ok, err, copied = require("github_stats.remote.create").scaffold(dir, { repo = "me/data", seed_dir = seed })
      assert.is_true(ok, err)
      assert.equals(3, copied)
      assert.equals(0, vim.fn.isdirectory(dir .. "/.git"))
      assert.equals(1, vim.fn.filereadable(dir .. "/data/me_x/clones/2026-11-01T00-00-00.json"))
      assert.same({ '{"repos":["me/x"]}' }, vim.fn.readfile(dir .. "/config.json"))
      assert.same({ "# mine" }, vim.fn.readfile(dir .. "/README.md"))

      local workflow = table.concat(vim.fn.readfile(dir .. "/.github/workflows/collect.yml"), "\n")
      -- Our placeholders are {{UPPER_CASE}}; GitHub's own expressions (${{ secrets.X }}) stay.
      assert.is_nil(workflow:find("{{[%u_]+}}"))
      assert.matches("%${{ secrets%.GH_STATS_TOKEN }}", workflow)
      assert.matches("github_stats%.nvim%.git", workflow)
      assert.matches("%-%-token%-env=GH_STATS_TOKEN", workflow)
      assert.matches("secrets%.GH_STATS_TOKEN", workflow)
    end)

    it("writes a default config.json and the README with the repository's name when there is no history", function()
      local dir = tmp .. "/empty"
      local ok = require("github_stats.remote.create").scaffold(dir, { repo = "me/data" })
      assert.is_true(ok)
      assert.equals("table", type(vim.json.decode(table.concat(vim.fn.readfile(dir .. "/config.json"), "\n")).repos))
      assert.matches("me/data", table.concat(vim.fn.readfile(dir .. "/README.md"), "\n"))
    end)

    it("refuses a name that is not owner/name", function()
      local ok, err = require("github_stats.remote.create").scaffold(tmp .. "/x", { repo = "data" })
      assert.is_false(ok)
      assert.matches("not a repository name", err)
    end)
  end)

  describe("create.create", function()
    it("commits and creates the private repository with gh, pushing the first commit", function()
      local dir = tmp .. "/made"
      local ok, err = require("github_stats.remote.create").create({ repo = "me/data", dir = dir })
      assert.is_true(ok, err)
      local gh = assert(call_of("gh repo create me/data"))
      assert.truthy(vim.tbl_contains(gh.cmd, "--private"))
      assert.truthy(vim.tbl_contains(gh.cmd, "--push"))
      assert.is_not_nil(call_of("git -C " .. dir .. " commit"))
    end)

    it("refuses a folder that already has files", function()
      vim.fn.mkdir(tmp .. "/full", "p")
      vim.fn.writefile({ "x" }, tmp .. "/full/x")
      local ok, err = require("github_stats.remote.create").create({ repo = "me/data", dir = tmp .. "/full" })
      assert.is_false(ok)
      assert.matches("not empty", err)
      assert.is_nil(call_of("gh repo create"))
    end)
  end)

  describe("wizard", function()
    local wizard, notes, questions, picks, real_reload, reloads, real_token, real_executable

    before_each(function()
      wizard = require("github_stats.remote.wizard")
      notes, questions, picks, reloads = {}, {}, {}, 0
      wizard.ui = {
        select = function(opts)
          questions[#questions + 1] = opts.title
          local idx = table.remove(picks, 1)
          return idx and opts.selection[idx] or nil, idx
        end,
        input = function(opts)
          questions[#questions + 1] = opts.prompt
          return opts.default, false
        end,
        confirm = function(opts)
          questions[#questions + 1] = opts.question
          local a = table.remove(picks, 1)
          return a
        end,
        note = function(opts)
          notes[#notes + 1] = table.concat(opts.message, "\n")
        end,
      }
      local gs = require("github_stats")
      real_reload = gs.reload_storage
      gs.reload_storage = function()
        reloads = reloads + 1
      end
      local config = require("github_stats.config")
      real_token = config.get_token
      config.get_token = function()
        return "tok-123", nil
      end
      real_executable = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "gh" then
          return 1
        end
        return real_executable(name)
      end
      answer("gh api user", { stdout = "me\n" })
      remote.set_current(remote.resolve({}, {}))
    end)

    after_each(function()
      require("github_stats").reload_storage = real_reload
      require("github_stats.config").get_token = real_token
      vim.fn.executable = real_executable
    end)

    it("remembers 'later' and does not open by itself again", function()
      picks = { 3 }
      wizard.open({ auto = true })
      assert.is_true(remote.read_state().deferred)
      assert.is_false(wizard.should_auto_open(remote.resolve({}, nil)))
    end)

    it("switches this machine to local mode", function()
      picks = { 2 }
      wizard.open()
      assert.equals("local", remote.read_state().mode)
      assert.equals(1, reloads)
      assert.is_nil(call_of("gh"))
    end)

    it("clones an existing data repository, sets the secret through stdin, starts the workflow", function()
      answer("gh repo view me/" .. remote.DEFAULT_REPO_NAME, { ok = true })
      answer("gh secret list", { stdout = "[]" })
      answer("gh repo clone", function(cmd)
        vim.fn.mkdir(cmd[5] .. "/.git", "p")
        return {}
      end)
      picks = { 1, true, "Use my token", true }
      wizard.open()

      local state = remote.read_state()
      assert.equals("remote", state.mode)
      assert.equals("me/" .. remote.DEFAULT_REPO_NAME, state.repo)
      assert.equals(1, reloads)

      local secret = assert(call_of("gh secret set " .. remote.SECRET_NAME))
      assert.equals("tok-123", secret.opts.input)
      assert.is_nil(line(secret.cmd):find("tok-123", 1, true))
      assert.is_not_nil(call_of("gh workflow run " .. remote.WORKFLOW_FILE))
      assert.matches("Remote mode is set up", notes[#notes])
    end)

    it("explains how to log in when gh cannot", function()
      answer("gh api user", { ok = false, code = 1, stderr = "not logged in" })
      picks = { 1 }
      wizard.open()
      assert.matches("gh auth login", notes[#notes])
      assert.is_nil(remote.read_state().mode)
    end)

    it("shows how to set the secret when the user does it", function()
      answer("gh repo view", { ok = true })
      answer("gh secret list", { stdout = "[]" })
      answer("gh repo clone", function(cmd)
        vim.fn.mkdir(cmd[5] .. "/.git", "p")
        return {}
      end)
      picks = { 1, true, "I set it myself" }
      wizard.open()
      assert.is_nil(call_of("gh secret set"))
      assert.is_nil(call_of("gh workflow run"))
      assert.matches("gh secret set GH_STATS_TOKEN", notes[#notes])
    end)

    it("opens by itself only in remote mode with nothing decided, and with a UI", function()
      local s = remote.resolve({}, {})
      -- headless: no UI
      assert.is_false(wizard.should_auto_open(s))
      local real_uis = vim.api.nvim_list_uis
      vim.api.nvim_list_uis = function()
        return { {} }
      end
      local unset = wizard.should_auto_open(s)
      local explicit = wizard.should_auto_open(remote.resolve({ storage = "remote" }, {}))
      local deferred = wizard.should_auto_open(remote.resolve({}, { deferred = true }))
      vim.api.nvim_list_uis = real_uis
      assert.is_true(unset)
      assert.is_false(explicit)
      assert.is_false(deferred)
    end)
  end)
end)

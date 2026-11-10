---@diagnostic disable: undefined-global

-- Specs for github_stats.cli -- the commands of scripts/github_stats.lua.
--
-- `github_stats.api` is replaced in package.loaded, so no request leaves the machine. Every run uses its own
-- --config-dir and --digest-dir below a temp folder: the history, config.json, the digests -- and root.json stays
-- untouched, which is one of the things checked here.

describe("cli", function()
  local cli, tmp, real_api, real_stdout, real_stderr, out, err, responder
  local saved_token

  ---@param argv string[]
  ---@return integer code
  local function run(argv)
    out, err = {}, {}
    io.stdout = {
      write = function(_, ...)
        for _, v in ipairs({ ... }) do
          out[#out + 1] = tostring(v)
        end
      end,
    }
    io.stderr = {
      write = function(_, ...)
        for _, v in ipairs({ ... }) do
          err[#err + 1] = tostring(v)
        end
      end,
    }
    local ok, code = pcall(cli.run, argv)
    io.stdout, io.stderr = real_stdout, real_stderr
    assert(ok, tostring(code))
    return code
  end

  ---@return string
  local function stdout()
    return table.concat(out)
  end

  ---@return string
  local function stderr()
    return table.concat(err)
  end

  ---@param extra string[]
  ---@return string[]
  local function args(extra)
    local a = { "--config-dir=" .. tmp .. "/cfg", "--digest-dir=" .. tmp .. "/dig" }
    vim.list_extend(a, extra)
    return a
  end

  before_each(function()
    real_stdout, real_stderr = io.stdout, io.stderr
    saved_token = vim.env.GITHUB_TOKEN
    vim.env.GITHUB_TOKEN = "spec-token"
    responder = function()
      return { count = 3, uniques = 2, clones = {}, views = {} }, nil
    end
    real_api = package.loaded["github_stats.api"]
    package.loaded["github_stats.api"] = {
      fetch_metric_async = function(repo, metric, callback)
        vim.schedule(function()
          callback(responder(repo, metric))
        end)
      end,
    }
    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.retention",
      "github_stats.digest",
      "github_stats.fetcher",
      "github_stats.cli",
    }) do
      package.loaded[name] = nil
    end
    tmp = vim.fn.tempname()
    cli = require("github_stats.cli")
  end)

  after_each(function()
    io.stdout, io.stderr = real_stdout, real_stderr
    vim.env.GITHUB_TOKEN = saved_token
    package.loaded["github_stats.api"] = real_api
    vim.fn.delete(tmp, "rf")
  end)

  describe("parse", function()
    it("reads the command, flags and values", function()
      local opts = assert(cli.parse({ "collect", "--force", "--repos=a/b, c/d", "--timeout=30", "--format=json" }))
      assert.equals("collect", opts.command)
      assert.is_true(opts.force)
      assert.same({ "a/b", "c/d" }, opts.repos)
      assert.equals(30, opts.timeout_s)
      assert.equals("json", opts.format)
    end)

    it("refuses what it does not know, by name", function()
      local _, e1 = cli.parse({ "collect", "--bogus" })
      assert.matches("unknown option %-%-bogus", e1)
      local _, e2 = cli.parse({ "report", "--repos=notarepo" })
      assert.matches("not owner/name", e2)
      local _, e3 = cli.parse({ "collect", "--timeout=0" })
      assert.matches("whole number", e3)
      local _, e4 = cli.parse({ "report", "--format=xml" })
      assert.matches("text or json", e4)
      local _, e5 = cli.parse({ "report", "extra" })
      assert.matches("unexpected argument extra", e5)
    end)
  end)

  describe("run", function()
    it("prints the usage: exit 0 for help, 2 without a command or for an unknown one", function()
      assert.equals(0, run({ "help" }))
      assert.matches("usage:", stdout())
      assert.equals(2, run({}))
      assert.matches("usage:", stderr())
      assert.equals(2, run({ "fetchall" }))
      assert.matches("unknown command fetchall", stderr())
    end)

    it("collect without a token is a configuration error (exit 2) and fetches nothing", function()
      vim.env.GITHUB_TOKEN = nil
      assert.equals(2, run(args({ "collect", "--repos=owner/alpha" })))
      assert.matches("no GitHub token", stderr())
      assert.equals(0, vim.fn.isdirectory(tmp .. "/cfg/data/owner_alpha"))
    end)

    it("collect fetches, writes the digests and leaves root.json alone (exit 0)", function()
      local root = require("github_stats.digest").root_path()
      local before = vim.fn.filereadable(root) == 1 and vim.fn.readfile(root) or nil

      assert.equals(0, run(args({ "collect", "--force", "--repos=owner/alpha,owner/beta", "--format=json" })))
      local result = vim.json.decode(stdout())
      assert.equals(8, result.fetched)
      assert.same({}, result.errors)
      assert.same({ "owner/alpha", "owner/beta" }, result.digest.written)
      assert.is_false(result.root_written)
      assert.equals(1, vim.fn.filereadable(tmp .. "/dig/digest/owner_alpha.json"))

      local after = vim.fn.filereadable(root) == 1 and vim.fn.readfile(root) or nil
      assert.same(before, after)
    end)

    it("collect reports a failed metric on stderr and exits 1, the rest is still stored", function()
      responder = function(repo)
        if repo == "owner/beta" then
          return nil, "boom"
        end
        return { count = 1, uniques = 1, clones = {}, views = {} }, nil
      end
      assert.equals(1, run(args({ "collect", "--force", "--repos=owner/alpha,owner/beta", "--quiet" })))
      assert.matches("fetched 4 metrics, 4 errors", stdout())
      assert.matches("owner/beta/clones: boom", stderr())
      assert.equals(1, vim.fn.filereadable(tmp .. "/dig/digest/owner_alpha.json"))
    end)

    it("collect inside the interval fetches nothing and says why (exit 0)", function()
      assert.equals(0, run(args({ "collect", "--force", "--repos=owner/alpha" })))
      assert.equals(0, run(args({ "collect", "--repos=owner/alpha" })))
      assert.matches("nothing fetched", stdout())
    end)

    it("report prints the history as the digest computes it, and names a repository without one", function()
      assert.equals(0, run(args({ "collect", "--force", "--repos=owner/alpha" })))
      assert.equals(0, run(args({ "report", "--repos=owner/alpha,owner/never", "--format=json" })))
      local result = vim.json.decode(stdout())
      assert.equals(1, #result.repos)
      assert.equals("owner/alpha", result.repos[1].repo)
      assert.same({ "owner/never" }, result.skipped)

      assert.equals(0, run(args({ "report", "--repos=owner/alpha,owner/never" })))
      assert.matches("owner/alpha", stdout())
      assert.matches("no history yet: owner/never", stdout())
    end)
  end)
end)

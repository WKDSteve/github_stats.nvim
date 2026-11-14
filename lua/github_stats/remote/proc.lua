---@module 'github_stats.remote.proc'
---@brief The one place the remote mode starts `git` and `gh`: awaitable inside the setup guide, callback-shaped elsewhere.
---@description
--- Every command goes through `M.exec`, which specs replace to answer without a process. Inside a coroutine that
--- `lib.nvim.ui.kit.async.run` started, `M.run` suspends it until the command is done (the editor keeps running);
--- anywhere else it blocks, which only the headless setup (`remote.create` from a script) does.

local M = {}

---@class GHStats.Remote.ProcResult
---@field ok boolean exit code 0 and not killed
---@field code integer
---@field stdout string
---@field stderr string

---@class GHStats.Remote.ProcOpts
---@field cwd? string
---@field input? string standard input (a secret goes here, never on the command line)
---@field env? table<string, string>
---@field timeout_ms? integer default 120000

---Start `cmd` and call `on_done` (scheduled) with its result. Replaced by specs.
---@param cmd string[]
---@param opts GHStats.Remote.ProcOpts|nil
---@param on_done fun(res: GHStats.Remote.ProcResult)
---@return nil
function M.exec(cmd, opts, on_done)
  opts = opts or {}
  require("lib.nvim.cross.run_argv").run_async_captured(
    cmd,
    -- Positional, not a result table; already scheduled. A process killed by a signal reads ok = true there,
    -- so the signal decides as well.
    function(ok, output, code, stderr, signal)
      on_done({
        ok = ok == true and (signal or 0) == 0,
        code = code or -1,
        stdout = output or "",
        stderr = stderr or "",
      })
    end,
    opts.input,
    {
      cwd = opts.cwd,
      -- Never wait for a password prompt nobody can answer.
      env = vim.tbl_extend("force", { GIT_TERMINAL_PROMPT = "0", GH_PROMPT_DISABLED = "1" }, opts.env or {}),
      timeout_ms = opts.timeout_ms or 120000,
    }
  )
end

---The coroutines `M.flow` started: only those may suspend (a test runner's own coroutine must block instead).
---@type table<thread, true>
local flows = setmetatable({}, { __mode = "k" })

---Run `fn` as a `kit.async` flow in which `M.run` suspends instead of blocking.
---@param fn fun()
---@return thread
function M.flow(fn)
  return require("lib.nvim.ui.kit.async").run(function()
    flows[coroutine.running()] = true
    fn()
  end)
end

---Whether the caller runs inside a flow `M.flow` started.
---@return boolean
local function in_kit_coroutine()
  local co, is_main = coroutine.running()
  return not is_main and flows[co] == true
end

---Run `cmd` to its end and return the result: suspends a `kit.async` coroutine, blocks anywhere else.
---@param cmd string[]
---@param opts GHStats.Remote.ProcOpts|nil
---@return GHStats.Remote.ProcResult
function M.run(cmd, opts)
  if in_kit_coroutine() then
    return require("lib.nvim.ui.kit.async").await(function(deliver)
      M.exec(cmd, opts, deliver)
    end)
  end
  ---@type GHStats.Remote.ProcResult|nil
  local result
  M.exec(cmd, opts, function(res)
    result = res
  end)
  local timeout = (opts and opts.timeout_ms or 120000) + 5000
  vim.wait(timeout, function()
    return result ~= nil
  end, 20)
  return result or { ok = false, code = 124, stdout = "", stderr = "timed out" }
end

---The first line of what a failed command said, for a message.
---@param res GHStats.Remote.ProcResult
---@return string
function M.reason(res)
  local text = vim.trim(res.stderr ~= "" and res.stderr or res.stdout)
  if text == "" then
    return ("exit code %d"):format(res.code)
  end
  return (text:gsub("\r?\n.*", ""))
end

return M

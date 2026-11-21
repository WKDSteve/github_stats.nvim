---@diagnostic disable: undefined-global

-- Specs for the wiring layer: the dashboard's buffer-local keymaps, the
-- plugin-lifecycle autocmd, `github_stats.setup()`, the right-click context
-- menu entries, and usrcmds.utils' float helper.
--
-- The keymaps are exercised the way a keypress reaches them -- by pulling each
-- buffer-local mapping's callback out of `nvim_buf_get_keymap` and calling it
-- -- rather than through `nvim_feedkeys`, which in a headless run would only
-- prove that the typeahead buffer accepted the characters.

describe("dashboard keymaps", function()
  local dashboard, dashboard_state, render, config
  local tmp_dir
  local notices, detail_calls, fetch_calls
  local saved = {}

  local REPOS = { "user/a", "user/b", "user/c", "user/d", "user/e" }

  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  ---The callback bound to `lhs` in the dashboard buffer, or nil.
  ---@param buf integer
  ---@param lhs string
  ---@return function?, table?
  local function mapping(buf, lhs)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == lhs then
        return m.callback, m
      end
    end
    return nil, nil
  end

  ---Open a dashboard over REPOS and return its buffer.
  ---@param dashboard_cfg? table
  ---@return integer buf
  local function open(dashboard_cfg)
    require("github_stats.config").init({
      config_dir = tmp_dir,
      repos = REPOS,
      dashboard = vim.tbl_extend("force", { refresh_interval_seconds = 0 }, dashboard_cfg or {}),
    })
    config = require("github_stats.config")
    notices = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    dashboard = require("github_stats.dashboard")
    dashboard_state = require("github_stats.dashboard.state")
    render = require("github_stats.dashboard.render")

    dashboard.open(false)
    return assert(require("github_stats.state.ui_state").get_buf(), "dashboard.open() must create a buffer")
  end

  before_each(function()
    saved = {}
    detail_calls, fetch_calls = {}, {}

    stub("github_stats.dashboard.detail", {
      show_detail = function(repo)
        detail_calls[#detail_calls + 1] = repo
      end,
    })
    stub("github_stats.fetcher", {
      fetch_repo = function(repo, cb)
        fetch_calls[#fetch_calls + 1] = { kind = "repo", repo = repo }
        cb({}, {})
      end,
      fetch_all = function(force, cb)
        fetch_calls[#fetch_calls + 1] = { kind = "all", force = force }
        if cb then
          cb({ success = {}, errors = {} })
        end
      end,
    })

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
      "github_stats.dashboard.actions",
      "github_stats.bindings.keymaps",
    }) do
      if saved[name] == nil then
        saved[name] = { package.loaded[name] }
      end
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
  end)

  after_each(function()
    pcall(function()
      require("github_stats.dashboard").close()
    end)
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  it("binds every configurable action to its default key", function()
    local buf = open()

    for _, key in ipairs({ "j", "k", "<CR>", "r", "R", "f", "s", "t", "T", "m", "?" }) do
      assert.is_function(mapping(buf, key), "no mapping for " .. key)
    end
  end)

  it("binds the fixed navigation keys too", function()
    local buf = open()

    for _, key in ipairs({ "<Down>", "<Up>", "<C-D>", "<C-U>", "<C-F>", "<C-B>", "gg", "G" }) do
      assert.is_function(mapping(buf, key), "no mapping for " .. key)
    end
  end)

  it("blocks horizontal and page cursor movement with <Nop>", function()
    local buf = open()

    for _, key in ipairs({ "h", "l", "<Left>", "<Right>", "<PageUp>", "<PageDown>", "<Home>", "<End>" }) do
      local _, m = mapping(buf, key)
      assert.is_not_nil(m, "no mapping for " .. key)
      -- `<Nop>` is reported back as an empty rhs with no Lua callback -- i.e.
      -- the key is bound and does nothing, which is the point.
      assert.equals("", m.rhs, key .. " is not a no-op")
      assert.is_nil(m.callback)
    end
  end)

  it("uses the configured key instead of the default", function()
    local buf = open({ keybindings = { navigate_down = "n" } })

    assert.is_function(mapping(buf, "n"))
    assert.is_nil(mapping(buf, "j"))
  end)

  it("leaves a key disabled with an empty string unbound", function()
    local buf = open({ keybindings = { show_help = "", cycle_sort = "" } })

    assert.is_nil(mapping(buf, "?"))
    assert.is_nil(mapping(buf, "s"))
    -- The rest still work.
    assert.is_function(mapping(buf, "t"))
  end)

  it("labels each binding for which-key", function()
    local buf = open()
    local _, m = mapping(buf, "j")

    assert.equals("GitHub Stats: navigate down", m.desc)
  end)

  it("moves the selection down and up", function()
    local buf = open()

    mapping(buf, "j")()
    assert.equals(2, dashboard_state.get_state().current_index)

    mapping(buf, "k")()
    assert.equals(1, dashboard_state.get_state().current_index)
  end)

  it("jumps to the last and first entry with G and gg", function()
    local buf = open()

    mapping(buf, "G")()
    assert.equals(#REPOS, dashboard_state.get_state().current_index)

    mapping(buf, "gg")()
    assert.equals(1, dashboard_state.get_state().current_index)
    assert.equals(0, dashboard_state.get_state().scroll_offset)
  end)

  it("scrolls by half and whole pages", function()
    local buf = open()
    local state = dashboard_state.get_state()

    -- Enough content to have somewhere to scroll to.
    dashboard_state.update_window_height(8)
    dashboard_state.set_scroll_offset(10)

    mapping(buf, "<C-D>")()
    assert.equals(20, state.scroll_offset)

    mapping(buf, "<C-U>")()
    assert.equals(10, state.scroll_offset)

    mapping(buf, "<C-F>")()
    assert.equals(10 + (state.win_height - render.HEADER_LINES), state.scroll_offset)
  end)

  it("opens the detail view for the selected repository", function()
    local buf = open()

    mapping(buf, "j")()
    mapping(buf, "<CR>")()

    assert.same({ "user/b" }, detail_calls)
  end)

  it("re-reads from disk on the refresh key", function()
    local buf = open()
    local storage = require("github_stats.storage")
    local invalidated = false
    local real_invalidate = storage.invalidate
    ---@diagnostic disable-next-line: duplicate-set-field
    storage.invalidate = function(...)
      invalidated = true
      return real_invalidate(...)
    end

    mapping(buf, "r")()

    storage.invalidate = real_invalidate
    assert.is_true(invalidated)
  end)

  it("force-refreshes all repositories and the selected one", function()
    local buf = open()

    mapping(buf, "R")()
    vim.wait(200)
    mapping(buf, "f")()
    vim.wait(200)

    assert.equals("all", fetch_calls[1].kind)
    assert.is_true(fetch_calls[1].force)
    assert.equals("repo", fetch_calls[2].kind)
    assert.equals("user/a", fetch_calls[2].repo)
  end)

  it("cycles sort and time range", function()
    local buf = open()

    mapping(buf, "s")()
    assert.equals("views", dashboard_state.get_state().sort_by)

    mapping(buf, "t")()
    assert.equals("90d", dashboard_state.get_state().time_range)
  end)

  it("switches to the maximum range", function()
    local buf = open()

    mapping(buf, "m")()

    assert.equals("max", dashboard_state.get_state().time_range)
  end)

  it("prints the help with the configured keys in it", function()
    local buf = open({ keybindings = { show_details = "<Space>" } })

    mapping(buf, "?")()

    assert.equals(1, #notices)
    assert.is_truthy(notices[1].message:find("GitHub Stats Dashboard Keybindings", 1, true))
    assert.is_truthy(notices[1].message:find("<Space>", 1, true))
  end)

  it("binds Esc as a fixed quit key alongside the configured one", function()
    local buf = open()

    assert.is_not_nil((mapping(buf, "<Esc>")))
    assert.is_not_nil((mapping(buf, "q")))
  end)

  it("does nothing when asked to bind with no dashboard state", function()
    local buf = open()
    dashboard.close()

    local scratch = vim.api.nvim_create_buf(false, true)
    require("github_stats.bindings.keymaps").setup_keymaps(scratch)

    assert.equals(0, #vim.api.nvim_buf_get_keymap(scratch, "n"))
    vim.api.nvim_buf_delete(scratch, { force = true })
    assert.is_not_nil(buf)
  end)
end)

describe("plugin autocmds", function()
  local autocmds, config
  local tmp_dir
  local background_started, dashboard_opens
  local ui_attached
  local saved = {}
  local real_defer_fn

  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  ---Fire the registered VimEnter callback with vim.defer_fn made synchronous.
  local function fire_vim_enter()
    local list = vim.api.nvim_get_autocmds({ group = "GithubStatsAutoFetch", event = "VimEnter" })
    assert.equals(1, #list)

    real_defer_fn = vim.defer_fn
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.defer_fn = function(fn)
      fn()
    end
    local ok, err = pcall(list[1].callback, {})
    vim.defer_fn = real_defer_fn
    assert.is_true(ok, tostring(err))
  end

  before_each(function()
    saved = {}
    background_started, dashboard_opens = 0, {}
    ui_attached = true
    vim.g.github_stats_no_clone_on_start = nil

    stub("github_stats.background", {
      has_ui = function()
        return ui_attached
      end,
      start = function()
        background_started = background_started + 1
      end,
      stop = function() end,
    })
    stub("github_stats.dashboard", {
      open = function(force)
        dashboard_opens[#dashboard_opens + 1] = force
      end,
      close = function() end,
    })

    for _, name in ipairs({ "github_stats.config", "github_stats.bindings.autocmds" }) do
      if saved[name] == nil then
        saved[name] = { package.loaded[name] }
      end
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = { "user/a" } })

    autocmds = require("github_stats.bindings.autocmds")
  end)

  after_each(function()
    vim.g.github_stats_no_clone_on_start = nil
    pcall(vim.api.nvim_del_augroup_by_name, "GithubStatsAutoFetch")
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  it("registers exactly one VimEnter handler in its own group", function()
    autocmds.setup()

    local list = vim.api.nvim_get_autocmds({ group = "GithubStatsAutoFetch", event = "VimEnter" })
    assert.equals(1, #list)
  end)

  it("replaces its handler rather than stacking a second one", function()
    autocmds.setup()
    autocmds.setup()

    local list = vim.api.nvim_get_autocmds({ group = "GithubStatsAutoFetch", event = "VimEnter" })
    assert.equals(1, #list)
  end)

  it("starts the background cycle and leaves the dashboard closed by default", function()
    autocmds.setup()

    fire_vim_enter()

    assert.equals(1, background_started)
    assert.equals(0, #dashboard_opens)
  end)

  it("auto-opens the dashboard when configured to", function()
    config.init({
      config_dir = tmp_dir,
      repos = { "user/a" },
      dashboard = { enabled = true, auto_open = true },
    })
    autocmds.setup()

    fire_vim_enter()

    assert.same({ false }, dashboard_opens)
  end)

  it("does not auto-open a disabled dashboard", function()
    config.init({
      config_dir = tmp_dir,
      repos = { "user/a" },
      dashboard = { enabled = false, auto_open = true },
    })
    autocmds.setup()

    fire_vim_enter()

    assert.equals(0, #dashboard_opens)
  end)
  describe("a remote data repository that is not cloned yet", function()
    local clones

    before_each(function()
      clones = 0
      local storage = { repo = "owner/vault" }
      stub("github_stats.remote", {
        current = function()
          return storage
        end,
        status = function()
          return "clone"
        end,
        clone = function()
          clones = clones + 1
        end,
      })
      stub("github_stats.remote.wizard", {
        should_auto_open = function()
          return false
        end,
      })
    end)

    it("is cloned once a UI is attached", function()
      autocmds.setup()
      fire_vim_enter()
      assert.equals(1, clones)
    end)

    it("is not cloned without a UI", function()
      ui_attached = false
      autocmds.setup()
      fire_vim_enter()
      assert.equals(0, clones)
    end)

    it("is not cloned when the session opts out", function()
      vim.g.github_stats_no_clone_on_start = true
      autocmds.setup()
      fire_vim_enter()
      assert.equals(0, clones)
    end)
  end)
end)

describe("github_stats.setup", function()
  local saved = {}
  local calls

  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  before_each(function()
    saved = {}
    calls = { init = {}, notify = {}, usrcmds = 0, autocmds = 0 }

    stub("github_stats.config", {
      init = function(opts)
        calls.init[#calls.init + 1] = opts
        return calls.init_result, calls.init_error
      end,
      notify = function(message, level)
        calls.notify[#calls.notify + 1] = { message = message, level = level }
      end,
    })
    stub("github_stats.bindings.usrcmds", {
      setup = function()
        calls.usrcmds = calls.usrcmds + 1
      end,
    })
    stub("github_stats.bindings.autocmds", {
      setup = function()
        calls.autocmds = calls.autocmds + 1
      end,
    })

    calls.init_result, calls.init_error = true, nil
    if saved["github_stats"] == nil then
      saved["github_stats"] = { package.loaded["github_stats"] }
    end
    package.loaded["github_stats"] = nil
  end)

  after_each(function()
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
  end)

  it("initializes the config, then the commands and autocmds", function()
    require("github_stats").setup({ repos = { "user/a" } })

    assert.same({ { repos = { "user/a" } } }, calls.init)
    assert.equals(1, calls.usrcmds)
    assert.equals(1, calls.autocmds)
  end)

  it("tolerates being called with no options at all", function()
    require("github_stats").setup()

    assert.same({ {} }, calls.init)
    assert.equals(1, calls.usrcmds)
  end)

  it("reports a configuration error and registers nothing", function()
    calls.init_result, calls.init_error = false, "config.json is not JSON"

    require("github_stats").setup({})

    assert.equals(0, calls.usrcmds)
    assert.equals(0, calls.autocmds)
    assert.equals(1, #calls.notify)
    assert.equals("error", calls.notify[1].level)
    assert.is_truthy(calls.notify[1].message:find("config.json is not JSON", 1, true))
  end)

  it("re-exports the submodules a user config might reach for", function()
    local gh = require("github_stats")

    for _, field in ipairs({ "config", "api", "storage", "fetcher", "analytics", "dashboard" }) do
      assert.is_table(gh[field], "missing submodule: " .. field)
    end
  end)
end)

describe("context menu integration", function()
  local menu, dashboard_state, config
  local tmp_dir
  local saved = {}
  local calls
  local real_input

  local REPOS = { "user/a", "user/b" }

  local function stub(name, value)
    if saved[name] == nil then
      saved[name] = { package.loaded[name] }
    end
    package.loaded[name] = value
  end

  ---Find an item by the text in its label.
  ---@param items table[]
  ---@param needle string
  ---@return table?
  local function item(items, needle)
    for _, entry in ipairs(items) do
      if type(entry.name) == "string" and entry.name:find(needle, 1, true) then
        return entry
      end
    end
    return nil
  end

  before_each(function()
    saved = {}
    calls = { detail = {}, render = {}, fetch = {}, export = {}, notify = {} }

    stub("github_stats.dashboard.detail", {
      show_detail = function(repo)
        calls.detail[#calls.detail + 1] = repo
      end,
    })
    stub("github_stats.dashboard", {
      schedule_render = function(force)
        calls.render[#calls.render + 1] = force
      end,
    })
    stub("github_stats.fetcher", {
      fetch_repo = function(repo, cb)
        calls.fetch[#calls.fetch + 1] = { kind = "repo", repo = repo }
        cb({}, {})
      end,
      fetch_all = function(force, cb)
        calls.fetch[#calls.fetch + 1] = { kind = "all", force = force }
        if cb then
          cb({ success = {}, errors = {} })
        end
      end,
    })
    stub("github_stats.bindings.usrcmds.export", {
      execute = function(args)
        calls.export[#calls.export + 1] = args.args
      end,
    })

    for _, name in ipairs({
      "github_stats.config",
      "github_stats.storage",
      "github_stats.analytics",
      "github_stats.dashboard.state",
      "github_stats.dashboard.render",
      "github_stats.dashboard.actions",
      "github_stats.integrations.menu",
    }) do
      if saved[name] == nil then
        saved[name] = { package.loaded[name] }
      end
      package.loaded[name] = nil
    end

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    config = require("github_stats.config")
    config.init({ config_dir = tmp_dir, repos = REPOS })
    ---@diagnostic disable-next-line: duplicate-set-field
    config.notify = function(message, level)
      calls.notify[#calls.notify + 1] = { message = message, level = level }
    end

    dashboard_state = require("github_stats.dashboard.state")
    menu = require("github_stats.integrations.menu")
  end)

  after_each(function()
    dashboard_state.clear_state()
    for name, boxed in pairs(saved) do
      package.loaded[name] = boxed[1]
    end
    saved = {}
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
      tmp_dir = nil
    end
  end)

  it("offers nothing when the integration is switched off", function()
    config.init({ config_dir = tmp_dir, repos = REPOS, dashboard = { menu = { enable = false } } })
    dashboard_state.init_state(REPOS)

    assert.same({}, menu.items())
    assert.is_nil(menu.submenu())
  end)

  it("is on by default, and by default without an explicit menu section", function()
    dashboard_state.init_state(REPOS)

    assert.is_true(#menu.items() > 0)
  end)

  it("offers the selection-independent entries even with no dashboard open", function()
    local items = menu.items()

    assert.is_nil(item(items, "Show details"))
    assert.is_nil(item(items, "Force-refresh selected"))
    assert.is_nil(item(items, "Export selected"))
    assert.is_not_nil(item(items, "Cycle sort"))
    assert.is_not_nil(item(items, "Refresh dashboard"))
    assert.is_not_nil(item(items, "Force-refresh all"))
  end)

  it("adds the selection-dependent entries once a repository is selected", function()
    dashboard_state.init_state(REPOS)
    local items = menu.items()

    assert.is_not_nil(item(items, "Show details"))
    assert.is_not_nil(item(items, "Force-refresh selected"))
    assert.is_not_nil(item(items, "Export selected"))
  end)

  it("mirrors the dashboard's own keys as right-hand hints", function()
    dashboard_state.init_state(REPOS)
    local items = menu.items()

    assert.equals("<CR>", item(items, "Show details").rtxt)
    assert.equals("s", item(items, "Cycle sort").rtxt)
    assert.equals("t", item(items, "Cycle time range").rtxt)
    assert.equals("m", item(items, "Maximum time range").rtxt)
    assert.equals("r", item(items, "Refresh dashboard").rtxt)
    assert.equals("R", item(items, "Force-refresh all").rtxt)
    assert.equals("f", item(items, "Force-refresh selected").rtxt)
  end)

  it("opens the detail view for whatever is selected when picked", function()
    dashboard_state.init_state(REPOS)
    dashboard_state.set_current_index(2)

    item(menu.items(), "Show details").cmd()

    assert.same({ "user/b" }, calls.detail)
  end)

  it("cycles sort and re-renders", function()
    dashboard_state.init_state(REPOS)

    item(menu.items(), "Cycle sort").cmd()

    assert.equals("views", dashboard_state.get_state().sort_by)
    assert.same({ false }, calls.render)
  end)

  it("cycles the time range and jumps to max", function()
    dashboard_state.init_state(REPOS)

    item(menu.items(), "Cycle time range").cmd()
    assert.equals("90d", dashboard_state.get_state().time_range)

    item(menu.items(), "Maximum time range").cmd()
    assert.equals("max", dashboard_state.get_state().time_range)
  end)

  it("forces a re-render on the refresh entry", function()
    dashboard_state.init_state(REPOS)

    item(menu.items(), "Refresh dashboard").cmd()

    assert.same({ true }, calls.render)
  end)

  it("announces and runs a force-refresh of everything", function()
    dashboard_state.init_state(REPOS)

    item(menu.items(), "Force-refresh all").cmd()
    vim.wait(200)

    assert.equals("all", calls.fetch[1].kind)
    assert.is_true(calls.fetch[1].force)
    assert.is_truthy(calls.notify[1].message:find("Refreshing all repositories", 1, true))
    assert.same({ true }, calls.render)
  end)

  it("announces and runs a force-refresh of the selection", function()
    dashboard_state.init_state(REPOS)

    item(menu.items(), "Force-refresh selected").cmd()
    vim.wait(200)

    assert.equals("repo", calls.fetch[1].kind)
    assert.equals("user/a", calls.fetch[1].repo)
    assert.is_truthy(calls.notify[1].message:find("Force-refreshing selected", 1, true))
  end)

  it("exports the selection through the export subcommand", function()
    dashboard_state.init_state(REPOS)
    real_input = vim.fn.input
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.input = function()
      return "out.md"
    end

    item(menu.items(), "Export selected").cmd()

    vim.fn.input = real_input
    assert.same({ "user/a both out.md" }, calls.export)
  end)

  it("cancels the export on an empty path", function()
    dashboard_state.init_state(REPOS)
    real_input = vim.fn.input
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.input = function()
      return ""
    end

    item(menu.items(), "Export selected").cmd()

    vim.fn.input = real_input
    assert.equals(0, #calls.export)
  end)

  it("wraps the entries as one fly-out submenu", function()
    dashboard_state.init_state(REPOS)

    local sub = menu.submenu()
    assert.is_truthy(sub.name:find("GitHub Stats", 1, true))
    assert.is_true(#sub.items > 0)

    assert.equals("Custom", menu.submenu("Custom").name)
  end)
end)

describe("usrcmds.utils", function()
  local utils

  before_each(function()
    utils = require("github_stats.bindings.usrcmds.utils")
  end)

  describe("split_lines", function()
    it("splits on newlines and keeps empty lines", function()
      assert.same({ "a", "b", "" }, utils.split_lines("a\nb\n"))
      assert.same({ "a", "", "b", "" }, utils.split_lines("a\n\nb\n"))
    end)

    -- Regression: the old `([^\n]*)\n?` pattern matched once more at the end
    -- of the subject and appended a trailing empty line to every result, even
    -- for a string with no newline at all -- which show_float() then multiplied
    -- across every element of a line array (see its spec below).
    it("returns a single entry for a string without newlines", function()
      assert.same({ "one" }, utils.split_lines("one"))
      assert.same({ "" }, utils.split_lines(""))
    end)
  end)

  describe("format_number", function()
    it("groups thousands", function()
      assert.equals("1,234,567", utils.format_number(1234567))
      assert.equals("42", utils.format_number(42))
    end)
  end)

  describe("show_float", function()
    it("shows a string, splitting it into lines", function()
      local buf, win = utils.show_float("first\nsecond", "Title")

      assert.is_not_nil(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals("first", lines[1])
      assert.equals("second", lines[2])

      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)

    -- Regression: each element used to pick up split_lines()' spurious
    -- trailing empty line, so every multi-line report came out double-spaced.
    it("flattens embedded newlines inside a line array without double-spacing", function()
      local buf, win = utils.show_float({ "a", "b\nc" }, "Title")

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.same({ "a", "b", "c" }, lines)

      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)

    it("focuses the window it opened", function()
      local _, win = utils.show_float({ "content" }, "Title")

      assert.equals(win, vim.api.nvim_get_current_win())

      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end)
end)

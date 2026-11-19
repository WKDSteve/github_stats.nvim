---@module 'github_stats.bindings.keymaps'
---@brief Dashboard keybindings
---@description
--- Defines all keybindings for dashboard navigation and interaction.
--- Configurable bindings are read from `dashboard.keybindings` (falling back
--- to config/DEFAULTS.lua), so users can remap or disable them (set a key to
--- "" to disable it) via setup(). Fixed bindings (arrow keys, Ctrl-d/u/f/b,
--- gg/G, Esc) are not part of the configurable set and always apply.
--- CRITICAL: Blocks native cursor movement to prevent race conditions.
---
--- No which-key registration: which-key reads buffer-local keymaps itself and
--- labels each from its own `desc`, which every binding here sets. This file
--- used to send those same strings a second time, which only gave one label
--- two places to drift apart in.

local config = require("github_stats.config")
local map = require("lib.nvim.bindings.keymap")
local window = require("lib.nvim.window")
local DEFAULT_KEYBINDINGS = require("github_stats.config.DEFAULTS").dashboard.keybindings
local dashboard_state = require("github_stats.dashboard.state")
local movement = require("github_stats.dashboard.movement")
local render = require("github_stats.dashboard.render")
local ui_state = require("github_stats.state.ui_state")
local detail = require("github_stats.dashboard.detail")
local actions = require("github_stats.dashboard.actions")

local M = {}

---@internal
---Resolve effective dashboard keybindings (user config merged over defaults)
---@return table<string, string>
local function get_keybindings()
  local cfg = config.get()
  local user_keybindings = (cfg and cfg.dashboard and cfg.dashboard.keybindings) or {}
  return vim.tbl_extend("force", DEFAULT_KEYBINDINGS, user_keybindings)
end

---@internal
---Map a key to an action with debounced render, unless the key is disabled ("")
---@param buf integer Buffer handle
---@param key string Key sequence, empty string disables the binding
---@param action function Action to perform
---@param desc? string Human-readable description, shown by which-key
---@return nil
local function map_key(buf, key, action, desc)
  if not key or key == "" then
    return
  end

  map("n", key, function()
    action()
    -- Trigger debounced render
    require("github_stats.dashboard").schedule_render(false)
  end, { buffer = buf }, desc)
end

---@internal
---Block native cursor movement to prevent conflicts
---@param buf integer Buffer handle
---@return nil
local function block_cursor_movement(buf)
  -- Block all native cursor movements that might interfere
  local blocked_keys = {
    "<Up>",
    "<Down>",
    "<Left>",
    "<Right>",
    "<PageUp>",
    "<PageDown>",
    "<Home>",
    "<End>",
    "h",
    "l", -- Horizontal movement not needed in dashboard
  }

  for _, key in ipairs(blocked_keys) do
    -- j, k, and arrows are handled explicitly below
    if key ~= "j" and key ~= "k" and key ~= "<Up>" and key ~= "<Down>" then
      map("n", key, "<Nop>", { buffer = buf })
    end
  end
end

---@internal
---Jump the current selection to a specific repository index, scrolling just
---enough to keep it visible (mirrors the auto-scroll idiom used by
---move_cursor_down/move_cursor_up). Clamped, so an out-of-range count is
---never an error.
---@param state GHStats.DashboardState
---@param target_index integer Requested repository index (1-based, unclamped)
---@return nil
local function jump_to_repo(state, target_index)
  local target = math.max(1, math.min(target_index, #state.repos))
  dashboard_state.set_current_index(target)

  local target_line = dashboard_state.get_repo_line(target)
  local visible_start = state.scroll_offset + 1
  local visible_end = state.scroll_offset + state.win_height

  if target_line < visible_start then
    dashboard_state.set_scroll_offset(math.max(0, target_line - 1))
  elseif target_line > visible_end then
    dashboard_state.set_scroll_offset(math.min(state.max_scroll, target_line - state.win_height))
  end
end

---Setup all dashboard keymaps
---@param buf integer Buffer handle
---@return nil
function M.setup_keymaps(buf)
  local state = dashboard_state.get_state()
  if not state then
    return
  end

  local keybindings = get_keybindings()

  -- Block conflicting cursor movements first
  block_cursor_movement(buf)

  -- Navigation: configurable keys AND arrow keys (fixed, with auto-scroll)
  -- count1: e.g. 5j moves down 5 repositories instead of 1
  map_key(buf, keybindings.navigate_down, function()
    movement.move_cursor_down(state, vim.v.count1)
  end, "GitHub Stats: navigate down")

  map_key(buf, "<Down>", function()
    movement.move_cursor_down(state, vim.v.count1)
  end)

  map_key(buf, keybindings.navigate_up, function()
    movement.move_cursor_up(state, vim.v.count1)
  end, "GitHub Stats: navigate up")

  map_key(buf, "<Up>", function()
    movement.move_cursor_up(state, vim.v.count1)
  end)

  -- Scroll: Ctrl-d/u (fixed)
  -- Raw count: 0 (no prefix) keeps the fixed default of 10 lines; an
  -- explicit prefix (e.g. 1<C-d>) scrolls by exactly that many lines.
  map_key(buf, "<C-d>", function()
    local lines = vim.v.count > 0 and vim.v.count or 10
    dashboard_state.scroll_by(lines)
  end, "GitHub Stats: scroll half page down")

  map_key(buf, "<C-u>", function()
    local lines = vim.v.count > 0 and vim.v.count or 10
    dashboard_state.scroll_by(-lines)
  end, "GitHub Stats: scroll half page up")

  -- Page navigation: Ctrl-f/b (fixed)
  -- count1: e.g. 3<C-f> scrolls 3 pages instead of 1
  map_key(buf, "<C-f>", function()
    local page_size = state.win_height - render.HEADER_LINES
    dashboard_state.scroll_by(page_size * vim.v.count1)
  end, "GitHub Stats: scroll full page down")

  map_key(buf, "<C-b>", function()
    local page_size = state.win_height - render.HEADER_LINES
    dashboard_state.scroll_by(-page_size * vim.v.count1)
  end, "GitHub Stats: scroll full page up")

  -- Jump to top/bottom: gg/G (fixed)
  -- Raw count: 0 (no prefix) keeps jumping to first/last; NgG or Ngg jumps
  -- to repository N instead (clamped, matching Vim's own gg/G convention).
  map_key(buf, "gg", function()
    if vim.v.count > 0 then
      jump_to_repo(state, vim.v.count)
    else
      dashboard_state.set_current_index(1)
      dashboard_state.set_scroll_offset(0)
    end
  end, "GitHub Stats: jump to top")

  map_key(buf, "G", function()
    if vim.v.count > 0 then
      jump_to_repo(state, vim.v.count)
    else
      dashboard_state.set_current_index(#state.repos)
      local max_scroll = state.max_scroll
      dashboard_state.set_scroll_offset(max_scroll)
    end
  end, "GitHub Stats: jump to bottom")

  -- View details: configurable (default <CR>)
  map_key(buf, keybindings.show_details, function()
    if state.current_index >= 1 and state.current_index <= #state.repos then
      local repo = state.repos[state.current_index]
      detail.show_detail(repo)
    end
  end, "GitHub Stats: show repository details")

  -- Refresh: configurable (default r) -- drops the storage read memo and
  -- re-renders from disk, without hitting the API. This is what makes `r`
  -- mean something plain navigation does not: since the memo landed, every
  -- other render is served from memory, so `r` is the documented way to pick
  -- up a change another window (or another Neovim) wrote.
  map_key(buf, keybindings.refresh_selected, function()
    require("github_stats.storage").invalidate()
    require("github_stats.dashboard").schedule_render(true)
  end, "GitHub Stats: re-read from disk and refresh")

  -- Re-render once a fetch the two keys below started is done: without it the dashboard kept showing the numbers
  -- from before the fetch until something else redrew it (integrations/menu.lua passes the same callback).
  local function render_after_fetch()
    require("github_stats.dashboard").schedule_render(true)
  end

  -- Refresh all: configurable (default R) -- force-fetches every configured repo
  map_key(buf, keybindings.refresh_all, function()
    config.notify("[github-stats] Refreshing all repositories...", "info")
    actions.refresh_all(render_after_fetch)
  end, "GitHub Stats: refresh all repositories")

  -- Force refresh: configurable (default f) -- force-fetches the selected repo
  map_key(buf, keybindings.force_refresh, function()
    config.notify("[github-stats] Force-refreshing selected repository...", "info")
    actions.force_refresh_selected(render_after_fetch)
  end, "GitHub Stats: force refresh selected repository")

  -- Cycle sort: configurable (default s)
  -- A count advances that many positions, matching how `j`/`k`/`<C-f>` in
  -- this dashboard already read one. `count1`, since no count means one step.
  map_key(buf, keybindings.cycle_sort, function()
    actions.cycle_sort(vim.v.count1)
  end, "GitHub Stats: cycle sort criteria")

  -- Cycle time range: configurable (default t)
  map_key(buf, keybindings.cycle_time_range, function()
    actions.cycle_time_range(vim.v.count1)
  end, "GitHub Stats: cycle time range")

  -- Custom time range: configurable (default T) -- prompts for a free-form
  -- expression instead of stepping through the fixed 7d/30d/90d/all cycle
  map_key(buf, keybindings.custom_time_range, function()
    actions.prompt_custom_time_range()
  end, "GitHub Stats: enter custom time range")

  -- Max time range: configurable (default m) -- one keypress to the longest
  -- window the stored data can cover, instead of stepping the t cycle around
  -- or typing an expression at the T prompt
  map_key(buf, keybindings.max_time_range, function()
    actions.set_max_time_range()
  end, "GitHub Stats: set maximum time range")

  -- Quit: configurable (default q), plus fixed Esc fallback. The dashboard
  -- buffer is bufhidden=wipe, so closing the window here also triggers the
  -- BufWipeout -> cleanup_dashboard() -> ui_state.cleanup_all() chain set up
  -- in dashboard/init.lua; nice_quit's plain nvim_win_close is enough.
  local quit_keys = { "<Esc>" }
  if keybindings.quit and keybindings.quit ~= "" then
    quit_keys[#quit_keys + 1] = keybindings.quit
  end
  local win = ui_state.get_win()
  if win then
    window.nice_quit(win, { keys = quit_keys, force = true })
  end

  -- Help: configurable (default ?)
  map_key(buf, keybindings.show_help, function()
    config.notify(
      "GitHub Stats Dashboard Keybindings:\n"
        .. string.format("  %s/%s/↑/↓   - Navigate up/down\n", keybindings.navigate_down, keybindings.navigate_up)
        .. "  <C-d/u>   - Scroll half page\n"
        .. "  <C-f/b>   - Scroll full page\n"
        .. "  gg/G      - Jump to top/bottom\n"
        .. string.format("  %-9s - View repository details\n", keybindings.show_details)
        .. string.format("  %-9s - Refresh dashboard\n", keybindings.refresh_selected)
        .. string.format("  %-9s - Refresh all repositories\n", keybindings.refresh_all)
        .. string.format("  %-9s - Force refresh selected repository\n", keybindings.force_refresh)
        .. string.format("  %-9s - Cycle sort criteria\n", keybindings.cycle_sort)
        .. string.format("  %-9s - Cycle time range\n", keybindings.cycle_time_range)
        .. string.format("  %-9s - Enter custom time range (e.g. 3m, since:2025-01-01)\n", keybindings.custom_time_range)
        .. string.format("  %-9s - Maximum time range (full stored history)\n", keybindings.max_time_range)
        .. string.format("  %-9s - Quit\n", keybindings.quit)
        .. string.format("  %-9s - Show this help", keybindings.show_help),
      "info"
    )
  end, "GitHub Stats: show help")
end

return M

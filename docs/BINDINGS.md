# Bindings Reference

Complete reference of all user commands, keymaps, and autocmds registered by
GitHub Stats. Implementation lives under `lua/github_stats/bindings/`.

## Table of Contents

- [User Commands](#user-commands)
- [Dashboard Keymaps](#dashboard-keymaps)
  - [Configurable](#configurable)
  - [Fixed](#fixed)
- [Autocmds](#autocmds)

---

## User Commands

One command, `:GithubStats <subcommand>` (built via
[`lib.nvim.bindings.usercmd.composer`](https://github.com/WKDSteve/lib.nvim), with
`<Tab>` completion at every level — subcommand name, then each positional
argument; repo names and date presets complete dynamically from live
config). Registered in
[`lua/github_stats/bindings/usrcmds/init.lua`](../lua/github_stats/bindings/usrcmds/init.lua).
See [docs/commands.md](commands.md) for full usage examples.

**The bang attaches to the verb, not the subcommand**: forced dashboard
refresh is `:GithubStats! dashboard`, not `:GithubStats dashboard!`. Vim's
`!` always binds to the command name itself, so a single verb has exactly
one bang slot shared across all its subcommands.

| Command | Args | Description |
|---|---|---|
| `:GithubStats setup` | – | Setup guide: where the history lives (remote data repository or local) and what remote mode needs |
| `:GithubStats sync` | – | Remote mode: push a changed `config.json`, pull the data repository |
| `:GithubStats fetch` | `[force]` | Fetch all metrics, respecting (or bypassing) the configured interval; in remote mode start the workflow instead |
| `:GithubStats show` | `{repo} {metric} [start] [end]` | Show detailed stats for a repository/metric |
| `:GithubStats summary` | `{clones\|views}` | Aggregated summary across all configured repos |
| `:GithubStats referrers` | `{repo} [limit]` | Top referrers for a repository |
| `:GithubStats paths` | `{repo} [limit]` | Top paths for a repository |
| `:GithubStats chart` | `{repo} {clones\|views\|both} [start] [end]` | ASCII sparkline/comparison chart |
| `:GithubStats export` | `{repo\|all} {clones\|views\|both} {filepath}` | Export to CSV, Markdown, or PDF (`.pdf` needs pdfport.nvim) |
| `:GithubStats diff` | `{repo} {metric} {period1} {period2}` | Compare two periods |
| `:GithubStats compact` | `[dry-run]` | Archive old clones/views data and prune stale referrers/paths snapshots (use `dry-run` to preview; remote mode: dry-run only) |
| `:GithubStats digest` | – | Rebuild the per-repository digest other programs read |
| `:GithubStats debug` | – | Print configuration/token/last-fetch diagnostics |
| `:GithubStats[!] dashboard` | – | Open the dashboard (`!` requests a forced refresh) |

All commands with repo/metric/path arguments support Tab-completion.

---

## Dashboard Keymaps

Registered in [`lua/github_stats/bindings/keymaps.lua`](../lua/github_stats/bindings/keymaps.lua),
scoped to the dashboard buffer (`:GithubStats dashboard`).

### Configurable

Set via `dashboard.keybindings` in `setup()`. Set a key to `""` to disable it.
Defaults come from [`lua/github_stats/config/DEFAULTS.lua`](../lua/github_stats/config/DEFAULTS.lua).

| Config key | Default | Action |
|---|---|---|
| `navigate_down` | `j` | Move selection down |
| `navigate_up` | `k` | Move selection up |
| `show_details` | `<CR>` | Open detailed view for the selected repo |
| `refresh_selected` | `r` | Drop the in-memory read cache and re-render from disk (no API call) |
| `refresh_all` | `R` | Force-fetch all configured repositories from GitHub, then re-render |
| `force_refresh` | `f` | Force-fetch the selected repository from GitHub, then re-render |
| `cycle_sort` | `s` | Cycle sort criteria: `clones` → `views` → `name` → `trend`. `Ns` advances N positions |
| `cycle_time_range` | `t` | Cycle time range: `7d` → `30d` → `90d` → `max`. `Nt` advances N positions |
| `custom_time_range` | `T` | Prompt for a free-form time range expression (e.g. `3m`, `since:2025-01-01`, a date preset name) |
| `max_time_range` | `m` | Set the range to `max`: the longest duration the locally stored data covers, and notify the concrete span |
| `quit` | `q` | Close the dashboard |
| `show_help` | `?` | Show the keybinding help overlay |

Both counts are taken **modulo the cycle length**, so `5s` over a four-entry
cycle lands one along rather than looping four extra times for nothing, and
`4s` is a deliberate no-op (a full loop). A count larger than the cycle is a
fat-fingered keypress, not a request to spin. This matches the rest of the
dashboard, where `j`/`k`, `<C-d>`/`<C-u>`, `<C-f>`/`<C-b>` and `Ngg`/`NG`
already read a count.

Sorting and time-range filtering are applied on every render based on
`state.sort_by`/`state.time_range` (see
[`lua/github_stats/dashboard/render.lua`](../lua/github_stats/dashboard/render.lua)); the
cycle keys just advance that state. `custom_time_range` instead prompts via
`vim.fn.input()` for a free-form expression, validated against
[`analytics.parse_time_range`](../lua/github_stats/analytics.lua) before being
applied -- an unrecognized expression is rejected with an error notification
and the previous range is kept. `max_time_range` is the one-keypress route to
the other end of that scale: it sets the range to `max` (no filtering, i.e.
everything left on disk after retention -- `all` remains an accepted synonym)
and notifies the span it resolved to, e.g. `2025-03-04 to 2026-08-22, 172
days`. The dashboard header prints that same resolved span next to whatever
range is active, so "how much history am I actually looking at?" is always
answered on screen. `refresh_all`/`force_refresh` are
implemented in
[`lua/github_stats/dashboard/actions.lua`](../lua/github_stats/dashboard/actions.lua)
and go through [`lua/github_stats/fetcher.lua`](../lua/github_stats/fetcher.lua)
to hit the GitHub API, bypassing the normal fetch-interval check.

### Fixed

Always active, not user-configurable (mirror standard Vim navigation, not
tied to the customizable action set above):

| Key | Action |
|---|---|
| `<Down>` / `<Up>` | Navigate down/up (arrow-key mirror of `navigate_down`/`navigate_up`), count-aware |
| `<C-d>` / `<C-u>` | Scroll down/up by 10 lines, or by an explicit count (`5<C-d>`) |
| `<C-f>` / `<C-b>` | Scroll full page down/up; `N<C-f>` scrolls N pages |
| `gg` / `G` | Jump to first/last repository; `Ngg` / `NG` jumps to repository N (clamped) |
| `<Esc>` | Quit dashboard (fixed fallback alongside `quit`) |
| `<Left>` / `<Right>` / `<PageUp>` / `<PageDown>` / `<Home>` / `<End>` / `h` / `l` | Mapped to `<Nop>`: native cursor movement would race the dashboard's own selection state |
| `<RightMouse>` | Open a context menu mirroring the keymaps above (`nvzone/menu`, soft dependency; `dashboard.menu.enable` to disable) — see [Right-Click Context Menu](dashboard.md#right-click-context-menu) |

---

## Autocmds

| Event | Group | Scope | Location | Purpose |
|---|---|---|---|---|
| `VimEnter` | `GithubStatsAutoFetch` | global | [`lua/github_stats/bindings/autocmds.lua`](../lua/github_stats/bindings/autocmds.lua) | Starts the background fetch/discovery cycle; opens the dashboard 1s later if `dashboard.enabled` and `dashboard.auto_open` are both set |
| `BufWipeout` | – | dashboard buffer | [`lua/github_stats/dashboard/init.lua`](../lua/github_stats/dashboard/init.lua) | Cleans up dashboard state/timers when the dashboard buffer is wiped |
| `VimResized` | – | dashboard buffer | [`lua/github_stats/dashboard/init.lua`](../lua/github_stats/dashboard/init.lua) | Recomputes the float's width/height/centering for the new editor size and re-renders |

The last two are buffer-scoped and created per dashboard instance at open
time, so they live next to the code that creates that buffer rather than in
`bindings/autocmds.lua`, which only owns plugin-lifecycle (non-buffer-scoped)
autocmds. That is also why they carry no group: `buffer` ties their lifetime
to the dashboard buffer instead -- including `VimResized`, which is not
itself a buffer event, but is torn down the same way once the buffer it was
registered against is wiped.

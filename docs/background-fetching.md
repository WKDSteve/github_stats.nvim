# Background fetching

How the silent background fetch/discovery cycle works under the hood. For
the user-facing configuration and the two intervals it juggles, see
[WORKFLOW.md](WORKFLOW.md#background-fetching-runs-the-whole-session--know-the-two-intervals);
for the catalog entry, [FEATURES/FETCHING.md](FEATURES/FETCHING.md).

> **Remote mode (the default) does not fetch here.** When the history lives
> in a data repository ([FEATURES/REMOTE.md](FEATURES/REMOTE.md)), the same
> cycle and timer only *pull* that repository: the first cycle after
> `initial_delay_ms`, then every `storage.pull_interval_minutes` (default 60).
> A pull that brought something drops the read memo and rebuilds stale
> digests. Everything below describes the fetch of local mode.

## Entry point

[`lua/github_stats/bindings/autocmds.lua`](../lua/github_stats/bindings/autocmds.lua)
registers a single `VimEnter` autocmd whose callback calls
`require("github_stats.background").start()` (in remote mode with a known but
not yet cloned data repository it clones first, then starts the cycle; with
none known it may also open the setup guide once). This is the only place
`background.lua` gets invoked from; nothing else in the plugin calls it.

## `M.start()`

```lua
function M.start()
  if timer then
    return                                        -- already running
  end

  local cfg = require("github_stats.config").get()
  if cfg and cfg.background and cfg.background.enabled == false then
    return                                        -- disabled outright
  end

  vim.defer_fn(run_cycle, initial_delay_ms(cfg))  -- one deferred cycle

  timer = vim.uv.new_timer()                      -- then recurring cycles
  if timer then
    local interval_ms = poll_interval_ms(cfg)
    timer:start(interval_ms, interval_ms, vim.schedule_wrap(run_cycle))
  end
end
```

Two guards, then two actions:

- **Guard 1 — double-start**: a module-level `local timer` upvalue. If it is
  already set, `start()` is a no-op. This matters because `M.setup()` (the
  plugin's public entry point) could in principle run more than once in a
  session (reload, re-`require`), and two competing timers is never what was
  wanted.
- **Guard 2 — `background.enabled = false`**: bails out before creating
  anything. The user is then fully on manual `:GithubStats fetch`.
- **Action 1**: one deferred cycle, `background.initial_delay_ms` after
  `VimEnter` (default `1000`), so it does not compete with Neovim's own
  startup work. It is a configuration key rather than a constant because how
  long startup takes is a property of the user's config, not of this plugin:
  one second is plenty after a lean start and lands in the middle of a heavy
  one.
- **Action 2**: a *recurring* `vim.uv` timer — this is the "runs for the
  whole session" part. Fetching once per `VimEnter` meant a day-long
  tmux/nvim session never fetched again until restarted.

### Poll interval vs. fetch interval — two different things

```lua
local function poll_interval_ms(cfg)
  local interval_hours = (cfg and cfg.fetch_interval_hours) or 24
  local minutes = math.min(60, interval_hours * 60)
  return math.floor(minutes * 60 * 1000)
end
```

`fetch_interval_hours` (existing config) still governs when a fetch is
*actually due* — that check lives entirely in
[`fetcher.lua`](../lua/github_stats/fetcher.lua)'s `should_fetch()` and is
untouched by this feature.

The timer's own period is a *derived* value, not a new config knob: `min(60,
fetch_interval_hours * 60)` minutes. It controls how often the plugin
*checks* whether a fetch is due, capped at once per hour. With the default
`fetch_interval_hours = 24`, that means: check every 60 minutes whether 24h
have passed, so a fetch that becomes due mid-session lands within an hour
instead of waiting for the next restart. If `fetch_interval_hours` is
smaller than 1, the check cadence shrinks to match it — there is no point
checking less often than the thing being checked for.

## `run_cycle()`

```lua
local function run_cycle()
  local cfg = config.get()
  local watch_users = cfg and cfg.watch_users or {}

  if #watch_users == 0 then
    fetcher.fetch_all(false, nil, { background = true })
    return
  end

  repo_discovery.discover(watch_users, function(repo_names, errors)
    config.set_discovered_repos(repo_names)
    for username, err in pairs(errors) do
      config.notify(string.format("[github-stats] Failed to discover repos for '%s': %s", username, err), "warn")
    end
    fetcher.fetch_all(false, nil, { background = true })
  end)
end
```

Every tick (the initial deferred one and every recurring one) does the same
thing:

1. If `watch_users` is empty, skip straight to fetching.
2. Otherwise, re-run discovery first: `repo_discovery.discover()` calls
   `api.list_user_repos()` for every configured username in parallel,
   paginating each one (`GET /users/{username}/repos?per_page=100&page=N`,
   following pages until a short one or until `max_user_repo_pages`), merges
   and dedupes the results, and reports per-username failures separately —
   one bad username cannot block the others (see
   [`repo_discovery.lua`](../lua/github_stats/repo_discovery.lua)).
3. `config.set_discovered_repos(repo_names)` replaces the discovered-repos
   cache in `config/init.lua`. `config.get_repos()` returns the deduped union
   of the static `repos` list and this cache (static list first, so its
   order is preserved) — this is the single place the merged repo list is
   computed; everything else (fetcher, dashboard, health, debug) just calls
   `config.get_repos()` and does not know or care where a given repo name
   came from.
4. Discovery errors are notified immediately (`config.notify(..., "warn")`),
   *unconditionally* — these are not gated by the `background` flag the way
   fetch notifications are, since a bad `watch_users` entry (typo, deleted
   account) is exactly the kind of thing you would otherwise never learn
   about.
5. Fetch with `{ background = true }`.

## Where the actual silence lives

`background.lua` itself suppresses nothing — it just always passes
`{ background = true }` into `fetcher.fetch_all()`. The gating happens inside
`fetch_all`:

```lua
if not background then
  config.notify(str_format("[github-stats] Starting fetch: %d repos, force=%s", #repos, tostring(force)), "info")
end
...
if error_count > 0 then
  config.notify(str_format("[github-stats] Fetched %d metrics, %d errors", #all_success, error_count), "warn")
elseif not background then
  config.notify(str_format("[github-stats] Successfully fetched %d metrics", #all_success), "info")
end
```

So: the "starting fetch" and "successfully fetched" info notifications are
skipped when `background = true`, but the "N errors" warning is
**unconditional** — it always fires when there were errors, in both
background and explicit (`:GithubStats fetch`, dashboard `R`/`f`) calls. That
warning still passes through `config.notify()`, so `notification_level =
"silent"` still means silent if that is what the user actually wants; the
`background` flag only changes the *default* noise level of routine
background activity, it does not add a second independent gate.

The progress indicator follows the same rule from the other side:
`fetch_all` only builds one when `background` is false, so a manual fetch
shows `progress_style` and a background cycle never does.

Explicit user-triggered fetches always pass `background = false` (or omit
`opts` entirely, which defaults the same way), so they keep the full
"starting/success/error" notification sequence regardless of this feature.

## `M.stop()`

Not called from anywhere in production code — it exists for tests and for
symmetry with `M.start()`. It stops and closes the `uv_timer_t` if one
exists (guarding on `is_closing()`), then clears the upvalue so a later
`M.start()` can create a fresh one.

## Failure modes worth knowing about

- If `config.get()` returns `nil` when a cycle runs (it should not normally —
  `background.start()` is only wired up after `config.init()` succeeds in
  `github_stats/init.lua`'s `M.setup()`), `run_cycle()` treats `watch_users`
  as empty and calls `fetch_all` anyway, which itself handles a nil/empty
  repo list gracefully.
- A `vim.system`/curl failure during discovery for one username does not
  abort discovery for the others — see the per-username error map in
  `repo_discovery.discover()`.
- `vim.uv.new_timer()` can return `nil`; `start()` checks before calling
  `timer:start()`, so a failed allocation costs the recurring cycle but not
  the deferred first one.
- The discovered-repos cache is **in-memory only**, not persisted to
  `config.json` or disk. It is rebuilt from scratch on every cycle (including
  the first one after a restart), by design — the whole point is that it
  never needs manual maintenance.

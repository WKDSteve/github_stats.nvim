# Fetching, background cycle, and auto-discovery

## Traffic data fetching

- **Module:** `fetcher.lua` (`fetch_all`, `fetch_repo`, `should_fetch`), `api.lua`
- **Usercmds:** `:GithubStats fetch [force]`
- **Config:** `opts.fetch_interval_hours` (default `24`), `opts.max_parallel_fetches` (default `4`), `opts.api_timeout_ms` (default `15000`: timeout of one GitHub API request, in ms), `opts.progress_style` (default `"auto"`), `opts.notify_fetch` (default `true`)

Fetches clones, views, referrers, and paths (4 GitHub API calls per repo,
run in parallel) for every configured repository. At most
`max_parallel_fetches` repositories are in flight at once (each one is four
`curl` processes); the rest wait in a queue and start as slots free up.
Starting a process is synchronous and costs roughly 10-15 ms on Windows,
much more where AV/EDR scans every spawn, so an uncapped fan-out over dozens
of repositories (for example via `watch_users`) blocked the UI for the whole
burst. A repository whose fetch fails to start (`curl` could not be spawned)
is recorded as that repository's error and the queue moves on, so the fetch
still completes. The dashboard's single-repository refresh is not queued. Without `force`, a fetch
is skipped if the last one ran within `fetch_interval_hours`; `force`
bypasses that check, and `notify_fetch` decides whether a skipped manual
fetch says so ("Fetch interval not elapsed") or stays quiet.
Inside the interval, a repository **without any stored data** (just added to `repos`, or newly
found through `watch_users`) is still fetched at once, with one info line naming it ("Fetching 1 new
repository: owner/name"; shown in a background cycle too). Everything else keeps waiting for its
interval, and such a partial fetch leaves `last_fetch.json` alone, so it never pushes the regular
full fetch out. A repository whose fetch keeps failing has no data and is therefore retried by every
unforced fetch; fix or remove it from `repos`.
`fetcher.last_fetch_summary` records per-repo/metric
errors, surfaced by `:GithubStats debug`. Manual fetches report live
progress through the optional [`lib.nvim.progress`](https://github.com/WKDSteve/lib.nvim)
dependency (`progress_style`, no-op without lib.nvim installed) — the
silent background cycle deliberately never uses it.

## Silent background fetch cycle

- **Module:** `background.lua` (`start`, `stop`)
- **Autocmds:** `VimEnter` in `bindings/autocmds.lua` starts it after a deferred first cycle
- **Config:** `opts.background.enabled` (default `true`), `opts.background.initial_delay_ms` (default `1000`)

Runs for the entire Neovim session rather than fetching only once at
`VimEnter`: a `vim.uv` timer periodically checks whether a fetch is due
(polling at `min(60, fetch_interval_hours * 60)` minutes — this only governs
how promptly a long session notices a due fetch, not the interval itself)
and, if `watch_users` is set, re-discovers repositories first. Success is
silent; real errors still notify, subject to `notification_level`.
`background = { enabled = false }` disables this entirely, leaving only
manual `:GithubStats fetch`.

The full walkthrough of the cycle — both guards, both intervals, and where
the silence actually lives — is in
[background-fetching.md](../background-fetching.md).

## Auto-discovery via `watch_users`

- **Module:** `repo_discovery.lua` (`discover`) over `api.lua`'s `list_user_repos`, merged into `config.get_repos()`
- **Config:** `opts.watch_users` (default `{}`), `opts.max_user_repo_pages` (default `30`)

Lists every public repository of each configured GitHub username
(`api.list_user_repos`) and merges the result into the tracked repo list
alongside the explicit `repos` list (explicit entries first, deduplicated).
Re-resolved on every background cycle, so a newly created repo under a
watched user starts appearing without editing config. A repo without push
access simply never populates traffic data — GitHub's traffic API requires
it.

Listing pages at 100 repositories each, following at most
`max_user_repo_pages` pages. Past that cap later repositories are **silently
not tracked**, which is why the cap is a configuration key rather than a
constant.

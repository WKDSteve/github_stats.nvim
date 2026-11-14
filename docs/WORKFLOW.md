# Workflow — getting real use out of github_stats.nvim day to day

Every feature here is documented on its own elsewhere (`docs/FEATURES/`,
`docs/commands.md`, `docs/dashboard.md`). This is the different
question: once several features exist, *how do they actually combine* into
a routine worth running regularly, and which combinations trip people up.

## First session: the guide, then `:checkhealth`

On the first start the setup guide asks where the history lives
([FEATURES/REMOTE.md](FEATURES/REMOTE.md)). In remote mode the token that
matters is the data repository's secret `GH_STATS_TOKEN`: the workflow
fetches, this machine never does, and the checks below about this machine's
token only matter for local mode. The workflow's run log on GitHub is where a
fetch problem shows up.

## First session: `:checkhealth` before you trust any data

Run `:checkhealth github_stats` before doing anything else in a new setup.
It checks config validity, token presence, `curl` availability, storage
writability, dashboard config shape, *and* does a synchronous live API call
(10s timeout) against your first configured repo — so a bad token or a
mistyped repo name shows up as a specific `401`/`403`/`404` right away
instead of as a silent "no data" dashboard entry later. `:GithubStats debug`
is the companion for later — same checks, plus whatever
`fetcher.last_fetch_summary` recorded from the most recent actual fetch, so
reach for it after a fetch has already run, not before.

## `repos` vs `watch_users` — pick the maintenance burden you want

`repos` is a hand-maintained list; `watch_users` auto-discovers every public
repo of a GitHub username and re-resolves it **every background cycle** (not
once at startup), so a repo you create this afternoon shows up in the
dashboard tonight without touching config. The trap: `watch_users` only
gets you repos GitHub itself can see the traffic API for — a discovered repo
you don't have push access to (an org repo where you're a read-only
collaborator, for instance) will sit in the dashboard permanently showing
"No Data", not an error. If a discovered entry never populates, that's
expected, not a bug to chase with `:GithubStats debug`.

Both lists merge (explicit `repos` first, then discovered, deduplicated) —
`config.get_repos()` is the one place this happens, so fetcher, dashboard,
health, and debug all see the same combined list regardless of which
mechanism put a given repo on it.

## Background fetching runs the whole session — know the two intervals

`background.enabled = true` (the default) means the plugin fetches on its
own for as long as Neovim stays open, not just once at `VimEnter`. Two
numbers govern this and they are **not the same knob**:

- `fetch_interval_hours` (default `24`) — how old data has to be before a
  fetch is actually *due*. Lives in `fetcher.should_fetch()`.
- The background timer's own poll period — `min(60, fetch_interval_hours *
  60)` minutes, derived automatically, not user-configurable. It only
  controls how often the plugin *checks* whether a fetch is due. With the
  default 24h interval, that means: check every 60 minutes, so a fetch that
  becomes due mid-session lands within the hour instead of waiting for the
  next restart.

Practical effect: setting `fetch_interval_hours = 1` doesn't just fetch
hourly, it also makes the poll check every minute (the `min(60, ...)` cap
only bites above 60 minutes) — fine, but worth knowing before setting it
very low across many repos and a tight token rate limit.

Background fetches are silent on success: `background = true` suppresses
only the routine "starting fetch" / "successfully fetched" chatter, not the
error path — an "N errors" warning still fires the same way it would for a
manual fetch. Both still route through `config.notify()`, so
`notification_level = "silent"` genuinely means silent either way. If you
want to see routine fetch activity while debugging a setup, don't look for
a `background`-specific toggle — set `notification_level = "all"` (the
default) and either wait for the next poll or force one manually.

The mechanics of both guards and both intervals are written out in
[background-fetching.md](background-fetching.md).

## Manual fetch: `force` bypasses the interval, nothing else does

```vim
:GithubStats fetch force
```

is the only way to get fresh data on demand outside the dashboard's own `f`
(selected repo) / `R` (all repos) keys, which do the same interval bypass
through `fetcher.fetch_repo` / `fetcher.fetch_all(true, ...)`. Manual
fetches (unlike background ones) report live progress through the optional
`lib.nvim.progress` dependency if installed (`progress_style`) — useful
signal on a dozen-plus repos where a full fetch is 4 API calls each and can
run for a while with nothing on screen otherwise.

## Dashboard: `r` vs `f` vs `R` is the mistake worth avoiding

`r` only **re-renders from cache** — it never talks to the network, so
pressing it repeatedly on a repo showing "No Data" does nothing. `f` fetches
just the selected repo; `R` fetches everything. The natural first move on a
stale-looking dashboard is `r` because it's the "default" refresh feel from
other tools, but here it's a no-op unless something else already fetched.
If a repo is genuinely stale, `f` is the cheap fix; reach for `R` only when
you actually want every repo hit at once (rate-limit cost scales with repo
count).

## Time range: `t` cycles, `T` types — and `T` never touches the network either

`t` cycles the dashboard's aggregation window through a fixed `7d → 30d →
90d → max` list, and `m` jumps straight to `max` in one keypress. `max` is the
longest span the locally stored data actually covers, and the header names the
window it resolved to — `Range:max (2025-03-04 → 2026-08-22, 172 days)`, or
`(no data)` when nothing is stored. `max` and `all` filter identically; `all`
is still accepted from `setup()` and the `T` prompt, `max` is the label the
cycle produces. Both cycles take a count (`Nt`, `Ns`), taken modulo the cycle
length, so a count larger than the cycle lands where it should instead of
looping. `T` opens a prompt (pre-filled with the current value) for
anything `analytics.parse_time_range` understands — `14d`, `3m`, `1y`,
`since:2025-01-01`, a bare ISO date, or any configured date-preset name
(`this_month`, `last_quarter`, a custom one from
`docs/configurations/USER-DEFINED-DATE-PRESETS.md`). Both are purely local
re-aggregation over data you already fetched; changing the range, however
wide, never triggers an API call by itself — pair a `T` jump to `all` with
`f`/`R` first if the wider range needs data you haven't fetched yet, since
widening the window alone won't retroactively fill in history you never
pulled.

An unrecognized `T` expression is rejected with an error notification and
the *previous* range stays active — it doesn't fall back to a default, so a
typo is safe to retry immediately.

**`3m` and `1y` are calendar-accurate, not 90 and 365 days.** They used to be
fixed blocks while the date presets accepted in the very same field
(`this_month`, `this_quarter`, `this_year`) were calendar-exact — two notions
of accuracy in one prompt, differing by up to five days a year. One month back
from the 31st now lands on the 28th, 29th or 30th, and `Ny` is `12 * N` months.
Worth knowing when comparing a `3m` figure against one you wrote down earlier.

## Reading the header before reading the list

The header answers the question the list cannot: *how is this going overall?*
Its second line carries clones and views summed over the active range plus the
repository with the most clones — summed from the per-repository stats already
computed for that render, so it costs nothing. No top repository is named while
nothing has been cloned, because "top" would then only mean "sorts first".

Each entry's `Period:` line ends with a sparkline of daily clones over the
range, which is the fastest way to tell a steady trickle from one spike — the
two produce the same total and mean entirely different things.

**`Trend` is measured over a fixed window, not over what is on screen.** It
used to halve whatever range was displayed and compare the two halves, so the
same `⬆ +67%` meant "last 3 days vs the 3 before" at `Range:7d` and "second
half-year vs first" at `Range:max`, with nothing on screen saying which — and
`sort_by = "trend"` was ordering repositories by quantities comparable only by
accident. It is now the last N complete days against the N before them, the
same N whatever is displayed, named in the header as `Trend:7d/7d` and set by
`dashboard.trend_window_days`.

The practical consequence: **changing the range no longer changes the trend.**
If you were reading the two together, they are now independent — the range is
what you are looking at, the trend is a fixed-window measurement beside it.

## Retention: dry-run before you trust the numbers on someone else's config

```vim
:GithubStats compact dry-run
:GithubStats compact
```

`retention.enabled = true` (default) already runs this automatically at
most once per 24h, opportunistically after a fetch, so most users never
need the manual command. Reach for it directly after changing
`retention.cutoff_days`/`prune_days` and wanting to see the effect
immediately rather than waiting for the next opportunistic run. The gotcha:
`cutoff_days` has a hard floor of `14` enforced in code
(`math.max(opts.cutoff_days or 15, 14)`) regardless of what you configure
lower, because GitHub's traffic API is itself a rolling 14-day window — a
day can't be considered final until it's aged out of that window. Setting
`cutoff_days = 5` in config silently behaves like `14`, not `5`; `dry-run`
is the fast way to notice that before assuming your config took effect.

## Export: check the format matrix before picking a target for `all`

CSV only supports a single repo — `:GithubStats export all clones
report.csv` is not a shortcut for "everything in one CSV", it's an error
(`'all' target only supports Markdown/PDF format`). For a fleet-wide report, go
straight to `.md` (or `.pdf` with `pdfport.nvim` installed):

```vim
:GithubStats export all both ~/reports/weekly.md
```

`both` (clones + views in one report) plus `all` (every configured repo) is
the combination that produces the single most useful weekly artifact — one
file with a Highlights section (`analytics.compute_highlights`: most
cloned/viewed repo, best month, best single day) instead of per-repo
digging. PDF export is a thin wrapper that hands the exact same Markdown
lines to `pdfport.create()` — if a `.md` export looks right, the `.pdf`
version of the same command will too; if `pdfport.nvim` isn't installed or
lacks a Markdown-capable backend (`pandoc` + a PDF engine), the export fails
outright rather than silently downgrading to `.md`, so don't script around
an assumed fallback.

## `diff` for reporting, `chart both` for spotting it first

The realistic order for "did something change" is: `chart {repo} both` to
eyeball count vs. uniques trend lines together, then `diff {repo} {metric}
{period1} {period2}` once you already know which two months/years you want
numbers for. `diff` compares by average-per-day specifically so a 28-day
February and a 31-day January are still a fair comparison — don't
hand-adjust for period length before calling it, the command already does
that. A zero-traffic `period1` reports `+∞`, not an error — expected for a
repo's very first active month.

## Config precedence: defaults < `config.json` < `setup()`

The configuration is three layers (`lib.lua.config.new` in `config/init.lua`),
the highest wins **key by key**: the built-in defaults, then `config.json`
(written with the defaults on the first run), then the table passed to
`setup()`. A nested table merges the same way, so `setup({ dashboard = {
header_width = 100 } })` changes that one value and keeps the rest of the
dashboard section from the file. A list (`repos`, `watch_users`) is replaced
whole. The file is never changed by `setup()`. If you maintain `config.json`
for cross-machine sync and pass `repos` into `setup()` on one machine "just to
test something," that machine uses the `repos` of `setup()`, and everything
else from the file.

An option dropped from `setup()` is gone at the next start (nothing carries
over). A key the plugin does not know and a value of the wrong type are
reported with a hint (`fetch_intervall_hours` -> did you mean
`fetch_interval_hours`) and left out, so the default applies; `config_dir`
and `data_dir` are paths, not options.

## Remote mode: the list of repositories lives in the data repository

In remote mode the workflow reads only the data repository's `config.json`;
it never sees your `setup()`. A `repos` (or `watch_users`) you pass to
`setup()` still wins locally, so the dashboard would list repositories the
workflow does not collect, or miss ones it does. Keep the list in the
clone's `config.json` and out of `setup()`, then `:GithubStats sync` pushes
it. The same goes for every option the collect step uses (`retention`,
`watch_users`, `max_user_repo_pages`); options only the editor uses
(`dashboard`, `progress_style`, `notification_level`) can stay in `setup()`.

# GitHub Stats User Commands

Complete reference for all available user commands.

One command, `:GithubStats <subcommand>` (built via
[`lib.nvim.bindings.usercmd.composer`](https://github.com/WKDSteve/lib.nvim)), with
`<Tab>` completion at every level — subcommand name, then each positional
argument. Repository names and date presets complete dynamically from live
configuration.

## Table of Contents

- [Command Overview](#command-overview)
- [GithubStats setup](#githubstats-setup)
- [GithubStats sync](#githubstats-sync)
- [GithubStats fetch](#githubstats-fetch)
- [GithubStats show](#githubstats-show)
- [GithubStats summary](#githubstats-summary)
- [GithubStats referrers](#githubstats-referrers)
- [GithubStats paths](#githubstats-paths)
- [GithubStats chart](#githubstats-chart)
- [GithubStats export](#githubstats-export)
- [GithubStats diff](#githubstats-diff)
- [GithubStats compact](#githubstats-compact)
- [GithubStats digest](#githubstats-digest)
- [GithubStats debug](#githubstats-debug)
- [GithubStats dashboard](#githubstats-dashboard)
- [Common Patterns](#common-patterns)

---

## Command Overview

| Command | Purpose | Autocompletion |
|---------|---------|----------------|
| `:GithubStats setup` | Guide: where the history lives (remote data repository or local) | None |
| `:GithubStats sync` | Remote mode: push a changed `config.json`, pull the data repository | None |
| `:GithubStats fetch` | Fetch traffic data manually (remote mode: start the workflow) | `force` |
| `:GithubStats show` | Detailed statistics for repo/metric | Repos, metrics |
| `:GithubStats summary` | Aggregate across all repositories | Metrics |
| `:GithubStats referrers` | Top referrer sources | Repos |
| `:GithubStats paths` | Most visited paths | Repos |
| `:GithubStats chart` | Visual charts and sparklines | Repos, metrics |
| `:GithubStats export` | Export to CSV/Markdown/PDF (clones/views/both) | Repos, metrics, paths |
| `:GithubStats diff` | Period-over-period comparison | Repos, metrics, periods |
| `:GithubStats compact` | Archive old data, prune stale snapshots | `dry-run` |
| `:GithubStats digest` | Rebuild the digest other programs read | None |
| `:GithubStats debug` | Diagnostic information | None |
| `:GithubStats[!] dashboard` | Open the interactive traffic dashboard | None |

---

## GithubStats setup

Opens the setup guide: where the history lives (remote, local, later), and in
remote mode the GitHub CLI check, the data repository (cloned or created
private, optionally with this machine's history), the workflow's secret and a
first run. Each step checks whether it is done, so running it again resumes.
Opens by itself once on the first start. See
[Where the history lives](FEATURES/REMOTE.md).

## GithubStats sync

Remote mode only: commits and pushes a changed `config.json` (rebased onto the
workflow's commits), then pulls the data repository fast-forward. The editor
does the same quietly on start and every `storage.pull_interval_minutes`.

---

## GithubStats fetch

In remote mode this starts the data repository's workflow (`gh workflow run`)
and pulls its result about two and a half minutes later; this machine itself
never fetches then. Everything below is the local mode.

### Usage:
```vim
:GithubStats fetch [force]
```

### Description:

Triggers a manual fetch of GitHub traffic statistics for all configured repositories. By default, respects the configured fetch interval (`fetch_interval_hours`): when it has not elapsed yet, a dialog says how long ago the last fetch was and asks whether to fetch anyway ("Not now" is the default answer). `force` fetches at once without asking.

### Arguments:
- `force` (optional) – Forces immediate fetch regardless of last fetch time

### Autocompletion:
- `force` keyword

### Behavior:
- Fetches data asynchronously (non-blocking)
- Updates internal caches for all commands
- Shows notification on completion (respects `notification_level`)
- Stores last fetch timestamp to track interval

### Examples:
```vim
" Respects 24-hour interval (default)
:GithubStats fetch

" Force immediate fetch
:GithubStats fetch force
```

### Output:
```
[github-stats] Starting fetch: 5 repos, force=false
[github-stats] Successfully fetched 20 metrics
```

Or with errors:
```
[github-stats] Fetched 18 metrics, 2 errors
```

Check `:GithubStats debug` for error details.

### Related:
- See [Configuration Guide](configurations/INTRO.md) for `fetch_interval_hours`
- See [Troubleshooting](troubleshooting.md#understanding-error-messages) for error resolution

---

## GithubStats show

### Usage:
```vim
:GithubStats show {repo} {metric} [start_date] [end_date]
```

### Description:

Displays detailed statistics for a single repository and metric, including total counts, uniques, and daily breakdown in a floating window.

### Arguments:
- `{repo}` – Repository identifier (`owner/repo`), must be configured
- `{metric}` – Either `clones` or `views`
- `[start_date]` (optional) – Start date in ISO format (`YYYY-MM-DD`)
- `[end_date]` (optional) – End date in ISO format (`YYYY-MM-DD`)

### Autocompletion:
- Repository names from configuration
- Metric types: `clones`, `views`
- Date preset names at both date slots — but see the warning below

> **`show` does not resolve date presets.** Completion offers them, but
> `show.lua` hands the argument straight to `analytics.query_metric` as
> `start_date`, and `parse_date` there accepts `YYYY-MM-DD` only. A preset
> name fails to parse and becomes *no filter at all*, so the command
> silently reports the full stored history. Use ISO dates here, or
> `:GithubStats chart` / the dashboard's `T` prompt for presets — see
> [Where presets actually resolve](configurations/USER-DEFINED-DATE-PRESETS.md#where-presets-actually-resolve).

### Smart Defaults:
- No `start_date` → Shows all available data
- No `end_date` → Defaults to today's date

### Examples:
```vim
" All available data (no date filters)
:GithubStats show username/repo clones

" Only start date (end defaults to today)
:GithubStats show username/repo views 2025-01-01

" Complete date range
:GithubStats show username/repo clones 2025-01-01 2025-12-31

" Using autocomplete
:GithubStats show <Tab>           " Lists repositories
:GithubStats show username/repo <Tab>  " Suggests: clones, views
```

### Output Example:
```
Repository: username/repo
Metric: clones
Period: 2025-11-20 to 2025-12-20

Total Count: 1,234
Total Uniques: 567

Daily Breakdown:
----------------
  2025-11-20:    45 count,    12 uniques
  2025-11-21:    52 count,    15 uniques
  2025-11-22:    38 count,    10 uniques
  ...
  2025-12-20:    67 count,    23 uniques
```

### Notifications:
```
[github-stats] No start_date specified, showing data from 2025-11-20 onwards
```

### Error Messages:
```
[github-stats] Invalid metric 'clone'. Use 'clones' or 'views'
[github-stats] No data found for username/repo. Check repository name and ensure data has been fetched.
```

### Related:
- `:GithubStats chart` for visual representation
- `:GithubStats export` to save data
- `:GithubStats diff` for period comparison

---

## GithubStats summary

### Usage:
```vim
:GithubStats summary {metric}
```

### Description:

Shows aggregated statistics across all configured repositories for the specified metric. Each repository is listed with its time period, total count, and total uniques.

### Arguments:
- `{metric}` – Either `clones` or `views`

### Autocompletion:
- Metric types: `clones`, `views`

### Behavior:
- Queries all repositories in configuration
- Shows complete available time range per repository
- Displays errors for failed repositories (if any)
- Results shown in floating window

### Examples:
```vim
:GithubStats summary clones
:GithubStats summary views

" Using autocomplete
:GithubStats summary <Tab>  " Suggests: clones, views
```

### Output Example:
```
Summary: clones across all repositories
============================================================

Repository: username/repo1
  Period: 2025-11-01 to 2025-12-20
  Total Count: 1,234
  Total Uniques: 567

Repository: username/repo2
  Period: 2025-11-15 to 2025-12-20
  Total Count: 890
  Total Uniques: 234

Repository: organization/repo3
  Period: 2025-10-01 to 2025-12-20
  Total Count: 2,345
  Total Uniques: 789
```

### Notes:
- This command does not accept date parameters
- Shows entire available history for each repository
- Useful for quick overview of all projects

### Related:
- `:GithubStats show` for detailed single-repository view
- `:GithubStats export all` for exporting summary

---

## GithubStats referrers

### Usage:
```vim
:GithubStats referrers {repo} [limit]
```

### Description:

Displays the top referring domains or sources for a repository, sorted by traffic count. Shows referrer name, total count, and unique visitors.

### Arguments:
- `{repo}` – Repository identifier (`owner/repo`)
- `[limit]` (optional) – Maximum number of results (default: 10)

### Autocompletion:
- Repository names from configuration

### Examples:
```vim
" Top 10 referrers (default)
:GithubStats referrers username/repo

" Top 20 referrers
:GithubStats referrers username/repo 20

" Using autocomplete
:GithubStats referrers <Tab>  " Lists repositories
```

### Output Example:
```
Top Referrers: username/repo
============================================================

 1. github.com
    Count: 1,234, Uniques: 567
 2. google.com
    Count: 890, Uniques: 234
 3. reddit.com
    Count: 456, Uniques: 123
 4. twitter.com
    Count: 234, Uniques: 89
 5. news.ycombinator.com
    Count: 123, Uniques: 45
```

### Notes:
- Data shows latest available snapshot from GitHub
- Referrers are tracked by GitHub for 14 days
- Empty results mean no referrer data available yet

### Use Cases:
- Identify traffic sources
- Evaluate marketing effectiveness
- Discover unexpected popularity sources

### Related:
- `:GithubStats paths` for most visited repository paths

---

## GithubStats paths

### Usage:
```vim
:GithubStats paths {repo} [limit]
```

### Description:

Displays the most visited paths within a repository, showing which files, directories, or pages receive the most traffic.

### Arguments:
- `{repo}` – Repository identifier (`owner/repo`)
- `[limit]` (optional) – Maximum number of results (default: 10)

### Autocompletion:
- Repository names from configuration

### Examples:
```vim
" Top 10 paths (default)
:GithubStats paths username/repo

" Top 20 paths
:GithubStats paths username/repo 20

" Using autocomplete
:GithubStats paths <Tab>  " Lists repositories
```

### Output Example:
```
Top Paths: username/repo
============================================================

 1. /README.md
    Title: Repository README
    Count: 2,345, Uniques: 890
 2. /docs/installation.md
    Title: Installation Guide
    Count: 1,234, Uniques: 456
 3. /src/main.lua
    Title: Main module
    Count: 890, Uniques: 234
 4. /LICENSE
    Title: MIT License
    Count: 567, Uniques: 123
 5. /CHANGELOG.md
    Title: Changelog
    Count: 345, Uniques: 89
```

### Notes:
- Data shows latest available snapshot from GitHub
- Paths are tracked by GitHub for 14 days
- Useful for understanding what content is most popular

### Use Cases:
- Identify popular documentation pages
- Understand user navigation patterns
- Prioritize content improvements

### Related:
- `:GithubStats referrers` for traffic source analysis

---

## GithubStats chart

### Usage:
```vim
:GithubStats chart {repo} {metric} [start_date|time_range] [end_date]
```

### Description:

Renders GitHub traffic data as ASCII sparklines or comparison charts. Provides visual trend analysis rather than raw numbers.

### Arguments:
- `{repo}` – Repository identifier (`owner/repo`)
- `{metric}` – `clones`, `views`, or `both` (comparison)
- `[start_date|time_range]` (optional) – Either a start date (`YYYY-MM-DD`) **or** a relative time range
- `[end_date]` (optional) – End date (`YYYY-MM-DD`); ignored when the third argument was a time range

**The third argument does double duty.** An argument that looks like `Nd`
(`7d`, `30d`) or contains `last` (`last_month`, `last_quarter`) is treated
as a *time range* and passed straight through as such; anything else is
treated as a start date. So `:GithubStats chart user/repo clones 30d` is the
last 30 days, while `:GithubStats chart user/repo clones 2025-11-01` is
everything from that date on.

That rule is also what decides whether a **date preset** works here: only
names matching it reach `analytics.parse_time_range`, which is the only
place presets are resolved. `last_quarter` works; `this_quarter` is treated
as a start date, fails to parse, and silently filters nothing. See
[Where presets actually resolve](configurations/USER-DEFINED-DATE-PRESETS.md#where-presets-actually-resolve).

### Autocompletion:
- Repository names
- Metric types: `clones`, `views`, `both`
- Date presets at both date slots

### Smart Defaults:
- No third argument → All available data
- Third argument is a date, no `[end_date]` → Today's date

### Examples:
```vim
" Single metric sparkline (all data)
:GithubStats chart username/repo clones

" Comparison chart
:GithubStats chart username/repo both

" With date range
:GithubStats chart username/repo views 2025-01-01 2025-12-31

" Only start date
:GithubStats chart username/repo clones 2025-11-01

" Relative time range instead of a start date
:GithubStats chart username/repo clones 30d

" Using autocomplete
:GithubStats chart <Tab>               " Lists repositories
:GithubStats chart username/repo <Tab> " Suggests: clones, views, both
```

### Output Example (Single Metric):
```
GitHub Stats: username/repo/clones
────────────────────────────────────────────────────────────────

▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁

Period: 2025-11-20 to 2025-12-20 (30 days)
Max: 1,234 | Avg: 567 | Min: 123 | Total: 17,010

Recent Values:
  2025-12-18: 789
  2025-12-19: 823
  2025-12-20: 901
```

### Output Example (Comparison):
```
GitHub Stats: username/repo/clones
════════════════════════════════════════════════════════════════

Count (Total):    ▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁
                  Max: 1,234 | Avg: 567 | Total: 17,010

Uniques:          ▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁▂▃▄▅▆▅▄▃▂▁
                  Max: 456 | Avg: 234 | Total: 7,020

Period: 2025-11-20 to 2025-12-20 (30 days)
```

### Sparkline Characters:
- `▁▂▃▄▅▆▇█` – Unicode block elements (8 levels)
- Normalized to data range (min → `▁`, max → `█`)

### Navigation:
- `q` or `<Esc>` – Close window
- Arrow keys – Scroll (if content exceeds window size)

### Related:
- `:GithubStats show` for numerical breakdown
- `:GithubStats export` to save data

---

## GithubStats export

### Usage:
```vim
:GithubStats export {repo|all} {metric} {filepath}
```

### Description:

Exports GitHub traffic statistics to a file. Supported formats are CSV (single repository only), Markdown (single repository or all repositories), and PDF (single repository or all repositories, via [pdfport.nvim](https://github.com/WKDSteve/pdfport.nvim), optional dependency).

### Arguments:
- `{repo|all}` – Repository identifier or `all` for multi-repository export
- `{metric}` – `clones`, `views`, or `both` (combined clones+views report)
- `{filepath}` – Output file path (extension determines format: `.csv`, `.md`, or `.pdf`)

### Autocompletion:
- Repository names (including `all` option)
- Metric types: `clones`, `views`, `both`
- File paths (uses Neovim's built-in file completion)

### Supported Formats:

| Format | Extension | Single Repo | All Repos |
|--------|-----------|-------------|-----------|
| CSV | `.csv` | Yes | No |
| Markdown | `.md` | Yes | Yes |
| PDF | `.pdf` | Yes | Yes |

### PDF export (optional dependency):

Routes through [pdfport.nvim](https://github.com/WKDSteve/pdfport.nvim) — soft dependency, `pcall`-guarded. The exact same report the Markdown export would write to a `.md` file is instead handed to `pdfport.create()` as text (no intermediate `.md` file). Requires pdfport.nvim installed with an available Markdown producer (`pandoc` + a PDF engine — `pdfport.can_create("markdown")`); without it the export fails with a clear error rather than silently falling back to another format.

### Extension Defaulting:

If `{filepath}` has no extension at all, one is appended automatically —
`.md` for the `all` target (the only format it supports), `.csv`
otherwise. A path that already has a *different* extension (e.g. `.txt`)
is left alone and still errors, since silently rewriting a deliberately-named
path would be more surprising than helpful.

### Parent Directories:

Created automatically if they don't exist yet (previously this failed with a
raw `E482: Can't open file ... for writing: no such file or directory`).

### Examples:
```vim
" Export single repository to CSV
:GithubStats export username/repo clones ~/data.csv

" Export single repository to Markdown
:GithubStats export username/repo views ~/reports/repo_views.md

" Export single repository to PDF (requires pdfport.nvim)
:GithubStats export username/repo views ~/reports/repo_views.pdf

" Export all repositories to Markdown summary
:GithubStats export all clones ~/reports/all_clones.md

" Export all repositories to a PDF summary (requires pdfport.nvim)
:GithubStats export all clones ~/reports/all_clones.pdf

" No extension given -> defaults to ~/reports/repo.csv
:GithubStats export username/repo clones ~/reports/repo

" Combined clones+views, single repo (CSV, Markdown, or PDF)
:GithubStats export username/repo both ~/reports/combined.csv

" Combined clones+views summary across all repos (Markdown or PDF)
:GithubStats export all both ~/reports/combined_summary.md

" Using autocomplete
:GithubStats export <Tab>               " Suggests: repo names + "all"
:GithubStats export username/repo <Tab> " Suggests: clones, views, both
:GithubStats export username/repo clones <Tab>  " File path completion
```

### CSV Format Example:
```csv
repository,metric,date,count,uniques
username/repo,clones,2025-12-20,45,12
username/repo,clones,2025-12-21,52,15
username/repo,clones,2025-12-22,38,10
```

### Combined CSV Format Example (`both`):
```csv
repository,date,clones_count,clones_uniques,views_count,views_uniques
username/repo,2025-12-20,45,12,8,3
username/repo,2025-12-21,52,15,11,5
```

### Markdown Format Example:
```markdown
# GitHub Stats Report: username/repo

**Metric:** clones
**Period:** 2025-11-20 to 2025-12-20
**Generated:** 2025-12-22 10:30:00

## Summary

- **Total Count:** 1,234
- **Total Uniques:** 567

## Daily Breakdown

| Date | Count | Uniques |
|------|-------|---------|
| 2025-11-20 | 45 | 12 |
| 2025-11-21 | 52 | 15 |
| 2025-11-22 | 38 | 10 |
...
```

### Markdown Summary Format (all repos):
```markdown
# GitHub Stats Summary: clones

**Generated:** 2025-12-22 10:30:00
**Repositories:** 5

## Highlights

- **Most cloned repository:** username/repo1 (12,340 clones)
- **Best month for clones:** 2025-11 (4,102 clones)
- **Best single day for clones:** username/repo1 on 2025-11-28 (890 clones)

## Repositories

| Repository | Period | Total Count | Total Uniques |
|------------|--------|-------------|---------------|
| username/repo1 | 2025-11-01 to 2025-12-20 | 1,234 | 567 |
| username/repo2 | 2025-11-15 to 2025-12-20 | 890 | 234 |
...

## Detailed Reports

### username/repo1
...
```

Every summary export (single-repo or `all`, either metric) includes a
**Highlights** section: the most cloned/viewed repository, the best calendar
month, and the best single day. `all` + `both` produces one combined summary
with both clones and views highlights, instead of two separate reports.

### Notes:
- Files are overwritten if they exist
- Tilde (`~`) expansion is supported
- Parent directories are created automatically if missing

### Error Messages:
```
[github-stats] 'all' target only supports Markdown/PDF format
[github-stats] Export failed: Permission denied
[github-stats] File must have .csv, .md or .pdf extension
```

### Related:
- `:GithubStats show` to view data before exporting
- See [Export to CSV, Markdown, and PDF](FEATURES/EXPORT.md) for more details

---

## GithubStats diff

### Usage:
```vim
:GithubStats diff {repo} {metric} {period1} {period2}
```

### Description:

Compares traffic metrics between two time periods, showing absolute values and percentage changes. Useful for month-over-month or year-over-year analysis.

### Arguments:
- `{repo}` – Repository identifier (`owner/repo`)
- `{metric}` – Either `clones` or `views`
- `{period1}` – First period (`YYYY-MM` or `YYYY`)
- `{period2}` – Second period (`YYYY-MM` or `YYYY`)

### Period Formats:
- `YYYY-MM` – Single month (e.g., `2025-01` = January 2025)
- `YYYY` – Full year (e.g., `2025` = Jan 1 - Dec 31, 2025)

### Autocompletion:
- Repository names
- Metric types: `clones`, `views`
- Period suggestions (current month, last month, current year, last year)

> Completion at the period slots offers only `YYYY-MM` and `YYYY` values.
> `diff` does not accept **date preset names**: `parse_period` takes
> `YYYY-MM` and `YYYY` only, and anything else fails with `Invalid
> period1/2`. Presets work at the date slots of `show` and `chart`, and at
> the dashboard's `T` prompt.

### Examples:
```vim
" Compare two months
:GithubStats diff username/repo clones 2025-01 2025-02

" Compare two years
:GithubStats diff username/repo views 2024 2025

" Compare Q4 2024 vs Q1 2025
:GithubStats diff username/repo clones 2024-10 2025-01

" Using autocomplete
:GithubStats diff <Tab>               " Lists repositories
:GithubStats diff username/repo <Tab> " Suggests: clones, views
:GithubStats diff username/repo clones <Tab>  " Suggests periods
```

### Output Example:
```
Period Comparison: username/repo - clones
══════════════════════════════════════════════════════════════════

Period 1: 2025-01
  Total Count:   1,234
  Total Uniques: 567
  Days:          31
  Avg/Day:       39 count, 18 uniques

Period 2: 2025-02
  Total Count:   1,423
  Total Uniques: 645
  Days:          28
  Avg/Day:       50 count, 23 uniques

Changes:
──────────────────────────────────────────────────────────────────
  Count:   +15.3%
  Uniques: +13.8%
```

### Metrics Explained:
- **Total Count** – Sum of all traffic in period
- **Total Uniques** – Sum of unique visitors in period
- **Days** – Number of days with data in period
- **Avg/Day** – Average per day (Total / Days)
- **Changes** – Percentage change from Period 1 to Period 2

### Change Indicators:
- Positive change: `+X%` (growth)
- Negative change: `-X%` (decline)
- No change: `±0.0%`
- Infinite change: `+∞` (Period 1 had zero traffic)

### Notes:
- Both periods must have data available
- Comparison is fair even if periods have different lengths (uses Avg/Day)
- Useful for identifying trends and seasonal patterns

### Error Messages:
```
[github-stats] Invalid period1: 2025-13 (must be YYYY-MM or YYYY)
[github-stats] No data available for period: 2025-01
```

### Related:
- `:GithubStats show` to check available date ranges
- `:GithubStats chart` for visual trend analysis

---

## GithubStats compact

### Usage:
```vim
:GithubStats compact [dry-run]
```

### Description:

Bounds on-disk storage growth. For `clones`/`views`, once a calendar day
falls outside the retention window (`opts.retention.cutoff_days`, default
`15`, minimum enforced `14` to match GitHub's own rolling 14-day traffic
window), its deduplicated `{count, uniques}` is folded into a per-repo/metric
`_archive.json` file and the now-redundant raw fetch files are deleted. For
`referrers`/`paths` (where only the latest snapshot is ever read), files
older than `opts.retention.prune_days` (default `15`) are deleted outright,
always keeping the newest. Runs automatically at most once per 24h after a
fetch (`opts.retention.enabled`, default `true`); this command runs it
on demand.

### Arguments:
- `dry-run` (optional) – Reports would-be archived/deleted counts and freed bytes without touching disk

### Autocompletion:
- `dry-run` keyword

### Examples:
```vim
" Preview what would be archived/pruned
:GithubStats compact dry-run

" Run archiving/pruning now
:GithubStats compact
```

### Related:
- See [Configuration Guide](configurations/INTRO.md) for `opts.retention`
- See [Data retention](FEATURES/RETENTION.md) for the full retention model

---

## GithubStats digest

### Usage:
```vim
:GithubStats digest
```

### Description:

Rebuilds, right now, the per-repository digest that other programs read
(a desktop app, another Neovim plugin) from the stored history. The digest is
written automatically after every fetch and whenever the history is newer
than it; this command is for the case those miss — chiefly a sync from your
other machine, whose history the local digest has not caught up with yet.
Digests whose content did not change are left untouched.

Reports how many digests were written, left unchanged, or skipped for lack
of history, and the directory they went to.

### Arguments:
None.

### Examples:
```vim
:GithubStats digest
```

### Related:
- See [Digest](FEATURES/DIGEST.md) for the file contract, where it lives and how a reader finds it
- `opts.digest_dir` and `opts.digest_daily_days` in the [Configuration Guide](configurations/INTRO.md)

---

## GithubStats debug

### Usage:
```vim
:GithubStats debug
```

### Description:

Displays comprehensive diagnostic information to help troubleshoot configuration and API issues. Shows current configuration, token status, last fetch results, and performs a test API call.

### Arguments:
None

### Output Sections:

1. **Configuration Status**
   - Number of tracked repositories (explicit + auto-discovered breakdown)
   - Token source (environment variable or file)
   - Notification level
   - Background fetch status (enabled/disabled)
   - Watched users (if `watch_users` is configured)

2. **Token Status**
   - Presence/absence of token
   - Token length (for verification)
   - Source location

3. **Last Fetch Summary** (if available)
   - Timestamp of last fetch
   - Number of successful metrics
   - Number of errors
   - Detailed error messages per repository/metric

4. **API Connectivity Test**
   - Tests first configured repository
   - Shows success/error message
   - Sample data on success

### Examples:
```vim
:GithubStats debug
```

### Output Example:
```
GitHub Stats Debug Info
============================================================

Repositories: 8 tracked (5 explicit, 3 discovered)
Token source: env
Notification level: all
Background fetch: enabled
Watched users: username
Token: Present (40 chars)

Last Fetch Summary:
────────────────────────────────────────────────────────────
Timestamp: 2025-12-22T09:05:52
Successful: 18 metrics
Errors: 2

Error Details:
  • username/old-repo/clones: API Error: 404 Not Found
  • username/old-repo/views: API Error: 404 Not Found

Testing first repository...
Repo: username/active-repo
Success! Sample data:
{
  count = 1234,
  uniques = 567,
  clones = { ... }
}
```

### When to Use:

- After initial setup to verify configuration
- When commands return unexpected errors
- When troubleshooting "N errors" messages from fetch
- Before opening support issues

### Common Issues Revealed:

1. **"Token: ERROR - GITHUB_TOKEN not set"**
   - Token not configured
   - See [Configuration](configurations/PREPARATION.md#setting-up-token-access)

2. **"API Error: 401 Unauthorized"**
   - Invalid or expired token
   - Regenerate token with `repo` permission

3. **"API Error: 404 Not Found"**
   - Repository name incorrect in configuration
   - Repository was deleted or renamed

4. **"API Error: 403 Forbidden"**
   - Token lacks `repo` permission
   - Rate limit exceeded (see [Rate Limit Check](configurations/PREPARATION.md#test-4-rate-limit-check))

### Related:
- `:checkhealth github_stats` for comprehensive health check
- `:messages` to view all Neovim messages
- [Troubleshooting Guide](troubleshooting.md)

---

## GithubStats dashboard

### Usage:
```vim
:GithubStats dashboard
:GithubStats! dashboard
```

### Description:

Opens the interactive full-buffer traffic dashboard, listing every
configured repository with per-repo clones, views, and a trend indicator.
The bang (`:GithubStats! dashboard`) forces a refresh from the GitHub API
before opening instead of rendering from cache — it attaches to the verb,
not the `dashboard` subcommand, since composer only supports one bang slot
per command.

Full keybindings, sorting/time-range controls, and configuration are covered
separately.

### Related:
- [Dashboard Guide](dashboard.md) — keybindings, sorting, time ranges, configuration
- [Bindings Reference](BINDINGS.md#dashboard-keymaps) — dashboard keymap table

---

## Common Patterns

### Quick Daily Check
```vim
" Open Neovim, check all repos
:GithubStats summary clones

" Check specific repo details
:GithubStats show username/my-main-repo clones
```

### Weekly Report Generation
```vim
" Export all repos to Markdown
:GithubStats export all clones ~/reports/weekly_$(date +%Y%m%d).md

" Compare this week vs last week
:GithubStats diff username/repo clones $(date -d "1 week ago" +%Y-%m) $(date +%Y-%m)
```

### Troubleshooting Workflow
```vim
" 1. Check health
:checkhealth github_stats

" 2. View detailed diagnostics
:GithubStats debug

" 3. Check Neovim messages
:messages

" 4. Force fetch to refresh data
:GithubStats fetch force

" 5. Verify data exists
:GithubStats show username/repo clones
```

### Monitoring Traffic Spikes
```vim
" 1. Check recent trend
:GithubStats chart username/repo both

" 2. Show recent data
:GithubStats show username/repo clones 2025-12-01

" 3. Check traffic sources
:GithubStats referrers username/repo 20

" 4. Identify popular content
:GithubStats paths username/repo 20
```

### Comparing Performance
```vim
" Month-over-month
:GithubStats diff username/repo clones 2025-01 2025-02

" Year-over-year
:GithubStats diff username/repo views 2024 2025

" Visual comparison
:GithubStats chart username/repo both
```

---

#### For more information:
- [README](../README.md) – Plugin overview
- [Configuration Guide](configurations/INTRO.md) – Setup instructions
- [Troubleshooting](troubleshooting.md) – Common issues and solutions
- `:help github_stats` – Vim help file

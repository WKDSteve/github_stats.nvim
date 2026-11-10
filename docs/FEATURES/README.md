# Features

GitHub Stats collects GitHub traffic data (clones, views, referrers, paths)
for a set of repositories, stores it locally as JSON, and exposes it through
commands, an interactive dashboard, charts, exports, and diagnostics.

Every page here is a dev-facing catalog entry: what the feature is, which
module implements it, which commands and configuration keys reach it, and
why it works the way it does. For *how to use* a feature, follow the links
into [the documentation index](../README.md).

| Page | What it covers |
| --- | --- |
| [DASHBOARD.md](DASHBOARD.md) | The interactive full-buffer dashboard: rendering, sorting, time ranges, trend, sparklines, the read memo, highlighting, refresh actions, and the context menu |
| [COMMANDS.md](COMMANDS.md) | The single `:GithubStats <subcommand>` verb and its completion model |
| [FETCHING.md](FETCHING.md) | Fetching traffic data, the silent background cycle, and repository auto-discovery via `watch_users` |
| [../cli.md](../cli.md) | The headless entry `scripts/github_stats.lua` (`collect`, `report`; module `cli.lua`): one background cycle run to its end, exit codes 0/1/2/3 |
| [DIGEST.md](DIGEST.md) | The per-repository traffic digest other programs read: the file contract, where it lives, discovery, and when it is written |
| [RETENTION.md](RETENTION.md) | Archiving old clones/views and pruning stale referrers/paths snapshots |
| [ANALYTICS.md](ANALYTICS.md) | The query engine, the report views built on it, ASCII charts, and period-over-period diffs |
| [EXPORT.md](EXPORT.md) | CSV, Markdown, and PDF export, including the extension-defaulting rules |
| [DATE_PRESETS.md](DATE_PRESETS.md) | Named date ranges, built-in and user-defined |
| [CONFIGURATION.md](CONFIGURATION.md) | `setup()` versus `config.json`, and the precedence between them |
| [DIAGNOSTICS.md](DIAGNOSTICS.md) | `:checkhealth github_stats` and `:GithubStats debug` |

## What is deliberately not here

Several items exist only as design notes and are **planned, not
implemented**: notification thresholds, comparison baselines, interactive
chart navigation, repository groups/tags, export templates, autocomplete
date suggestions, fetch progress indicators for many-repo runs, and webhook
integration. There is no `thresholds.lua`, no `:GithubStats baseline` route,
no `groups.lua`, and no webhook module anywhere under `lua/`. They are left
out of this catalog on purpose: a feature page for something that does not
exist is the most expensive kind of documentation bug.

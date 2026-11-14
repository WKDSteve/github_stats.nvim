# Collecting without the editor

GitHub keeps clones and views for 14 days. The plugin collects them in the background while Neovim runs, so a
fortnight without opening the editor leaves a gap that can never be filled again. `scripts/github_stats.lua` runs the
same collection from a scheduler (Task Scheduler, cron, a CI job) without a running editor.

```sh
nvim --headless -u NONE -l scripts/github_stats.lua collect            # once a day is enough
nvim --headless -u NONE -l scripts/github_stats.lua report             # what the history holds
nvim --headless -u NONE -l scripts/github_stats.lua report --format=json
```

Run it from the plugin's folder (or give the script's full path). It needs `curl`, the GitHub token (the same source
as in the editor: `token_source`, by default `$GITHUB_TOKEN`) and `lib.nvim`, which it finds through `$LIB_NVIM_DIR`,
`$LIB_NVIM_PATH`, `$REPOS_DIR/lib.nvim`, `.deps/lib.nvim`, a checkout next to the plugin, or lazy.nvim's data folder.

## Commands

| Command | What it does |
| --- | --- |
| `collect` | One background cycle, run to its end: rebuilds the digests that lag the (synced) history, discovers the repositories of `watch_users`, fetches every tracked repository (only when `fetch_interval_hours` has elapsed, unless `--force`; a repository without any data is fetched at once), runs retention and writes the [digests](FEATURES/DIGEST.md). |
| `report` | Prints the traffic the history holds, per repository: views and clones of the last 7 and 30 complete days and the 7-day trend, computed exactly as the digest computes them. Never fetches. With `--format=json`: `{ schema, repos: [<digest>...], skipped, errors }`, each entry the [digest](FEATURES/DIGEST.md#digestowner_repojson) of one repository. |
| `help` | The usage. |

## Options

The workflow of a data repository ([remote mode](FEATURES/REMOTE.md)) runs
`collect --force --token-env=GH_STATS_TOKEN --config-dir=<the repository>`; in remote
mode the daily task below is not needed, the workflow is that task.

| Option | Meaning |
| --- | --- |
| `--repos=<owner/name,...>` | These repositories instead of the configured ones; `watch_users` is not asked. |
| `--config-dir=<dir>` | The folder of `config.json` (default: the editor's, `stdpath("config")/lua/plugins/github-stats`). |
| `--data-dir=<dir>` | The history (default: `<config-dir>/data`). |
| `--digest-dir=<dir>` | `collect`: where the digests go (default: `stdpath("data")/github_stats.nvim`). |
| `--force` | `collect`: fetch even when `fetch_interval_hours` has not elapsed. |
| `--token-env=<NAME>` | Read the token from this environment variable, whatever `config.json` says (`token_source`, `token_env_var`). |
| `--timeout=<seconds>` | `collect`: give up after this long (default 600). |
| `--format=text\|json` | Default `text`. |
| `--quiet` | `collect`: no warnings on stderr. |

## What it reads

The configuration is the plugin's `config.json`, the file the editor reads too. Options given to `setup()` in the
editor's Lua config are **not** seen: a headless run loads no user config. Put what both should share (`repos`,
`watch_users`, `fetch_interval_hours`, `token_source`, ...) into `config.json`, or pass the folders and `--repos`.

The history is the same one the editor writes, and the fetch interval is shared through `last_fetch.json`: a
scheduled run and an open editor never fetch the same day twice.

`root.json`, the pointer other programs follow to the digests, is written as in the editor. With `--config-dir`,
`--data-dir` or `--digest-dir` it is **left alone**: a run on other folders (a trial, a second history) must not
repoint what the editor's readers see.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Done (also when the interval had not elapsed and nothing was fetched). |
| 1 | A metric could not be fetched, a repository of `watch_users` could not be listed, or a digest could not be written. Everything else was still collected. The details are on stderr (`--format=json`: in the result). |
| 2 | Usage or configuration: an unknown option, an unreadable `config.json`, no token. |
| 3 | The environment: no `curl`, no `lib.nvim`, or the run did not finish within `--timeout`. |

## A daily task on Windows

```powershell
schtasks /Create /SC DAILY /ST 09:00 /TN "github_stats collect" /TR "nvim --headless -u NONE -l C:\path\to\github_stats.nvim\scripts\github_stats.lua collect --quiet"
```

The task runs as your user, so `$GITHUB_TOKEN` must be a user environment variable (or use `token_source = "file"`).

# github_stats.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | Requirements, loading strategies, and a spec per plugin manager |
| [quickstart.md](quickstart.md) | The first thing to run after installing |
| [FEATURES/REMOTE.md](FEATURES/REMOTE.md) | Where the history lives: a private data repository GitHub Actions fills (default) or this machine's folder; the setup guide |
| [configurations/README.md](configurations/README.md) | The configuration guide as a whole: preparation, every option with its default, and the two ways to set them |
| [troubleshooting.md](troubleshooting.md) | Common failures, what to run to diagnose them, and the fixes |
| [cross-platform.md](cross-platform.md) | What differs on Windows, macOS and Linux |

## Using it

| Page | Answers |
| --- | --- |
| [what-you-get.md](what-you-get.md) | The commands worth knowing on day one, once the setup guide has run |
| [commands.md](commands.md) | The complete `:GithubStats <subcommand>` reference |
| [BINDINGS.md](BINDINGS.md) | Every command, keymap and autocommand in one place |
| [dashboard.md](dashboard.md) | The interactive dashboard: its keys, its layout, and what it can be configured to show |
| [configurations/USER-DEFINED-DATE-PRESETS.md](configurations/USER-DEFINED-DATE-PRESETS.md) | The built-in date ranges and how to define your own |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each command does, but how the pieces combine over a session — including the two intervals the background fetch runs on |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES/README.md](FEATURES/README.md) | The feature catalog: one page per area, each naming its modules, commands, config keys, and the decision behind it |
| [architecture.md](architecture.md) | The on-disk data layout and which GitHub API endpoints are used |
| [background-fetching.md](background-fetching.md) | How the silent fetch and discovery cycle works under the hood — the implementation counterpart to the configuration in [WORKFLOW.md](WORKFLOW.md) |
| [cli.md](cli.md) | Collecting and reporting without the editor (`scripts/github_stats.lua`), for a scheduler or CI |
| [performance.md](performance.md) | Storage footprint, fetch timings, and where the rate limits bite |

## Working on it

| Page | Answers |
| --- | --- |
| [CHANGELOG.md](CHANGELOG.md) | What changed, release by release |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Ground rules, project layout, and how to add a subcommand |

> `docs/map/` is not in this repository. `:DocMap` builds it from the current
> tree in seconds, which is why it is generated rather than shipped.

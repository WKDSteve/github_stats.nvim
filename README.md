> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# github_stats.nvim

```
   ____ _ _   _   _       _       ____  _        _
  / ___(_) |_| | | |_   _| |__   / ___|| |_ __ _| |_ ___
 | |  _| | __| |_| | | | | '_ \  \___ \| __/ _` | __/ __|
 | |_| | | |_|  _  | |_| | |_) |  ___) | || (_| | |_\__ \
  \____|_|\__|_| |_|\__,_|_.__/  |____/ \__\__,_|\__|___/
                                                   .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/WKDSteve/github_stats.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/WKDSteve/github_stats.nvim/actions/workflows/ci.yml)
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://wkdsteve.github.io/wkd/p/github_stats/)

> Part of the [wkd](https://wkdsteve.github.io/wkd/) family — see this plugin's [page](https://wkdsteve.github.io/wkd/p/github_stats/) on the site.

GitHub keeps clones, views, referrers and paths for **fourteen days** and then
throws them away. This plugin collects them in the background before that
happens, analyses the history it builds, and exports it — all from inside
Neovim.

---

## Around it

> **[reposcope.nvim](https://github.com/WKDSteve/reposcope.nvim)** — a
> repository browser and switcher. This plugin tells you which of your
> repositories people are actually looking at; reposcope is how you jump into one.
>
> **[insights.nvim](https://github.com/WKDSteve/insights.nvim)** — traffic is
> the outside view of a repository; insights is the inside one.
>
> **[ui.nvim](https://github.com/WKDSteve/ui.nvim)** — puts this week's
> view count for the current repository in the statusline, so the number is
> there without opening the dashboard.
>
> reposcope and insights above are soft: without them everything else works
> unchanged. ui.nvim is not — `require("github_stats")` itself pulls in
> `ui.kit`/`ui.contextmenu` (the dashboard's note popups and right-click
> menu) at module load, before `setup()` even runs. It is a real dependency
> alongside [lib.nvim](https://github.com/WKDSteve/lib.nvim) and `curl` —
> see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, the `lib.nvim` dependency, `curl`, and the GitHub token.
- [Installation](docs/installation.md) — loading strategies and every plugin manager.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the commands worth knowing on day one.
- [Configuration guide](docs/configurations/README.md) — token setup, every option with its default, and the two ways to set them.
- [Command reference](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)
- [Statusline](docs/statusline.md) — this week's view count as a component, for lualine, heirline, the native statusline or ui.nvim.
- [Dashboard guide](docs/dashboard.md) — the interactive dashboard, its keys, and what it can be configured to show.

### The Rest

- [Features](docs/FEATURES/README.md) — the catalog: one page per area, each naming its modules, commands and config keys.
- [Background fetching](docs/background-fetching.md) — when it fetches, and what it costs.
- [Workflow](docs/WORKFLOW.md) — how the pieces combine over a session, day to day.
- [Architecture](docs/architecture.md) — module layout and the storage format.
- [Digest](docs/FEATURES/DIGEST.md) — the small per-repository file that lets another program (a desktop app, another plugin) show this traffic without a token: where it is, what is in it, how to find it.
- [Health check](docs/FEATURES/DIAGNOSTICS.md) — what `:checkhealth github_stats` and `:GithubStats debug` report, and how they divide the diagnostic work.
- [Troubleshooting](docs/troubleshooting.md) — common failures, what to run to diagnose them, and the fixes.
- [Cross-platform notes](docs/cross-platform.md)
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a subcommand.
- [Feedback](https://github.com/WKDSteve/github_stats.nvim/issues)

`:help github_stats` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

github_stats.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).

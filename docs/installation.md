# Installation

## Requirements

- **Neovim** >= 0.11.0 — `vim.uv` is used unguarded in `background.lua`,
  `dashboard/init.lua`, `dashboard/state.lua` and `health.lua`
- **[lib.nvim](https://github.com/WKDSteve/lib.nvim)** — required, not optional: notifications, JSON I/O, the GitHub API client (and the curl client under it), the bounded fetch queue, the user-command composer and the cross-platform executable check all come from it.
  **Minimum: commit `ccd30b5` (2026-10-31) or newer.** Every API request goes through `lib.nvim.net.github`, which arrived in that commit; with an older lib.nvim the API module does not load at all. (`:GithubStats fetch` also needs `lib.nvim.async.map_limit` from `884fe61`, which the newer commit includes.) The API response cap (`api_max_response_bytes`) is handed to that client as `max_bytes`. `:checkhealth github_stats` reports an error when `lib.nvim.net.github` is missing and a warning when the client ignores the cap.
- **[ui.nvim](https://github.com/WKDSteve/ui.nvim)** — also required, not optional: `require("github_stats")` itself pulls in `ui.kit`/`ui.contextmenu` (the dashboard's note popups and right-click menu) at module load, before `setup()` even runs
- **curl** (for API requests)
- **GitHub Personal Access Token** with `repo` permission

Optional: [pdfport.nvim](https://github.com/WKDSteve/pdfport.nvim) for
`.pdf` export, and [nvzone/menu](https://github.com/nvzone/menu) for the
dashboard's right-click menu. Both degrade to a no-op when absent.

See [Preparation](configurations/PREPARATION.md) for a full walkthrough of creating a token, verifying `curl`, and testing token permissions.

## Choosing a Loading Strategy

| Variant | Startup impact | Commands available | When to use |
|---|---|---|---|
| **Default (lazy)** | Minimal | On first use of a `:GithubStats` subcommand | Large config, many plugins |
| **`lazy = false`** | Loads immediately | Right from the start | Want the daily auto-fetch guaranteed from the first frame |
| **`event = "VimEnter"`** | After UI init | After editor UI ready | **Recommended** — daily auto-fetch / dashboard auto-open timing, minimal startup impact |

`event = "VimEnter"` is the point of the plugin: the background collector has
to be running for there to be any history to analyse later. A `cmd` trigger
would mean it only ever collects on days you happened to open the dashboard.

## lazy.nvim

*Load after UI init (recommended, matches the plugin's own `VimEnter` auto-fetch):*
```lua
{
  "WKDSteve/github_stats.nvim",
  dependencies = { "WKDSteve/lib.nvim", "WKDSteve/ui.nvim" },
  event = "VimEnter",
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

*Load at startup (eager):*
```lua
{
  "WKDSteve/github_stats.nvim",
  dependencies = { "WKDSteve/lib.nvim", "WKDSteve/ui.nvim" },
  lazy = false,
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

## packer.nvim

```lua
use {
  "WKDSteve/github_stats.nvim",
  requires = { "WKDSteve/lib.nvim", "WKDSteve/ui.nvim" },
  config = function()
    require("github_stats").setup({
      repos = { "user/repo1", "user/repo2" },
    })
  end,
}
```

## Next Steps

- [Configuration guide](configurations/README.md) — the whole configuration story, in reading order.
- [Preparation](configurations/PREPARATION.md) — create and verify your GitHub token.
- [Configuration options](configurations/INTRO.md) — every key, its type, and its default.

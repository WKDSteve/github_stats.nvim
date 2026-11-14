---@module 'github_stats.@types'
---@brief Type definitions for GitHub Stats collector

---@class GHStats.DatePresetConfig
---@field enabled boolean Whether date presets are enabled
---@field builtins string[] List of enabled built-in preset names
---@field custom table<string, fun(): string, string> Custom user-defined presets

---@class GHStats.BackgroundConfig
---@field enabled boolean Master switch for the silent background fetch/discovery cycle. When false, only manual `:GithubStats fetch` (and dashboard refresh keys) ever fetch data.
---@field initial_delay_ms integer? Delay before the first cycle, in ms (default 1000). The recurring interval derives from `fetch_interval_hours`.

---@class GHStats.RetentionConfig
---@field enabled boolean Master switch for opportunistic post-fetch retention (github_stats.retention.maybe_run_all)
---@field cutoff_days integer clones/views: age (days) after which a day's deduplicated value is folded into the archive and its raw fetch files are deleted
---@field prune_days integer referrers/paths: age (days) after which a snapshot is deleted outright (the newest snapshot is always kept)

---@class GHStats.SetupOptions
---@field storage? "remote"|"local"|GHStats.StorageOptions Where the history lives: a data repository GitHub Actions fills (default, see `github_stats.remote`) or this machine's own folder ("local", the plugin's fetching as before)
---@field notify_fetch? boolean Notify at startup whether a fetch was performed or not
---@field repos? string[] List of individually tracked repositories ("owner/repo")
---@field watch_users? string[] GitHub usernames whose public repositories are auto-discovered and tracked in addition to `repos`
---@field background? GHStats.BackgroundConfig Background fetch/discovery configuration
---@field retention? GHStats.RetentionConfig Data retention configuration (archiving/pruning old metric files)
---@field token_source? "env"|"file" Token source
---@field token_env_var? string Environment variable name
---@field token_file? string Path to token file
---@field fetch_interval_hours? number Fetch interval
---@field max_parallel_fetches? integer Repositories a fetch keeps in flight at once, 4 curl processes each (default 4)
---@field api_timeout_ms? integer Timeout for GitHub API requests in ms (default 15000)
---@field api_max_response_bytes? integer Byte cap for GitHub API responses, enforced via curl --max-filesize (default 5 MiB)
---@field max_user_repo_pages? integer Pages followed when listing a watched user's repos, 100 per page (default 30). Past the cap, later repos are silently not tracked.
---@field notification_level? "all"|"errors"|"silent" Notification level
---@field progress_style? "auto"|"notify"|"statusline"|"fidget"|"float"|"kit" Indicator while a manual fetch is in flight; needs lib.nvim, no-op without it. Background cycles never show one.
---@field config_dir? string Custom config directory (default: stdpath('config')/lua/plugins/github-stats)
---@field data_dir? string Custom data directory (default: config_dir/data)
---@field digest_dir? string Where the per-repository digest for other programs is written (default: stdpath('data')/github_stats.nvim). Local to this machine on purpose; see docs/FEATURES/DIGEST.md.
---@field digest_daily_days? integer How many days of daily values a digest keeps (default 400)
---@field date_presets? GHStats.DatePresetConfig Date range preset configuration
---@field dashboard? GHStats.DashboardConfig Dashboard configuration

--- The resolved configuration: `GHStats.SetupOptions` after the merge over
--- `config/DEFAULTS.lua`, where the four fields the plugin cannot run without
--- are guaranteed. `DEFAULTS` and `config.get()` carry this; `setup()` takes
--- the optional-everything input type above.
---@class GHStats.Config : GHStats.SetupOptions
---@field notify_fetch  boolean
---@field repos         string[]
---@field token_source  "env"|"file"
---@field dashboard     GHStats.Dashboard.Resolved

return {}

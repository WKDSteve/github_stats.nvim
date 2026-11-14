# Configuration Guide

## Table of content

  - [Overview](#overview)
  - [Configuration Methods](#configuration-methods)
    - [Quick Comparison](#quick-comparison)
    - [Decision Guide](#decision-guide)
  - [Configuration Options](#configuration-options)
    - [Core Options](#core-options)
      - [`storage`](#storage)
      - [`repos`](#repos)
      - [`watch_users`](#watch_users)
      - [`background.enabled`](#backgroundenabled)
      - [`token_source`](#token_source)
      - [`token_env_var`](#token_env_var)
      - [`token_file`](#token_file)
      - [`fetch_interval_hours`](#fetch_interval_hours)
      - [`max_parallel_fetches`](#max_parallel_fetches)
      - [`max_user_repo_pages`](#max_user_repo_pages)
      - [`notification_level`](#notification_level)
      - [`notify_fetch`](#notify_fetch)
      - [`progress_style`](#progress_style)
    - [Advanced Options](#advanced-options)
      - [`config_dir`](#config_dir)
      - [`data_dir`](#data_dir)
      - [`retention`](#retention)
      - [`digest_dir`](#digest_dir)
      - [`digest_daily_days`](#digest_daily_days)
    - [Options With Their Own Page](#options-with-their-own-page)
  - [Token Management](#token-management)
    - [Creating a GitHub Token](#creating-a-github-token)
    - [Token Security Best Practices](#token-security-best-practices)
    - [Environment Variable Setup](#environment-variable-setup)
    - [Token File Setup](#token-file-setup)
  - [Storage Paths](#storage-paths)
    - [Default Storage Structure](#default-storage-structure)
    - [Custom Storage Paths](#custom-storage-paths)
    - [Storage Size Estimation](#storage-size-estimation)
  - [Why Two Configuration Methods?](#why-two-configuration-methods)
    - [Option A (Direct Setup) Advantages](#option-a-direct-setup-advantages)
    - [Option B (Config File) Advantages](#option-b-config-file-advantages)
    - [The Sync Use Case](#the-sync-use-case)
  - [Next Steps](#next-steps)

---

## Overview

GitHub Stats supports two flexible configuration methods to accommodate different workflows:

1. **[Option A: Direct Setup](OPTION-A.md)** – Configure via `setup()` in your Neovim init file
2. **[Option B: Config File](OPTION-B.md)** – Use external `config.json` for persistence

Both methods support the same configuration options and can be used interchangeably.

---

## Configuration Methods

### Quick Comparison

| Aspect | Option A (Direct Setup) | Option B (Config File) |
|--------|-------------------------|------------------------|
| **Location** | Neovim init file (`init.lua`) | `~/.config/nvim/lua/plugins/github-stats/config.json` |
| **Best For** | Quick setup, single system | Multi-system sync, backup |
| **Flexibility** | Lua functions, conditionals | Static JSON |
| **Version Control** | Part of Neovim config | Separate file (optional) |
| **Precedence** | Higher (overrides config.json) | Lower |

### Decision Guide

#### Use Option A (Direct Setup) if:
- You manage all configuration in Neovim init file
- You want to use Lua logic for dynamic configuration
- You prefer everything in one place

#### Use Option B (Config File) if:
- You sync Neovim config across multiple systems
- You want to version control repository lists separately
- You prefer JSON for portability

#### Use Both if:
- You want system-specific overrides (Option A) with a shared base (Option B)
- Priority: `setup()` > `config.json`

---

## Configuration Options

### Core Options

#### `storage`
**Type:** `"remote" | "local" | table`
**Default:** `"remote"` (until the setup guide has run, the plugin fetches locally)
**Where:** `setup()` only; it decides where `config.json` itself is read from

Where the history lives. **Remote**: a private data repository of yours, filled once a
day by a GitHub Actions workflow; every machine clones and pulls it and never fetches
itself. **Local**: this Neovim fetches into `config_dir`/`data_dir`, as before. The
table form takes `mode`, `repo` (`"owner/name"`), `dir` (the clone, default
`stdpath('data') .. '/github_stats.nvim-vault'`) and `pull_interval_minutes` (default
`60`). Setting `config_dir` or `data_dir` also means local.

##### Example:
```lua
storage = "local"                                  -- fetch here, no data repository
storage = { repo = "you/github-stats-vault" }      -- remote, repository known: no guide
```

In remote mode `config.json` is the one in the clone (the workflow reads it too), so
`repos`, `watch_users` and the other options it holds are shared by every machine and
the workflow; edit it there and run `:GithubStats sync`. Everything about the mode, the
setup guide and the workflow: [Where the history lives](../FEATURES/REMOTE.md).

#### `repos`
**Type:** `string[]`
**Default:** `{}` (nothing is tracked until you name repositories here or users in `watch_users`)
**Required:** Yes, unless `watch_users` is set
**Format:** `"owner/repository"`
**Example:** `["username/repo1", "organization/repo2"]`

List of individually tracked repositories. Repository names must match exactly as they appear on GitHub (case-sensitive). Works together with `watch_users` — both lists are merged.

#### `watch_users`
**Type:** `string[]`
**Default:** `{}`
**Example:** `["username"]`

GitHub usernames whose public repositories are auto-discovered and tracked in addition to `repos`. Re-resolved on every background cycle, so newly created repos show up automatically without editing config. Traffic stats still require push access to each repo, so entries you don't have access to simply never populate data.

```lua
require("github_stats").setup({
  watch_users = { "username" },  -- tracks every public repo of "username"
})
```

#### `background.enabled`
**Type:** `boolean`
**Default:** `true`

Master switch for the silent background fetch/discovery cycle (started on `VimEnter`, stays active for the whole session). When `false`, only manual `:GithubStats fetch` ever fetches data — see [Background fetching](../WORKFLOW.md#background-fetching-runs-the-whole-session--know-the-two-intervals) in the workflow guide for the full behavior.

#### `token_source`
**Type:** `"env" | "file"`
**Default:** `"env"`

Specifies where the GitHub token should be loaded from:
- `"env"` – Read from environment variable
- `"file"` – Read from file (specified by `token_file`)

##### Example:
```lua
token_source = "env"  -- Uses environment variable
```

#### `token_env_var`
**Type:** `string`
**Default:** `"GITHUB_TOKEN"`
**Used when:** `token_source = "env"`

Name of the environment variable containing the GitHub token.

##### Example:
```lua
token_env_var = "GH_TOKEN"  -- Custom variable name
```

#### `token_file`
**Type:** `string`
**Default:** `nil`
**Required when:** `token_source = "file"`

Path to file containing the GitHub token. Supports tilde expansion (`~`).

##### Example:
```lua
token_file = "~/.github_token"
```

**Security Note:** Ensure file has restricted permissions:
```bash
chmod 600 ~/.github_token
```

#### `fetch_interval_hours`
**Type:** `number`
**Default:** `24`
**Range:** `> 0`

Hours between automatic data fetches. Prevents excessive API usage.

##### Examples:
```lua
fetch_interval_hours = 24   -- Daily (default)
fetch_interval_hours = 12   -- Twice daily
fetch_interval_hours = 168  -- Weekly
```

**Note:** Manual fetches with `:GithubStats fetch force` bypass this interval.

**Related:** `background.initial_delay_ms` (default `1000`) is the delay
before the *first* cycle — it keeps the fetch out of startup. Raise it if
your startup is heavy enough that one second still lands inside it.

#### `max_parallel_fetches`
**Type:** `number`
**Default:** `4`
**Range:** `>= 1`

Repositories a fetch keeps in flight at once; each one starts four `curl`
processes, the rest wait in a queue. Process creation blocks Neovim briefly
(about 10-15 ms per spawn on Windows, far more when a virus scanner checks
each one), so the cap keeps a fetch over many repositories, such as one
populated by `watch_users`, from freezing the UI. Lower it on a machine with
slow process creation; values below 1 fall back to the default.

#### `max_user_repo_pages`
**Type:** `number`
**Default:** `30`

Pages followed when listing a watched user's repositories, 100 per page.
Past the cap, later repos are **silently not tracked** — raise it only for
an account with more than 3000 public repos.

#### `notification_level`
**Type:** `"all" | "errors" | "silent"`
**Default:** `"all"`

Controls notification verbosity:

| Level | Behavior | Use Case |
|-------|----------|----------|
| `"all"` | Show all notifications (info, warnings, errors) | Default, full feedback |
| `"errors"` | Only show warnings and errors | Reduce noise |
| `"silent"` | No notifications (check `:GithubStats debug` manually) | Minimal distraction |

##### Example:
```lua
notification_level = "errors"  -- Only show problems
```

#### `notify_fetch`
**Type:** `boolean`
**Default:** `true`

Whether a manual fetch through the Lua API (`fetcher.manual_fetch(false)`)
that is skipped because the interval has not elapsed says so ("Fetch interval
not elapsed (use 'force' to bypass)") or stays quiet. `:GithubStats fetch`
never gets there: it asks whether to fetch anyway. It only affects that one
message; it is not a second
notification gate next to `notification_level`.

#### `progress_style`
**Type:** `"auto" | "notify" | "statusline" | "fidget" | "float" | "kit"`
**Default:** `"auto"`

Indicator shown while a *manual* fetch is in flight — a full fetch is four
API calls per repository, so over a dozen repositories it can run for a
while with nothing on screen otherwise. Drawn by `lib.nvim.progress`.
Background cycles never show one, matching how they already suppress info
notifications.

`"auto"` prefers fidget.nvim when installed and falls back to
`vim.notify`. `"statusline"` draws nothing and instead publishes the text
for your own statusline to read via
`require("lib.nvim.progress.styles.statusline").active()`.

---

### Advanced Options

#### `config_dir`
**Type:** `string | nil`
**Default:** `stdpath('config') .. '/lua/plugins/github-stats'`
##### Platform-specific defaults:
- Linux/macOS: `~/.config/nvim/lua/plugins/github-stats`
- Windows: `%LOCALAPPDATA%\nvim\lua\plugins\github-stats`

Custom directory for configuration file (`config.json`) storage. Setting it means
local mode (see [`storage`](#storage)); in remote mode the clone of the data repository
is the config directory.

##### Example:
```lua
config_dir = "~/my-github-stats"
```

##### When to customize:
- Store configuration outside Neovim's config directory
- Use shared location across multiple editors
- Organize plugin data separately

#### `data_dir`
**Type:** `string | nil`
**Default:** `config_dir .. '/data'`

Custom directory for traffic data storage. If not specified, data is stored relative to `config_dir`. Setting it means local mode (see [`storage`](#storage)).

##### Example:
```lua
data_dir = "/mnt/shared/github-stats"  -- Network storage
```

##### Use cases:
- Store large datasets on separate partition
- Use network-attached storage (NAS)
- Share data across multiple systems
- Separate data from configuration

#### `retention`
**Type:** `table`
**Default:** `{ enabled = true, cutoff_days = 15, prune_days = 15 }`

Bounds on-disk growth. `cutoff_days` is the age at which a day's
clones/views value is folded into a per-metric `_archive.json` and its raw
fetch files are deleted; `prune_days` is the age at which a referrers/paths
snapshot is deleted outright (the newest is always kept). `enabled = false`
turns the opportunistic post-fetch run off, leaving only manual
`:GithubStats compact`.

```lua
retention = {
  enabled = true,
  cutoff_days = 15,  -- floor of 14 is enforced in code
  prune_days = 15,
}
```

**`cutoff_days` has a hard floor of 14** (`math.max(opts.cutoff_days or 15,
14)`), because GitHub's traffic API is itself a rolling 14-day window — a
day cannot be considered final until it has aged out of it. Configuring `5`
behaves like `14`; `:GithubStats compact dry-run` is the fast way to see
that before assuming otherwise.

#### `digest_dir`
**Type:** `string | nil`
**Default:** `stdpath("data") .. "/github_stats.nvim"`

Where the per-repository digest is written — the small JSON file another
program reads to show this traffic without a token (see
[Digest](../FEATURES/DIGEST.md)). It is **local to one machine on purpose**:
the raw history is synced with your Neovim config, the digest is derived and
rewritten in place, so it must not sit in a synced folder. Set it in
`setup()`, not in the synced `config.json`.

A small pointer file, `root.json`, is always written at the default place and
names wherever `digest_dir` really is, so a reader needs no setting either way.

```lua
digest_dir = "D:/local/github-stats-digest"
```

#### `digest_daily_days`
**Type:** `integer`
**Default:** `400`

How many days of daily values each digest keeps per metric. The 7/30/90-day
sums are unaffected. A digest with this many days is about 20 KB.

---

### Options With Their Own Page

Three more configuration sections exist and are documented where their
behavior is:

| Section | Page |
|---|---|
| `dashboard` (layout, keybindings, sort, time range, trend, auto-refresh, context menu) | [dashboard.md](../dashboard.md#configuration) |
| `date_presets` (built-ins and custom preset functions) | [USER-DEFINED-DATE-PRESETS.md](USER-DEFINED-DATE-PRESETS.md) |
| `background` (beyond `enabled`: `initial_delay_ms`) | [background-fetching.md](../background-fetching.md#mstart) |

---

## Token Management

### Creating a GitHub Token

1. Visit: https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select `repo` scope (full repository access required)
4. Set expiration date (or "No expiration" for long-term use)
5. Generate and **save token securely**

#### Required Permissions:
- `repo` (full control of private repositories)

This includes:
- `repo:status` – Access commit status
- `repo_deployment` – Access deployment status
- `public_repo` – Access public repositories
- `repo:invite` – Access repository invitations
- `security_events` – Read and write security events

### Token Security Best Practices

#### DO:
- Use environment variables when possible
- Restrict file permissions (`chmod 600`) for token files
- Use separate tokens for different projects
- Set expiration dates on tokens
- Rotate tokens periodically

#### DON'T:
- Commit tokens to version control
- Share tokens between users
- Use tokens with broader permissions than needed
- Store tokens in plain text in shared locations

### Environment Variable Setup

#### Linux/macOS (bash/zsh):
```bash
# In ~/.bashrc or ~/.zshrc
export GITHUB_TOKEN="ghp_your_token_here"

# Reload shell configuration
source ~/.bashrc
```

#### Windows (PowerShell):
```powershell
# Temporary (current session)
$env:GITHUB_TOKEN = "ghp_your_token_here"

# Permanent (user profile)
[Environment]::SetEnvironmentVariable(
    "GITHUB_TOKEN",
    "ghp_your_token_here",
    "User"
)
```

#### Verification:
```bash
# Linux/macOS
echo $GITHUB_TOKEN

# Windows (PowerShell)
echo $env:GITHUB_TOKEN
```

### Token File Setup

```bash
# Create token file
echo "ghp_your_token_here" > ~/.github_token

# Secure permissions (Linux/macOS)
chmod 600 ~/.github_token

# Verify
ls -la ~/.github_token
# Should show: -rw------- (readable/writable by owner only)
```

---

## Storage Paths

### Default Storage Structure

In remote mode (the default) this tree is the clone of your data repository,
`stdpath('data')/github_stats.nvim-vault/`, with the workflow in
`.github/workflows/collect.yml` next to it. In local mode it is `config_dir`:

```
~/.config/nvim/lua/plugins/github-stats/
├── config.json                    # Configuration (Option B)
├── last_fetch.json                # Fetch interval tracking
└── data/
    └── username_repo/             # Sanitized repo name
        ├── clones/
        │   ├── 2025-12-20T10-30-00.json
        │   └── 2025-12-21T10-30-00.json
        ├── views/
        ├── referrers/
        └── paths/
```

### Custom Storage Paths

#### Example 1: Separate Data Location
```lua
require("github_stats").setup({
  repos = { "user/repo" },
  data_dir = "~/Documents/github-stats-data",
})
```

Results in:
```
~/.config/nvim/lua/plugins/github-stats/
├── config.json               # Config stays here
└── last_fetch.json

~/Documents/github-stats-data/
└── username_repo/            # Data stored here
    ├── clones/
    ├── views/
    └── ...
```

#### Example 2: Completely Custom Paths
```lua
require("github_stats").setup({
  repos = { "user/repo" },
  config_dir = "~/my-config",
  data_dir = "/mnt/nas/github-stats",
})
```

Results in:
```
~/my-config/
├── config.json
└── last_fetch.json

/mnt/nas/github-stats/
└── username_repo/
    └── ...
```

### Storage Size Estimation

#### Per Repository:
- ~2KB per data point (daily)
- 4 metrics × 14 days = ~112KB per repository per 2 weeks
- With history: ~1.5MB per repository per year

#### Example Calculation:
- 10 repositories
- 1 year of daily data
- ~15MB total storage

---

## Why Two Configuration Methods?

### Option A (Direct Setup) Advantages

1. **Lua Power**: Use functions, conditionals, environment detection
   ```lua
   repos = vim.fn.system("git config github.repos"):split("\n")
   ```

2. **Single Source of Truth**: Everything in init.lua

3. **IDE Support**: LSP autocomplete for configuration options

4. **Validation**: Immediate feedback during Neovim startup

### Option B (Config File) Advantages

1. **Cross-System Sync**: Store in Neovim config, sync via Git
   ```bash
   # In dotfiles repository
   ~/.config/nvim/lua/plugins/github-stats/config.json
   ```

2. **Separation of Concerns**: Keep plugin config separate from init.lua

3. **Easy Backup**: Single JSON file contains all configuration

4. **Tool Integration**: Other tools can read/modify config.json

5. **Data Portability**: Config + data in same directory

### The Sync Use Case

**Scenario:** You use Neovim on multiple systems (work laptop, home desktop, remote server) and want consistent GitHub Stats across all machines.

#### Solution: remote mode (the default)

The data repository is the shared place: one workflow collects for all machines, each
machine clones and pulls it, nothing is fetched twice and no fetch results land in your
dotfiles. Put `storage = { repo = "you/github-stats-vault" }` into the spec every machine
uses, or run `:GithubStats setup` once per machine. See
[Where the history lives](../FEATURES/REMOTE.md).

#### Solution with Option B (local mode):

1. **Structure:**
   ```
   ~/.config/nvim/lua/plugins/github-stats/
   ├── config.json        # Sync this
   ├── last_fetch.json    # Don't sync (system-specific)
   └── data/              # Sync this (if you want shared history)
   ```

2. **In .gitignore:**
   ```gitignore
   # Don't sync fetch tracking
   github-stats/last_fetch.json

   # Optional: Don't sync data if system-specific
   # github-stats/data/
   ```

3. **Result:**
   - Same repository list on all systems
   - Shared historical data (if data/ synced)
   - System-specific fetch intervals (last_fetch.json not synced)

#### Alternative with Option A:

If config is in `init.lua`, it is synced with your Neovim config automatically — but the *data* is a separate question either way. Traffic data lives under `data_dir`, which defaults to `config_dir/data` (that is, inside `stdpath('config')`), so whether it syncs depends entirely on whether your dotfiles repository ignores that directory. Point `data_dir` somewhere outside the Neovim config tree if you want the two decisions separated.

---

## Next Steps

- **[Preparation Guide](PREPARATION.md)** – Create GitHub token, prepare environment
- **[Option A: Direct Setup](OPTION-A.md)** – Configure in init.lua
- **[Option B: Config File](OPTION-B.md)** – Use config.json
- **[Configuration index](README.md)** – all five pages, in reading order

For troubleshooting, see [docs/troubleshooting.md](../troubleshooting.md).

---

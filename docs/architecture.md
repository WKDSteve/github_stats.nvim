# Architecture

## Data Structure

Where this tree is depends on the mode ([FEATURES/REMOTE.md](FEATURES/REMOTE.md)):
in remote mode (the default) it is the clone of the data repository,
`stdpath('data')/github_stats.nvim-vault/`, which also holds
`.github/workflows/collect.yml` and is written only by that workflow (except
`config.json`); in local mode it is `config_dir`:

```
<clone> or <config_dir>                     # config_dir
├── config.json                    # User configuration (optional)
├── last_fetch.json                # Interval tracking
└── data/                          # data_dir (defaults to config_dir/data)
    └── username_repo/             # sanitized "owner/repo"
        ├── clones/
        │   ├── _archive.json      # written by retention, one entry per aged-out day
        │   ├── 2025-12-20T10-30-00.json
        │   └── 2025-12-21T10-30-00.json
        ├── views/                 # same shape as clones/
        ├── referrers/             # snapshots; only the newest is ever read
        └── paths/                 # snapshots; only the newest is ever read
```

One file per fetch per repo per metric, named by timestamp. Only the latest
file per calendar day is used (`analytics.deduplicate_by_date`), so a
repeated same-day fetch never double-counts. Growth is bounded by
[retention](FEATURES/RETENTION.md), which folds aged-out clones/views days
into `_archive.json` and deletes the raw files behind them, and prunes old
referrers/paths snapshots outright.

### Where the history comes from: `remote/`

`lua/github_stats/remote/` decides the mode and does the git work, the rest of
the plugin only sees a `config_dir`:

| Module | Job |
| --- | --- |
| `remote/init.lua` | the mode (`storage`, `config_dir`/`data_dir`, the guide's state file `stdpath('data')/github_stats.nvim-remote.json`), clone, fast-forward pull, `config.json` push, workflow dispatch, one sync at a time |
| `remote/wizard.lua` | the setup guide (`:GithubStats setup`) on `lib.nvim.ui.kit.async` |
| `remote/create.lua` | a new data repository: files from `templates/vault/`, first commit, `gh repo create --private --push` |
| `remote/proc.lua` | every `git`/`gh` process: awaitable inside the guide, callback-shaped elsewhere |

`init.lua` resolves the mode before `config.init`, so in remote mode the
clone is simply the `config_dir`. `fetcher.fetch_all`/`fetch_repo` and the
background cycle check `remote.active()` first and pull instead of fetching.

### The digest

Next to (not inside) this history the plugin publishes a derived, per-machine
copy for other programs: `<digest_dir>/digest/<owner_repo>.json` plus a
`root.json` pointer under `stdpath("data")/github_stats.nvim`. It is rebuilt
from the history above and never written into the synced config directory. See
[Digest](FEATURES/DIGEST.md).

See [Configuration Guide — Storage Paths](configurations/INTRO.md#storage-paths) for how to customize these locations.

## API Endpoints

The plugin uses GitHub REST API v3:

- `GET /repos/{owner}/{repo}/traffic/clones` – Clone statistics
- `GET /repos/{owner}/{repo}/traffic/views` – View statistics
- `GET /repos/{owner}/{repo}/traffic/popular/referrers` – Top referrers
- `GET /repos/{owner}/{repo}/traffic/popular/paths` – Top paths
- `GET /users/{username}/repos?per_page=100&page=N` – Repository discovery for `watch_users`

All four traffic endpoints are a **rolling 14-day window** on GitHub's side,
refreshed daily. That single fact drives three otherwise unrelated
decisions: the `cutoff_days` floor of 14, why dashboard auto-refresh
re-renders rather than fetches, and why today's data is excluded from every
aggregation as incomplete.

Requests go through `lib.nvim.net.github` (on `lib.nvim.net.curl`), the
GitHub client shared with other plugins: it owns the API headers, the token
handling (`-K -`, never argv) and the error rules (4xx/5xx, a `200` that is a
`{"message": ...}` error object, an exhausted rate limit). The token itself
still comes from this plugin's `config.get_token()`. Nothing in this plugin
shells out to `curl` itself. The background cycle that drives them is described in
[background-fetching.md](background-fetching.md).

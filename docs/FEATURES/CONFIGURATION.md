# Configuration: `setup()` and `config.json`

- **Module:** `config/init.lua` (`init`, `get`, `get_repos`, `get_token`, `get_retention`, `get_notification_level`, `notify`), `config/DEFAULTS.lua`
- **Config:** `opts.config_dir` (default `stdpath('config')/lua/plugins/github-stats`), `opts.data_dir` (default `config_dir/data`), `opts.token_source` (default `"env"`), `opts.token_env_var` (default `"GITHUB_TOKEN"`), `opts.token_file`, `opts.notification_level` (default `"all"`), `opts.digest_dir` (default `stdpath("data")/github_stats.nvim`), `opts.digest_daily_days` (default `400`)
- **User guide:** [configurations/README.md](../configurations/README.md)

Two interchangeable configuration methods with a fixed precedence:
`setup({ ... })` opts (highest) over a `config.json` in `config_dir`
(created with defaults on first run if neither is supplied) over
`config/DEFAULTS.lua`'s built-in defaults. The merge is a
`vim.tbl_deep_extend("force", ...)`, so a partial `setup()` table overrides
only the keys it names.

The precedence is deliberately "explicit code beats generated file": the
plugin writes a `config.json` on first run, so a file always exists, and the
other order would make every `setup()` option unreachable as soon as the
plugin had run once.

`notification_level` (`"all"` / `"errors"` / `"silent"`) gates every
`config.notify()` call plugin-wide — `"errors"` shows only `warn`/`error`
level notifications, `"silent"` shows none (diagnostics remain available via
`:GithubStats debug`). It is the single gate; the background cycle's own
silence is a *default* noise level on top of it, not a second independent
switch.

Both directories are resolved once in `M.init()` and read back through
`M.get_config_dir()` / `M.get_storage_root()`; nothing else recomputes a
path. Data lives under `config_dir/data` unless `data_dir` says otherwise.

`storage` is not an option of this store either: `github_stats.init` resolves
it first (`github_stats.remote.resolve`), takes it out of the table like the
two paths, and in remote mode hands the clone of the data repository to
`M.init()` as `config_dir`. So in remote mode `config.json` is the data
repository's own (shared with every machine and the workflow), and the
`"file"` layer is that file. See [REMOTE.md](REMOTE.md).

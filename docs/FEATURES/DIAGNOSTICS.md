# Diagnostics: `:GithubStats debug` and `:checkhealth`

- **Module:** `health.lua` (`check`), `bindings/usrcmds/debug.lua`
- **Usercmds:** `:GithubStats debug`
- **User guide:** [troubleshooting.md](../troubleshooting.md)

`:checkhealth github_stats` validates configuration (repo format, at least
one of `repos`/`watch_users` set), token presence/source, background-cycle
status, `curl` availability (cross-platform, via
`lib.nvim.cross.executable`), storage directory writability, dashboard
config shape, and a synchronous live API connectivity test (10s timeout,
distinguishing 401/403/404 from a generic failure). Its *Storage* section
first names where the history lives ([REMOTE.md](REMOTE.md)): remote with the
data repository and its clone, local, or, as `info` since nothing has to be
done, remote not yet set up (fetching locally meanwhile) or not yet cloned
(it is cloned on the next start). It reads back the
configuration `setup()` already loaded rather than re-initializing it, so it
reports "Configuration not loaded" if run before `setup()` has ever run.

The *GitHub Stats Digest* section checks the digest that other programs read
([DIGEST.md](DIGEST.md)): `digest_dir` and `digest_daily_days` are valid, the
digest directory can be written, `root.json` is in place and points at the
digest directory, and the digests are not behind the stored history (the
synced-history case — the fix it names is `:GithubStats digest`).

`:GithubStats debug` covers overlapping ground non-interactively: repo
counts (explicit vs. discovered), token source/length,
`fetcher.last_fetch_summary` (with per-repo/metric error detail), and its
own live API test against the first configured repository, plus where the
digest goes and the outcome of the last digest write. The division is when,
not what: health runs before there is any data to look at, debug runs after
a fetch has recorded something worth reading.

`refresh_interval_seconds = 0` is reported as info ("Auto-refresh disabled by
configuration") rather than rejected — it is the documented off switch, and
health validation that failed the one value the docs recommend was a real
bug in an earlier version. Any other value below `10` is still rejected as
too aggressive.

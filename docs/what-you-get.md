# What you get with the defaults

On the first start a short guide asks where the history should live: in a
private data repository a GitHub Actions workflow fills every day (the
default), or in a folder this Neovim fetches into itself. Either way the
collecting then runs on its own — nothing below requires further
configuration first. See [Where the history lives](FEATURES/REMOTE.md).

| Command | Does |
| --- | --- |
| `:GithubStats setup` | The guide again: switch modes, finish what is missing (a clone, the secret) |
| `:GithubStats dashboard` | The interactive view over everything collected |
| `:GithubStats fetch force` | Fetch now, ignoring the schedule (remote mode: start the workflow) |
| `:GithubStats sync` | Remote mode: pull now, and push a changed `config.json` |
| `:GithubStats show` | Detailed statistics for one repository or metric |
| `:GithubStats summary` | Aggregated across every configured repository |
| `:GithubStats referrers` / `:GithubStats paths` | Top referrer sources, most visited paths |
| `:GithubStats chart` | Charts and sparklines |
| `:GithubStats diff` | Period over period |
| `:GithubStats export` | Write the history out as CSV, Markdown or PDF |
| `:GithubStats compact [dry-run]` | Archive old data and prune stale snapshots |

That is on top of what needs no command at all: silent background fetching
(or, in remote mode, pulling what the workflow collected), a JSON history, and automatic archiving/pruning so the store stays
bounded rather than growing forever. The retention policy is deliberate and
documented rather than incidental — see
[FEATURES/RETENTION.md](FEATURES/RETENTION.md) for what is kept at full
resolution, what is rolled up, and why.

The full command tree, with examples and output, is [commands.md](commands.md);
the dashboard's own keys are in [dashboard.md](dashboard.md).

# GithubStats command tree

- **Module:** `bindings/usrcmds/init.lua`, one `composer.verb("GithubStats", ...)` registration
- **Usercmds:** `:GithubStats setup|sync|fetch|show|summary|referrers|paths|chart|export|diff|compact|digest|debug|dashboard` — full reference in [commands.md](../commands.md) and [BINDINGS.md](../BINDINGS.md)

A single `:GithubStats <subcommand>` verb (built with
[`lib.nvim.bindings.usercmd.composer`](https://github.com/WKDSteve/lib.nvim)),
with `<Tab>` completion at every positional slot — repo names and date
presets complete dynamically against live config (`GH_REPO`,
`GH_REPO_OR_ALL`, `GH_DATE_OR_PRESET`, `GH_PERIOD` custom completion types
registered in `usrcmds/init.lua`).

There is deliberately no per-subcommand flat `:GithubStatsX` alias set — that
was the pre-migration shape and was dropped as a breaking change, per the
module's own header comment. The bang is the one thing that moved rather than
disappeared: Vim binds `!` to the command name itself, so collapsing eleven
commands into one verb makes forced dashboard refresh `:GithubStats! dashboard`,
not `:GithubStats dashboard!`.

Each route reconstructs the space-joined argument string a flat `nargs="+"`
command would have received and forwards it to the same `execute()` the
pre-migration command used, so validation, error messages and business logic
are unchanged by the migration.

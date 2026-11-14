# Where the history lives: remote (default) or local

GitHub keeps traffic for fourteen days. Someone has to collect it every day, and
everyone who wants the history has to see the same files. Two modes:

| | **remote** (default) | **local** |
| --- | --- | --- |
| Who fetches | a GitHub Actions workflow in a private data repository, once a day | this Neovim, in the background |
| Where the history is | that repository; every machine clones and pulls it | a folder on this machine (`config_dir`/`data_dir`) |
| Days without an editor | covered: the workflow runs anyway | lost once they fall out of GitHub's 14-day window |
| Several machines | the same history everywhere, fetched once | each machine fetches; syncing the folder is up to you |
| Needs | the GitHub CLI (`gh`) once for the setup, a token as a repository secret | a token on this machine |

Module: `lua/github_stats/remote/` (`init.lua` the mode and the git work on the
clone, `create.lua` a new data repository, `wizard.lua` the setup guide,
`proc.lua` the processes). The workflow and README of a new data repository are
`templates/vault/`.

## Choosing

Nothing to choose up front: on the first start after installing, the setup guide
opens by itself (once; "Later" is remembered) and asks where the history should
live. Until it has run, the plugin fetches locally, so no day is lost while you
decide.

To decide in the spec instead, one key:

```lua
-- lazy.nvim
{
  "WKDSteve/github_stats.nvim",
  dependencies = { "WKDSteve/lib.nvim", "WKDSteve/ui.nvim" },
  opts = {
    storage = "local",                         -- fetch in this Neovim, as before
    -- storage = { repo = "you/github-stats-vault" }, -- remote, repository known: no guide, cloned on first start
  },
}
```

`storage` takes the mode alone (`"remote"`, `"local"`) or a table:

| Key | Default | Meaning |
| --- | --- | --- |
| `mode` | `"remote"` | `"remote"` or `"local"` |
| `repo` | the guide's answer | the data repository, `owner/name` |
| `dir` | `stdpath("data")/github_stats.nvim-vault` | where it is cloned on this machine |
| `pull_interval_minutes` | `60` | how often a running editor pulls |

The mode is decided in this order, first match wins:

1. `storage` in `setup()`.
2. `config_dir` or `data_dir` in `setup()`: you manage the folder yourself, so local.
3. The guide's answer on this machine (`stdpath("data")/github_stats.nvim-remote.json`).
4. Remote.

## The setup guide

`:GithubStats setup`. Each step checks first whether it is already done, so running
it again resumes where it stopped.

1. **Where should the history live?** Remote, local, or later.
2. **The GitHub CLI.** Remote mode creates and reads the data repository with `gh`.
   Not installed or not logged in: the guide says how (`gh auth login`) and stops.
3. **The data repository** (default `<you>/github-stats-vault`).
   - It exists (you set it up on another machine): it is cloned.
   - It does not: it is created **private**, with the workflow, a README and your
     `config.json`. If this machine already has a local history, the guide offers to
     take it over, so nothing collected so far is lost. Without one it asks what the
     workflow should track: all public repositories of your login (`watch_users`), a
     list you type (`repos`), or nothing yet (you edit `config.json` later).
4. **The secret `GH_STATS_TOKEN`** the workflow reads the traffic with. The guide
   offers to set it from the token this plugin already uses (handed to `gh secret set`
   on stdin, never on a command line), or shows the command to run yourself.
5. **The first run**, if you like, right away (`gh workflow run collect.yml`).

The token needs to read the traffic of the tracked repositories: a classic token with
the `repo` scope, or a fine-grained token with "Administration: read" on them.
A fine-grained token covers one owner; tracking repositories of two owners takes a
classic token.

## Day to day in remote mode

- On start and every `pull_interval_minutes` the clone is pulled (fast-forward only).
  When something arrived, the read memo is dropped and the digests other programs read
  are rebuilt.
- `:GithubStats sync` pulls now, after committing and pushing a changed `config.json`
  (the one file a machine writes; rebased onto the workflow's commits first).
- `:GithubStats fetch` starts the workflow instead of fetching here, and pulls its
  result a little later.
- The dashboard's refresh keys pull instead of fetching.
- `:GithubStats compact` only runs as `dry-run`: the workflow archives and prunes, and a
  clone that did it on its own could no longer be fast-forwarded.
- This machine never fetches in remote mode: a second fetcher would fetch twice and
  leave files in a clone nobody commits.
- To track another repository, edit `config.json` in the clone (`:checkhealth github_stats`
  shows where it is), then `:GithubStats sync`.

## The workflow

`templates/vault/.github/workflows/collect.yml`, copied into the data repository:

- runs every day at 04:23 UTC, and on demand (`workflow_dispatch`);
- installs Neovim, clones `github_stats.nvim` and `lib.nvim` (public, `main`);
- runs `scripts/github_stats.lua collect --force --token-env=GH_STATS_TOKEN
  --config-dir=<the repository>`, which is the same code a background cycle runs:
  discovery from `watch_users`, the fetch, retention;
- commits what changed as `github-actions[bot]` and pushes (rebasing up to three
  times when a machine pushed `config.json` in between);
- fails visibly (GitHub mails you) when `collect` did, after committing what it got.

Runs on a private repository count against the Actions minutes of your account; one
run takes about a minute.

## Moving from local to remote

Run `:GithubStats setup`, choose remote, and let it create the repository with your
local history taken over. The old folder is left as it was; delete it (and its
`config_dir` from your spec) once the first run has landed.

## Limits

- Remote mode needs `git` on every machine and `gh` on the machine that runs the guide
  (a machine with `storage.repo` in its spec only clones, through `gh` when it is there,
  else plain `git` with your credential helper).
- A clone with local changes besides `config.json` cannot be fast-forwarded; the pull
  then fails with git's message, and nothing is overwritten.

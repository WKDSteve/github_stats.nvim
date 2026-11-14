# Quickstart

On the first start after installing, a short guide opens by itself and asks where
the history should live (any time later: `:GithubStats setup`):

- **Remote** (recommended): a private repository of yours holds the history and a
  GitHub Actions workflow in it collects every day; this Neovim only pulls. The guide
  creates it (or clones it, when another machine already did), sets the token as its
  secret and starts the first run. Needs the [GitHub CLI](https://cli.github.com),
  logged in once. Details: [Where the history lives](FEATURES/REMOTE.md).
- **Local**: this Neovim fetches by itself, as described below. The same in the spec,
  without the guide: `opts = { storage = "local" }`.

In remote mode `:GithubStats fetch` starts the workflow and `:GithubStats sync`
pulls; the rest of this page is the local mode.

First, the token — an environment variable is the recommended shape:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

No token yet, or unsure it has the right scope? [Preparation](configurations/PREPARATION.md)
walks through creating one and verifying it reaches the traffic API.

Then, in Neovim, fetch once by hand and look at the result:

```vim
:GithubStats fetch force
:GithubStats dashboard
```

Verify your setup any time with:

```vim
:checkhealth github_stats
```

From here: [What you get with the defaults](what-you-get.md) for the commands
worth knowing on day one, or the [command reference](commands.md) for the full
`:GithubStats <subcommand>` tree.

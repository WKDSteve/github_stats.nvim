# Digest (traffic for other programs)

- **Module:** `digest.lua` (`build`, `write`, `write_all`, `write_root`, `stale`, `refresh_if_stale`, `digest_dir`, `default_dir`, `root_path`, `digest_file`)
- **Usercmds:** `:GithubStats digest`
- **Config:** `opts.digest_dir` (default `stdpath("data")/github_stats.nvim`), `opts.digest_daily_days` (default `400`)
- **Health:** `:checkhealth github_stats` → *GitHub Stats Digest*

The plugin keeps GitHub's traffic past the 14 days GitHub itself reports. The
digest is how another program — a desktop app, another Neovim plugin — shows
that data **without re-implementing the plugin's rules** (one value per day,
today excluded as incomplete, the retention archive, the trend windows) and
**without ever seeing a token**. It is a small, read-only JSON file per
repository, and this page is its contract: what the files are, where they are,
how a reader finds them, and what they do not say.

Nothing in the digest is fetched from GitHub. It is derived from the history
the plugin already holds, and rebuilt from it at any time.

## Table of content

  - [Where the files are](#where-the-files-are)
  - [How a reader finds them](#how-a-reader-finds-them)
  - [`root.json`](#rootjson)
  - [`digest/<owner_repo>.json`](#digestowner_repojson)
  - [What the digest does not say](#what-the-digest-does-not-say)
  - [When it is written](#when-it-is-written)
  - [Rules for readers](#rules-for-readers)

## Where the files are

```
<default>/github_stats.nvim/root.json            the pointer, always here
<digest_dir>/digest/<owner_repo>.json            one file per repository
<default>/github_stats.nvim/stale-memo.json      private to the plugin, not part of this contract
```

- `<default>` is Neovim's `stdpath("data")`. `digest_dir` defaults to the same
  folder, so with no configuration both are under `stdpath("data")/github_stats.nvim`.
- The history lives in the Neovim **config** (`…/lua/plugins/github-stats/data`),
  because that folder is what a user syncs between machines. The digest is
  *derived* and rewritten in place, so in a synced folder two machines would
  overwrite each other and the sync tool would report conflicts. It therefore
  lives in a **local, per-machine** place and is rebuilt from the synced history
  whenever that is newer (see [When it is written](#when-it-is-written)).
- `digest_dir` can point anywhere. `root.json` is written to the default place
  **regardless**, and names where the digests really are. Digests always sit in a
  `digest/` subfolder, so even a `digest_dir` that is the history folder never
  puts a digest next to the per-repository history folders.
- `digest_dir` is best set in `setup()`, not in the (synced) `config.json`: the
  value is only right for one machine.
- `<owner_repo>` is the repository name with `/` replaced by `_` and every byte
  outside `[A-Za-z0-9._-]` percent-encoded (`a/b:c` → `a_b%3Ac`) — the same rule
  the history folders use. `/` and a literal `_` both end up as `_`, so the name
  is not strictly injective; on github.com it never collides in practice (an owner
  name cannot contain `_`), and the file's own `repo` field is authoritative for
  which repository a file holds. A reader should not derive the name itself:
  `root.json` lists it.

## How a reader finds them

The same chain for every reader, first hit wins:

1. **An explicit setting** of the reader (the app: a folder chosen in its Traffic
   section; `docmap.nvim`: `opts.traffic.digest_dir`).
2. **`root.json`** at the default place.
3. **Ask Neovim.** `require("github_stats.digest").digest_dir()` — a module of its
   own that needs only `config`, `storage`, `analytics` and `lib.nvim`, **not**
   `ui.nvim`. Probe *this*, not `require("github_stats")`: the top-level module
   loads the dashboard at load time, which needs `ui.nvim`, and would report
   "not installed" for a user who has the plugin but not (yet) its UI dependency.
   `digest_dir()` answers before `setup()` has run (it then names the default).
4. Nothing found → say so. Never search the disk.

Do not read the path out of the user's plugin installation spec. It is Lua code
(`opts` may be a function); ask the plugin instead.

## `root.json`

```json
{
  "schema": 1,
  "digest_dir": "C:/Users/me/AppData/Local/nvim-data/github_stats.nvim",
  "data_dir": "C:/Users/me/AppData/Local/nvim/lua/plugins/github-stats/data",
  "repos": { "owner/name": "owner_name" }
}
```

| Field | Meaning |
|---|---|
| `schema` | Integer, `1`. A reader must refuse a higher one. |
| `digest_dir` | Where the digests are. Forward slashes on every platform. |
| `data_dir` | Where the raw history is (the plugin's `data_dir`). Only for a reader that wants to fall back to the raw files; omitted before `setup()` has run. |
| `repos` | Repositories that have a digest file → the file name stem. **Not being listed means there is no digest** — not tracked, or nothing fetched yet — never "zero traffic". Omitted entirely while no digest exists. |

`root.json` is not written until at least one digest exists.

## `digest/<owner_repo>.json`

```json
{
  "schema": 1,
  "repo": "owner/name",
  "generated": "2026-09-28T07:03:09Z",
  "fetched": "2026-09-27T20:37:37Z",
  "span": { "from": "2026-06-29", "to": "2026-09-23" },
  "views":  { "d7": {"count": 4, "uniques": 3}, "d30": {…}, "d90": {…}, "trend": 12.5 },
  "clones": { "d7": {…}, "d30": {…}, "d90": {…}, "trend": -3.0 },
  "daily": {
    "views":  [["2026-09-22", 2, 2], ["2026-09-23", 1, 1]],
    "clones": [["2026-09-22", 27, 14], ["2026-09-23", 17, 9]]
  },
  "referrers": [{ "referrer": "google.com", "count": 9, "uniques": 5 }],
  "paths": [{ "path": "/owner/name/blob/main/docs/X.md", "title": "docs/X.md", "count": 7, "uniques": 3 }]
}
```

| Field | Meaning |
|---|---|
| `schema` | Integer, `1`. |
| `repo` | `owner/name`. |
| `generated` | ISO 8601 UTC. When **this digest** was built. |
| `fetched` | ISO 8601 UTC. The newest fetch the digest was built from. Show this as "data as of"; it is also what the plugin compares against the history to detect a stale digest. Absent if nothing was ever fetched. |
| `span` | First and last day with data, `YYYY-MM-DD`. Absent when there are no daily values. |
| `views`, `clones` | Sums over the last 7/30/90 **complete** days (today is excluded by the plugin as incomplete), and `trend`. |
| `…​.uniques` | The **sum of the daily uniques**, not distinct visitors over the window. Presented as "uniques", not "visitors". |
| `…​.trend` | Percent change of the last 7 complete days against the 7 before: `12.5` means +12.5 %. Fixed at 7 days, independent of the dashboard's trend setting. Absent when neither window holds data. |
| `daily.views`, `daily.clones` | Oldest first, at most `digest_daily_days` entries each. An entry is `[date, count, uniques]`. The two metrics can cover different days. Empty array = no days. |
| `referrers` | GitHub's **top 10** referrers in the latest snapshot. `[]` means GitHub reported none; **absent means the plugin has no snapshot** (unknown). |
| `paths` | GitHub's **top 10** popular content paths in the latest snapshot; same `[]` versus absent rule. `path` is a URL path on github.com; `title` is optional. |

All counts are non-negative integers. Strings are clipped (referrer 200, path
500, title 300 characters). Only these fields are ever written: the payload is
built by copying named fields, so nothing else from the plugin's configuration
— in particular **no token, no token path and no user path** — can appear in it.

## What the digest does not say

- **Not a heat map.** GitHub reports repository-level traffic and a top-10 of
  paths. A page that is not in the top 10 is **unknown, not zero**. Never show
  "0 views" for a file that is merely absent.
- **No stars, forks or issues.** Not collected.
- **No traffic for repositories the token cannot push to.** GitHub refuses it;
  such a repository simply has no digest.
- **History starts the day the collector started.** Before that, nothing.
- **Windows are approximate at the day boundary.** "Today is incomplete" is
  judged by the local calendar, the 7/30/90 windows are counted in UTC; the
  difference is at most one day at the edge and matches the dashboard.

## When it is written

| Trigger | What happens |
|---|---|
| After a fetch (`:GithubStats fetch`, the background cycle, the dashboard's refresh keys) | The digests of the repositories that got data are rebuilt on later event-loop turns, one repository per turn and `root.json` last, so no single turn holds the editor for the whole set. A failure never fails or slows the fetch. |
| Every background cycle, first | If any tracked repository's digest is missing or was built from older history than is now on disk (the other machine fetched and the history synced), everything is rebuilt. While nothing changed, the check is one `stat` per history folder and per digest file: a folder is listed and a digest decoded only after it changed, and what the check learnt is kept in `stale-memo.json` for the next session (deleting it only costs one full check). |
| `:GithubStats digest` | Rebuild all now. The answer to "the local digest lags after a sync". |

Rules for every write: **atomic** (a temp file in the same folder, then a rename —
a reader never sees half a file; a stray `*.tmp` is not a digest), **only when
the content changed** (compared without `generated`, so an idle repository does
not touch its mtime, which a reader's cache keys on), and **only for the
repositories of this cycle**.

Two consequences worth knowing:

- A digest for a repository that is no longer tracked stays until deleted; its
  `generated`/`fetched` say how old it is.
- `root.json` keeps repositories whose digest file still exists, whether or not
  the current configuration lists them.

## Rules for readers

- **Read-only.** Never write into `digest_dir`.
- **Cap the read** (a few MiB is far above a real file; a 400-day digest is about
  20 KB) and treat an unreadable, oversized or non-JSON file as "unreadable",
  not as a crash.
- **Refuse a `schema` greater than you know**, and say that the digest is newer
  than the reader understands.
- **Treat every string as untrusted text.** A referrer is whatever a website sent
  — render it as text, never as markup. A `path` is a URL path, not a file path:
  before it becomes a link to a local file, make it project-relative, reject `..`,
  a backslash, a drive letter and a leading `/`, and check the joined path is
  still inside the project.
- **Missing is unknown.** No digest, no `referrers`, a path outside the top 10:
  none of them means zero.
- **Read numbers as integers with saturating arithmetic**; a hand-edited file may
  contain anything.
- Ignore fields you do not know; `schema` changes only when a field's meaning does.

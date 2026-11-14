# Troubleshooting Guide

This document explains common errors and how to resolve them.

## Table of Contents

- [Understanding Error Messages](#understanding-error-messages)
- [Common Fetch Errors](#common-fetch-errors)
- [Configuration Issues](#configuration-issues)
- [Network and API Problems](#network-and-api-problems)
- [Storage Issues](#storage-issues)
- [Remote Mode (Data Repository)](#remote-mode-data-repository)
- [Notification Settings](#notification-settings)
- [Diagnostic Commands](#diagnostic-commands)
- [Getting Help](#getting-help)
- [Quick Reference](#quick-reference)

---

## Understanding Error Messages

### Error Format

When you see: `[github-stats] Fetched 40 metrics, 4 errors`

This means:
- **40 metrics** were successfully fetched and stored
- **4 metrics** failed for various reasons

### Finding Error Details

```vim
:GithubStats debug
```

This shows:
- Configuration status
- Token availability
- **Last Fetch Summary** with detailed error messages
- Test API call result

#### Example Output:
```
Last Fetch Summary:
────────────────────────────────────────────────────────────
Timestamp: 2025-12-21T09:05:52
Successful: 40 metrics
Errors: 4

Error Details:
  • username/old-repo/clones: API Error: 404 Not Found
  • username/old-repo/views: API Error: 404 Not Found
  • username/private-repo/referrers: API Error: 403 Forbidden
  • username/private-repo/paths: API Error: 403 Forbidden
```

---

## Common Fetch Errors

### 1. 404 Not Found

#### Error Message:
```
username/repo/clones: API Error: 404 Not Found
```

#### Causes:
- Repository name is incorrect
- Repository was renamed or deleted
- Repository visibility changed
- Typo in config.json

#### Solutions:
1. Verify repository exists: https://github.com/username/repo
2. Check exact name in GitHub (case-sensitive)
3. Update config.json:
   ```json
   {
     "repos": [
       "username/correct-repo-name"
     ]
   }
   ```
4. Remove old repositories from config if deleted

---

### 2. 403 Forbidden

#### Error Message:
```
username/repo/referrers: API Error: 403 Forbidden
```

#### Causes:
- Token lacks `repo` permission
- Token expired
- Rate limit exceeded (5,000 requests/hour)
- Private repository without access

#### Solutions:

#### For Permission Issues:
1. Check token has `repo` scope:
   - Go to: https://github.com/settings/tokens
   - Click your token
   - Verify `repo` is checked
   - Regenerate if needed

2. Update token in config:
   ```bash
   # If using environment variable:
   export GITHUB_TOKEN="ghp_your_new_token"

   # If using token file:
   echo "ghp_your_new_token" > ~/.github_token
   chmod 600 ~/.github_token
   ```

#### For Rate Limits:
- Wait 1 hour for reset
- Reduce number of repositories
- Increase `fetch_interval_hours` in config

#### For Private Repos:
- Ensure token has access to the organization/user
- Verify you have read permissions on the repository

---

### 3. 401 Unauthorized

#### Error Message:
```
username/repo/views: API Error: 401 Unauthorized
```

#### Causes:
- Token is invalid or expired
- Token not provided
- Wrong token format

#### Solutions:
1. Verify token is set:
   ```bash
   # Environment variable:
   echo $GITHUB_TOKEN

   # Token file:
   cat ~/.github_token
   ```

2. Test token manually:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/user
   ```

3. Generate new token if needed:
   - https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Select `repo` scope
   - Copy and save securely

---

### 4. Connection Timeout

#### Error Message:
```
username/repo/clones: curl timeout after 30s
```

#### Causes:
- Network connectivity issues
- Firewall blocking GitHub
- Proxy configuration needed
- GitHub API down (rare)

#### Solutions:

#### Check Network:
```bash
# Test basic connectivity
ping github.com

# Test API access
curl https://api.github.com
```

#### Configure Proxy (if needed):
```bash
# Set proxy environment variables
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
```

#### Check GitHub Status:
- Visit: https://www.githubstatus.com/

---

### 5. Invalid JSON Response

#### Error Message:
```
username/repo/paths: Failed to parse JSON response
```

#### Causes:
- GitHub API returned malformed data (rare)
- Network interruption during fetch
- Proxy injecting HTML

#### Solutions:
1. Try manual fetch:
   ```vim
   :GithubStats fetch force
   ```

2. Check raw API response:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/repos/username/repo/traffic/clones
   ```

3. If proxy issue, bypass or configure correctly

---

## Configuration Issues

### Missing config.json

#### Error Message:
```
[github-stats] Configuration error: File not found
```

#### Solution:
Plugin creates it automatically, but you can create manually:

```bash
mkdir -p ~/.config/nvim/lua/plugins/github-stats
cat > ~/.config/nvim/lua/plugins/github-stats/config.json << 'EOF'
{
  "repos": [
    "username/repo1",
    "username/repo2"
  ],
  "token_source": "env",
  "token_env_var": "GITHUB_TOKEN",
  "fetch_interval_hours": 24,
  "notification_level": "all"
}
EOF
```

---

### Invalid JSON Syntax

#### Error Message:
```
[github-stats] Failed to parse config JSON: Expected ','
```

#### Causes:
- Missing comma between array elements
- Trailing comma before closing bracket
- Unquoted strings
- Comments in JSON (not allowed)

#### Solution:
Validate your JSON:

```bash
# Using jq (if installed)
cat ~/.config/nvim/lua/plugins/github-stats/config.json | jq .

# Or use online validator:
# https://jsonlint.com/
```

Or, without leaving Neovim: if you have
[`data.nvim`](https://github.com/WKDSteve/data.nvim) installed, open
`config.json` and run `:JSON pretty` — a malformed file is left untouched
with a clear decode-error notification instead of a silent partial rewrite,
so it doubles as a validator.

#### Common mistakes:
```json
// WRONG:
{
  "repos": [
    "user/repo1"  // Missing comma
    "user/repo2"
  ]
}

// CORRECT:
{
  "repos": [
    "user/repo1",
    "user/repo2"
  ]
}
```

---

### Repository Name Format

#### Error Message:
```
[github-stats] Invalid repo format: must be 'owner/repo'
```

#### Wrong Formats:
```json
"repos": [
  "myrepo",              // Missing owner
  "github.com/user/repo", // Include domain
  "user/repo.git",       // Include .git
  "user\\repo"           // Wrong separator
]
```

#### Correct Format:
```json
"repos": [
  "username/repository-name",
  "organization/project",
  "WKDSteve/github_stats.nvim"
]
```

---

## Network and API Problems

### Firewall Blocking

#### Symptoms:
- All fetch operations timeout
- Works on other networks
- Other GitHub tools work

#### Solution:

Allow GitHub domains:
- `github.com`
- `api.github.com`
- Port: `443` (HTTPS)

#### Windows Firewall:
```powershell
New-NetFirewallRule -DisplayName "GitHub API" `
  -Direction Outbound -RemoteAddress api.github.com `
  -Protocol TCP -RemotePort 443 -Action Allow
```

---

### Proxy Configuration

#### For Corporate Networks:

```bash
# In ~/.bashrc or ~/.zshrc
export HTTP_PROXY="http://proxy.company.com:8080"
export HTTPS_PROXY="http://proxy.company.com:8080"
export NO_PROXY="localhost,127.0.0.1"
```

#### Windows (PowerShell):
```powershell
$env:HTTP_PROXY = "http://proxy.company.com:8080"
$env:HTTPS_PROXY = "http://proxy.company.com:8080"
```

---

### Rate Limiting

#### Error Message:
```
username/repo/clones: API Error: 403 rate limit exceeded
```

#### Check Rate Limit:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.github.com/rate_limit
```

#### Response:
```json
{
  "rate": {
    "limit": 5000,
    "remaining": 0,
    "reset": 1640000000
  }
}
```

#### Solutions:
1. Wait until `reset` timestamp
2. Increase `fetch_interval_hours` in config
3. Reduce number of repositories

---

## Storage Issues

### Permission Denied

#### Error Message:
```
[github-stats] Failed to write file: Permission denied
```

#### Solutions:

#### Linux/macOS:
```bash
# Check permissions
ls -la ~/.config/nvim/lua/plugins/github-stats/

# Fix permissions
chmod 755 ~/.config/nvim/lua/plugins/github-stats/
chmod 644 ~/.config/nvim/lua/plugins/github-stats/config.json
```

#### Windows:
```powershell
# Check current user
whoami

# Verify folder ownership
icacls "%LOCALAPPDATA%\nvim\lua\plugins\github-stats"
```

---

### Disk Space

#### Error Message:
```
[github-stats] Failed to save: No space left on device
```

#### Check Disk Space:

#### Linux/macOS:
```bash
df -h ~/.config/nvim/
```

#### Windows:
```powershell
Get-PSDrive C
```

#### Storage Usage:
- ~2KB per fetch per repository per metric
- 4 metrics × 14 days × 11 repos = ~616KB
- Growth is bounded by retention, not linear in time

#### Cleanup Old Data:

Use the plugin's own retention pass rather than deleting files by hand — it
folds aged-out clones/views days into a per-metric `_archive.json` instead
of discarding them, and always keeps the newest referrers/paths snapshot:

```vim
:GithubStats compact dry-run   " what would be archived/deleted, and how many bytes
:GithubStats compact           " actually do it
```

Retention also runs by itself, at most once per 24h after a fetch. See
[Data retention](FEATURES/RETENTION.md) for the thresholds and the
`cutoff_days` floor of 14.

```bash
# Show storage size
du -sh ~/.config/nvim/lua/plugins/github-stats/data/
```

---

## Remote Mode (Data Repository)

`:checkhealth github_stats`, section *Storage*, says which mode is in use and
where the clone is. See [FEATURES/REMOTE.md](FEATURES/REMOTE.md) for how the
mode works.

### The workflow fails: "no GitHub token: Environment variable GH_STATS_TOKEN not set"

The data repository has no secret `GH_STATS_TOKEN`. Set it (or run
`:GithubStats setup`, which offers to):

```bash
gh secret set GH_STATS_TOKEN -R <owner>/<data-repository>
gh secret list -R <owner>/<data-repository>   # must list GH_STATS_TOKEN
```

The token needs to read the traffic: a classic token with `repo`, or a
fine-grained one with "Administration: read" on the tracked repositories (one
owner per fine-grained token).

### The workflow fails with exit code 1

`collect` fetched, but some repository or metric failed (403 for a repository
the token cannot read, 404 for a renamed one). What did arrive is still
committed; the run log names the failing `owner/repo/metric`. Fix the list in
`config.json` (then `:GithubStats sync`) or the token's access.

### "Pulling ... failed: fatal: Not possible to fast-forward"

The clone has local commits or changes besides `config.json`, so it can no
longer follow the workflow. Nothing is overwritten. Look at the clone (path in
`:checkhealth`) with `git status` / `git log origin/main..`, keep what you need,
then reset it to `origin/main`, or delete the clone: it is cloned again on the
next start.

### "Cloning ... failed" on a new machine

The machine cannot read the private data repository. With `gh` installed,
`gh auth login`; otherwise make sure plain `git clone https://github.com/<owner>/<repo>.git`
works with your credential helper. Until then the plugin fetches locally.

### "Updating the workflow failed" in `:GithubStats setup`

Moving the workflow to a newer pin pushes `.github/workflows/collect.yml`, and GitHub
accepts a workflow file only from a token with the `workflow` scope:
`gh auth refresh -s workflow` (or a credential helper token with that scope), then run
`:GithubStats setup` again. Until then the workflow keeps running its old pin.

### No new data although the workflow ran

The editor pulls on start and every `storage.pull_interval_minutes` (default
60). `:GithubStats sync` pulls now. `:GithubStats fetch` starts the workflow
and pulls its result about two and a half minutes later.

---

## Notification Settings

### Controlling Notification Verbosity

Edit `~/.config/nvim/lua/plugins/github-stats/config.json`:

```json
{
  "notification_level": "all"  // Options: "all", "errors", "silent"
}
```

#### Options:

| Level | Behavior |
|-------|----------|
| `all` | Show all notifications (info, warnings, errors) |
| `errors` | Only show warnings and errors |
| `silent` | No notifications at all |

#### Examples:

#### Verbose (see everything):
```json
"notification_level": "all"
```
Shows:
- ✓ Starting fetch
- ✓ Successfully fetched
- ⚠ Fetch errors
- ✗ Configuration errors

#### Minimal (only problems):
```json
"notification_level": "errors"
```
Shows:
- ⚠ Fetch errors
- ✗ Configuration errors

#### Silent (no popups):
```json
"notification_level": "silent"
```
Shows nothing, check `:GithubStats debug` manually

---

## Diagnostic Commands

### Full Health Check

```vim
:checkhealth github_stats
```

Checks:
- Configuration validity
- Token access
- curl availability
- Storage paths
- API connectivity

---

### Detailed Debug Info

```vim
:GithubStats debug
```

Shows:
- Current configuration
- Token status
- **Last fetch error details**
- API test result

---

### Check Messages

```vim
:messages
```

Shows all Neovim messages including plugin notifications.

---

### Manual Fetch (Bypass Interval)

```vim
:GithubStats fetch force
```

Forces immediate fetch, useful for testing.

---

### View Raw Data

```bash
# Show latest fetch for a repo
cat ~/.config/nvim/lua/plugins/github-stats/data/username_repo/clones/*.json | tail -1

# List all stored data
find ~/.config/nvim/lua/plugins/github-stats/data/ -name "*.json"
```

If you have [`data.nvim`](https://github.com/WKDSteve/data.nvim) installed,
opening one of these files and running `:JSON pretty` is often quicker than
piping through `jq` — `:JSON lines` also flattens a day's metrics onto one
`path: value` line each, useful for spotting which field actually changed
between two fetches.

---

## Getting Help

If problems persist:

1. Run diagnostics:
   ```vim
   :checkhealth github_stats
   :GithubStats debug
   :messages
   ```

2. Check configuration:
   ```bash
   cat ~/.config/nvim/lua/plugins/github-stats/config.json
   ```

3. Test token manually:
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/repos/YOUR_USER/YOUR_REPO/traffic/clones
   ```

4. Open an issue:
   - Include output from `:GithubStats debug`
   - Include relevant error messages
   - Mention OS and Neovim version
   - GitHub: https://github.com/WKDSteve/github_stats.nvim/issues

---

## Quick Reference

| Problem | Command | Fix |
|---------|---------|-----|
| "4 errors" | `:GithubStats debug` | Check error details |
| Token issue | `:checkhealth github_stats` | Verify token permissions |
| Too many notifications | Edit config.json | Set `notification_level: "errors"` |
| Network timeout | `curl api.github.com` | Check connectivity |
| Storage full | `du -sh ~/.config/nvim/lua/plugins/github-stats/` | Clean old files |
| Invalid JSON | `jq . config.json` | Validate syntax |
| Disk growing | `:GithubStats compact dry-run` | Run retention |

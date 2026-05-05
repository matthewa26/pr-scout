# Configuration

## Where the config lives

`pr-scout` looks for the config file at:

```
$XDG_CONFIG_HOME/pr-scout/config.json
```

Falling back to `~/.config/pr-scout/config.json` if `XDG_CONFIG_HOME` is unset (the standard on macOS without explicit XDG setup).

## Two ways to create one

### Interactive wizard (recommended)

```bash
pr-scout config
```

Walks through profile name → directories → GitHub user (auto-detected) → owners allowlist (auto-suggested from local clones in your chosen directories) → category selection → preview → save. Multi-profile support — runs again until you decline. See [the wizard discussion in the man page](https://github.com/matthewa26/pr-scout/blob/main/man/pr-scout.1) for full step-by-step.

### Non-interactive

```bash
pr-scout init                  # writes a single-profile starter
pr-scout init --path some/path # alternate location
pr-scout init --force          # overwrite an existing config
```

The starter is intentionally minimal — one profile named `personal` scanning `~/projects` with the default category catalog and `defaultBotAuthors` ignored.

## Schema

```json
{
  "defaultProfile": "personal",
  "profiles": {
    "<name>": {
      "directories": ["~/path/one", "~/path/two"],
      "githubUser": "optional-override",
      "scope": "currentDirectoryRepos",
      "owners": ["my-org"],
      "excludeRepos": ["foo/legacy"],
      "categories": ["changes_requested_mine", "awaiting_my_review"],
      "ignoreAuthors": ["dependabot[bot]", "renovate[bot]"]
    }
  }
}
```

All fields except `profiles` are optional. Each profile's fields are also optional — omit any field and the documented default applies.

## Profile fields

| Field | Type | Default | Purpose |
|---|---|---|---|
| `directories` | `string[]` | `[]` | Directory prefixes used to auto-resolve this profile from the current working directory. Any path beneath one of these matches. `~` expands to the home directory. |
| `githubUser` | `string` | from `gh api user` | Override the viewer login. Useful when impersonating teammates or using multiple GitHub accounts. |
| `scope` | `"currentDirectoryRepos"` \| `"discoveredOrgs"` | `"currentDirectoryRepos"` | How repos are queried. `currentDirectoryRepos` only queries the repos found via local clones. `discoveredOrgs` queries every open PR in the GitHub orgs those repos belong to (broader). |
| `owners` | `string[]` | _no restriction_ | Allowlist of GitHub owners. When set, only repos whose owner appears here are queried. Useful when scan dirs also contain unrelated OSS clones. |
| `excludeRepos` | `string[]` | `[]` | Explicit `owner/repo` slugs to skip even when discovered. |
| `categories` | `string[]` | the default catalog | Which categories this profile shows. See [categories.md](categories.md) for the full catalog. |
| `ignoreAuthors` | `string[]` | the default bot list | Login names whose PRs are filtered out. See [Bots](#bots) below. |

## Profile auto-resolution

When you run `pr-scout`, the active profile is decided in this order:

1. `--profile <name>` flag — wins outright if provided.
2. Otherwise, longest matching `directories` prefix against the current working directory (or `--directory <path>`).
3. Otherwise, `defaultProfile` from the top-level config.
4. Otherwise, no profile is applied — `pr-scout` scans the current directory with library defaults.

### Example

```json
{
  "defaultProfile": "personal",
  "profiles": {
    "work":     { "directories": ["~/work"] },
    "personal": { "directories": ["~/projects"] },
    "oss":      { "directories": ["~/oss"] }
  }
}
```

| You're in | Active profile |
|---|---|
| `~/work/some-repo` | `work` |
| `~/projects/foo` | `personal` |
| `~/projects/foo/sub/dir` | `personal` (matched on prefix) |
| `~/random` | `personal` (falls back to `defaultProfile`) |

### Longest prefix wins

```json
{
  "profiles": {
    "all":      { "directories": ["~/code"] },
    "specific": { "directories": ["~/code/work-stuff"] }
  }
}
```

In `~/code/work-stuff/repo`, both profiles match. `specific` wins because its prefix is longer.

## Bots

By default, `ignoreAuthors` includes the common bot logins:

```
dependabot, dependabot[bot]
renovate, renovate[bot]
github-actions, github-actions[bot]
claude-code, claude-code[bot]
```

To **see** Dependabot PRs (or any bot's PRs), explicitly set `ignoreAuthors` and remove that login:

```json
{
  "profiles": {
    "work": {
      "ignoreAuthors": ["renovate[bot]", "github-actions[bot]"]
    }
  }
}
```

Now Dependabot PRs surface like any human-authored PR.

Note: this only controls **PR author** filtering. Bot **reviews** (e.g. a github-actions CI status comment) are always excluded from "no reviews yet" detection so they don't mask the fact that no human has reviewed the PR. See [troubleshooting.md](troubleshooting.md) for the full rationale.

## Editing without the wizard

The config is plain JSON. Edit it in your editor of choice:

```bash
$EDITOR ~/.config/pr-scout/config.json
```

Run `pr-scout --help` to verify the changes parse correctly. If pr-scout fails to load, it falls back to library defaults and prints a warning.

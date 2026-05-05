# Output formats

`pr-scout list` (and the bare `pr-scout` invocation) supports four formats. Pick with `--format <name>` or `-f <name>`.

| Format | Default? | Stable? | Use when |
|---|---|---|---|
| `pretty` | ✓ | n/a | Reading interactively in a terminal. |
| `list` | | yes | Piping to grep / awk / less; CI logs. |
| `table` | | yes | At-a-glance dashboards or wide terminals. |
| `json` | | yes | Scripts; piping through `jq`; integrating with other tools. |

"Stable" means the field set / line shape will not change without a version bump.

## `pretty`

Default format. ANSI colors, grouped by category, with bullets. Auto-falls back to `list` when stdout isn't a TTY (so piping always produces clean output without escape codes).

```
pr-scout · viewer: @matthewa26 · profile: truthly · matches: 6 · 2026-05-04T18:30:00Z

Your PRs with changes requested (1)
  • truthly-inc/backend#43 — feat: alarm on production deployment failures
      @matthewa26 · updated 15h ago · changes requested
      https://github.com/truthly-inc/backend/pull/43

Awaiting your review (1)
  • truthly-inc/prompts#23 — [Prompt Revision] revision-2026_05_01
      @kjc999 · updated 21h ago · no reviews yet
      https://github.com/truthly-inc/prompts/pull/23
```

## `list`

Same shape as `pretty` minus the colors. Safe for any environment.

```
pr-scout · viewer: @matthewa26 · profile: truthly · matches: 6 · 2026-05-04T18:30:00Z

Your PRs with changes requested (1)
  • truthly-inc/backend#43 — feat: alarm on production deployment failures
      @matthewa26 · updated 15h ago · changes requested
      https://github.com/truthly-inc/backend/pull/43
```

## `table`

Aligned ASCII columns. Compact and grep-friendly.

```
CATEGORY                     REPO                 PR    AUTHOR      UPDATED  TITLE                                                         URL
---------------------------  -------------------  ----  ----------  -------  ------------------------------------------------------------  -----------------------------------------------
new_commits_since_my_review  truthly-inc/android  #166  eryanRM     10h ago  fix(CI): switch test + lint + deploy workflows from npm…    https://github.com/truthly-inc/android/pull/166
changes_requested_mine       truthly-inc/backend  #43   matthewa26  15h ago  feat: alarm on production deployment failures across…       https://github.com/truthly-inc/backend/pull/43
awaiting_my_review           truthly-inc/prompts  #23   kjc999      21h ago  [Prompt Revision] revision-2026_05_01_17_43_37               https://github.com/truthly-inc/prompts/pull/23
```

Title is truncated to 60 characters.

## `json`

Stable, machine-readable schema. Each element of the top-level array represents one classified PR.

```json
[
  {
    "category": "changes_requested_mine",
    "categoryDisplay": "Your PRs with changes requested",
    "repo": "truthly-inc/backend",
    "number": 43,
    "title": "feat: alarm on production deployment failures",
    "author": "matthewa26",
    "url": "https://github.com/truthly-inc/backend/pull/43",
    "createdAt": "2026-04-30T18:58:19Z",
    "updatedAt": "2026-05-02T02:04:08Z",
    "reason": "changes requested"
  }
]
```

### Schema fields (stable)

| Field | Type | Description |
|---|---|---|
| `category` | string | The category ID (see [categories.md](categories.md)). |
| `categoryDisplay` | string | Human-readable category name. |
| `repo` | string | `owner/repo` slug. |
| `number` | int | PR number within the repo. |
| `title` | string | PR title. |
| `author` | string | PR author's GitHub login. |
| `url` | string | Canonical GitHub PR URL. |
| `createdAt` | string (ISO 8601) | When the PR was opened. |
| `updatedAt` | string (ISO 8601) | When the PR was last updated. |
| `reason` | string | One-line explanation of why this category fired. |

Empty result is `[]` — never `null`.

## Compose with jq

Recipes (more in [cookbook.md](cookbook.md)):

```bash
# Just the URLs of PRs awaiting your review
pr-scout --format json | jq -r '.[] | select(.category == "awaiting_my_review") | .url'

# Count of PRs by category
pr-scout --format json | jq 'group_by(.category) | map({category: .[0].category, count: length})'

# Open every match in your browser
pr-scout --format json | jq -r '.[].url' | xargs open

# Just the new-commits-since-my-review entries, formatted as Slack message
pr-scout --format json \
  | jq -r '.[] | select(.category == "new_commits_since_my_review")
                | "• \(.repo)#\(.number) — \(.reason): \(.url)"'
```

# pr-scout

Scan open GitHub PRs across your local clones and surface only the ones that need your attention.

Built on top of [`gh`](https://cli.github.com), so it reuses your existing authentication and respects your GitHub access. No tokens to manage, no API keys to leak.

## What it shows you

- **Your PRs that have changes requested.**
- **Other people's PRs that are awaiting your review** — either you're explicitly requested or no review activity has happened yet.
- **Other people's PRs that have new commits since your last review** — you reviewed, they pushed, you should re-review.
- **Your own PRs where someone else pushed and you haven't reviewed since** — easy to miss when collaborators push directly to your branch.

The catalog of categories is configurable per profile. See [Categories](#categories).

## Install

### macOS — Homebrew

```bash
brew install matthewa26/tap/pr-scout
```

This installs both `pr-scout` and its `gh` dependency in one step.

### Any platform — from source

```bash
git clone https://github.com/matthewa26/pr-scout.git
cd pr-scout
swift build -c release
install .build/release/pr-scout /usr/local/bin/
```

### Prerequisite: GitHub CLI

`pr-scout` shells out to [`gh`](https://cli.github.com). The Homebrew formula installs it automatically. Building from source on Linux: install via the platform's package manager (apt, dnf, pacman, apk) — the tool prints platform-specific install hints on first run if `gh` is missing.

After installing, run `gh auth login` once.

## Usage

Run from any directory containing one or more git clones (recursive scan):

```bash
pr-scout                               # default: list, pretty format
pr-scout --format json                 # machine-readable
pr-scout --format table                # ASCII table
pr-scout --profile work                # use a named profile
pr-scout --directory ~/some/path       # scan a different root
pr-scout --user someoneelse            # impersonate a different GitHub viewer
pr-scout init                          # write a starter config
```

When invoked with no flags, `pr-scout` resolves the profile by matching the current working directory against the `directories` prefix on each configured profile (longest prefix wins). Falls back to `defaultProfile` if no match.

### Output formats

| Format   | Use when                                                                |
|----------|-------------------------------------------------------------------------|
| `pretty` | Default. Color + emoji-free Unicode in TTYs. Auto-falls-back to `list`. |
| `list`   | Plain bullet list, no ANSI. Safe for piping or logs.                    |
| `table`  | Aligned monospace columns. Good for at-a-glance scanning.               |
| `json`   | Stable schema for scripts. Pipe through `jq` to compose with other tools. |

## Configuration

`pr-scout` looks for `~/.config/pr-scout/config.json` (or `$XDG_CONFIG_HOME/pr-scout/config.json` if set).

The fastest way to get a working config is the interactive wizard:

```bash
pr-scout config
```

It walks you through profile name → directories → GitHub user (auto-detected) → owners allowlist (auto-suggested from local clones) → category selection → preview → save. Multi-profile support; runs again until you decline.

For non-interactive scaffolding (e.g. provisioning scripts):

```bash
pr-scout init
```

### Schema

```json
{
  "defaultProfile": "personal",
  "profiles": {
    "<name>": {
      "directories": ["~/path/one", "~/path/two"],
      "githubUser": "optional-override",
      "scope": "currentDirectoryRepos | discoveredOrgs",
      "categories": ["changes_requested_mine", "awaiting_my_review"],
      "ignoreAuthors": ["dependabot[bot]"]
    }
  }
}
```

### Profile fields

- **`directories`** — directory prefixes used to auto-resolve this profile from the CWD. Any path beneath one of these is matched (longest-prefix wins).
- **`githubUser`** — optional override of the viewer login. Useful if you switch GitHub accounts per context. Defaults to `gh api user`.
- **`scope`** — `currentDirectoryRepos` (default) queries only the repos found under `directories`; `discoveredOrgs` queries every open PR in the GitHub orgs those repos belong to (broader, catches PRs in repos you haven't cloned).
- **`owners`** — allowlist of GitHub owners (orgs or users). When set, only repos whose owner appears here are queried. Useful when you also clone OSS repos under the same root and don't want them polluting the list.
- **`excludeRepos`** — explicit `owner/repo` slugs to skip.
- **`categories`** — pick from the [catalog below](#categories). If omitted, a sensible default catalog is used.
- **`ignoreAuthors`** — login names to filter out before fetching detail. Bots are excluded by default.

### Profile auto-resolution example

```json
{
  "profiles": {
    "work":     { "directories": ["~/work"] },
    "personal": { "directories": ["~/projects"] },
    "oss":      { "directories": ["~/oss"] }
  }
}
```

- `cd ~/work/some-repo && pr-scout` → uses `work`
- `cd ~/projects/foo && pr-scout` → uses `personal`
- Anywhere else → falls back to `defaultProfile`, or scans the current directory

## Categories

| ID                              | Meaning                                                                          |
|---------------------------------|----------------------------------------------------------------------------------|
| `changes_requested_mine`        | Your PRs where reviewers have requested changes.                                 |
| `awaiting_my_review`            | Others' PRs where you're requested, or no review activity has happened yet.      |
| `new_commits_since_my_review`   | Others' PRs that have new commits pushed after your last review.                 |
| `stale_pushed_by_others`        | Your PRs where the latest commit is by someone else and you haven't responded.   |
| `mergeable_approved_mine`       | Your PRs that are approved and ready to merge.                                   |

## Cookbook

Real-world recipes you can lift directly.

### Periodic check via tmux status bar

Run pr-scout every 5 minutes and stash the count:

```bash
# in your tmux.conf
set -g status-right '#(pr-scout --format json | jq length) PRs'
```

### Open every match in the browser

```bash
pr-scout --format json | jq -r '.[].url' | xargs open
```

### Block CI on a clean queue (paranoia mode)

```bash
test "$(pr-scout --format json | jq length)" = "0" || exit 1
```

### Slack post on stale collaborations

A scheduled cron that pings you if anyone pushed to your PRs:

```bash
pr-scout --format json \
  | jq -r '.[] | select(.category == "stale_pushed_by_others")
                | "\(.repo)#\(.number) — \(.reason)"' \
  | curl -X POST -H 'Content-type: application/json' \
      --data "$(jq -Rs '{text: .}')" "$SLACK_WEBHOOK"
```

### Inspect a teammate's queue

`--user` overrides the viewer login. Useful when triaging on someone's behalf or when handing off review responsibility:

```bash
pr-scout --user some-teammate
```

### Different config per directory

Profiles auto-resolve from the working directory. Drop into the right tree and pr-scout picks the matching profile automatically — no flags needed.

### Pipe through fzf for an interactive picker

```bash
pr-scout --format list | fzf | awk '{print $2}' | xargs gh pr view --web
```

## Offline documentation

After installing via Homebrew:

```bash
man pr-scout                # full manual
pr-scout --help             # top-level usage
pr-scout list --help        # per-subcommand help
tldr pr-scout               # quick reference (when tldr-pages adds it; meanwhile see docs/pr-scout.tldr.md)
```

Long-form prose docs live under [`docs/`](docs/) in this repo:

- [Installation](docs/installation.md) · [Configuration](docs/configuration.md) · [Categories](docs/categories.md) · [Output formats](docs/output-formats.md)
- [Cookbook](docs/cookbook.md) · [Troubleshooting](docs/troubleshooting.md) · [FAQ](docs/faq.md)
- [Index](docs/index.md) — start here if you're new

## Development

```bash
git clone https://github.com/matthewa26/pr-scout.git
cd pr-scout
./scripts/setup-dev.sh   # installs the pre-commit hook + verifies the build
swift test               # 60+ tests, runs in <1s
```

The pre-commit hook runs `swift test` and blocks the commit on failure. CI runs the same suite on every PR. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full developer workflow.

To regenerate the man page after editing help text in `Sources/PRScout/main.swift`:

```bash
./scripts/generate-man.sh
```

## Why Swift

Cold start in <50ms after a one-time `swift build`, single static binary, runs natively on macOS and Linux, and Foundation is enough — no runtime deps. Easy to integrate into a tmux status line, a `cd` hook, or a periodic check.

## License

Licensed under the [Apache License, Version 2.0](LICENSE). Copyright 2026 Matthew Ayers.

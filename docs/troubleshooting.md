# Troubleshooting

## `gh: command not found` (or pr-scout exits with 127)

`pr-scout` shells out to the GitHub CLI for every query. If `gh` isn't on `PATH`, the tool prints platform-specific install hints and exits.

Fix: install `gh`. See [Installation > Prerequisite](installation.md#prerequisite-github-cli-gh).

After installing, you must also authenticate once:

```bash
gh auth login
```

## `gh auth status` says I'm logged out

Run `gh auth login` again. pr-scout uses whatever credentials `gh` has — there's no separate auth surface.

If you've been logged in but tokens have expired:

```bash
gh auth refresh
```

## I removed Dependabot from `ignoreAuthors` but its PRs still don't show

This was a bug in v0.1.0; fixed in v0.1.1. Upgrade:

```bash
brew update && brew upgrade pr-scout
pr-scout --version    # should be ≥ 0.1.1
```

If you're already on ≥ v0.1.1 and still don't see them: confirm your config actually has `dependabot[bot]` removed (not just `dependabot`) from `ignoreAuthors`. Both forms are in the default list. Edit:

```bash
$EDITOR ~/.config/pr-scout/config.json
```

Run with `--verbose` to see exactly which PRs were filtered out:

```bash
pr-scout --verbose 2>&1 | grep -i dependabot
```

## I see the same PR twice under two different owners

You probably have two clones of the same repo where the origin URLs point to different owner names. This happens after a GitHub repo rename — the old clone still references the original owner, and `gh` follows GitHub's redirect on `gh pr list --repo old/name`, returning the same PRs.

Fixed in v0.1.2 — duplicate PRs are now deduped by canonical URL. Upgrade:

```bash
brew update && brew upgrade pr-scout
```

For a permanent local fix, also update the stale clone's remote:

```bash
git -C path/to/stale-clone remote set-url origin https://github.com/<canonical-owner>/<repo>.git
```

## A PR with only a github-actions CI comment isn't surfacing in "Awaiting your review"

Fixed in v0.1.2 (initial detection) and v0.1.3 (covers bots whose login lacks the `[bot]` suffix).

If you're on ≥ v0.1.3 and still seeing this: the bot's login may not be in our known list. Check:

```bash
gh pr view <number> --repo <owner>/<repo> --json reviews
```

Look at `reviews[].author.login`. If it's a bot we haven't added to the known list (currently: `github-actions`, `dependabot`, `renovate`, `claude`, `claude-code`, `codecov`, `sonarcloud`, `sonarqubecloud`, `coderabbitai`, `copilot-pull-request-reviewer`), [open an issue](https://github.com/matthewa26/pr-scout/issues/new) and we'll extend the list.

## `dial tcp ... i/o timeout` on a specific repo

Transient network failure between your machine and `api.github.com`. `gh` retries internally but can give up. The next pr-scout invocation usually succeeds.

If it persists: check `gh api user` directly. If that also times out, the issue is your network / DNS / firewall, not pr-scout.

## Profile not auto-resolving from CWD

Verify three things:

1. The config exists at the expected path. Run `cat ~/.config/pr-scout/config.json` (or `$XDG_CONFIG_HOME/pr-scout/config.json`).
2. The current working directory matches one of the profile's `directories` prefixes. `~` must be expanded — check that `pwd` returns a path that starts with the absolute form of the configured directory.
3. The longest matching prefix is the profile you expect (longest prefix wins).

Force a specific profile to bypass auto-resolution:

```bash
pr-scout --profile work
```

## Some categories I expected aren't appearing

The catalog of categories enabled per profile is controlled by the profile's `categories` field. The default catalog is four of the five — `mergeable_approved_mine` is opt-in.

To enable everything:

```json
{
  "profiles": {
    "work": {
      "categories": [
        "changes_requested_mine",
        "awaiting_my_review",
        "new_commits_since_my_review",
        "stale_pushed_by_others",
        "mergeable_approved_mine"
      ]
    }
  }
}
```

See [categories.md](categories.md) for the full catalog and trigger conditions.

## "No matching PRs" but I know there are some

Most common causes:

1. **Wrong profile resolved.** Run `pr-scout --verbose` to see which profile the tool resolved to. Override with `--profile <name>`.
2. **`owners` allowlist filtered them out.** Check if the profile's `owners` field includes the org of the repo you expect.
3. **`excludeRepos` blocking the repo.** Check the explicit exclude list.
4. **Author is in `ignoreAuthors`.** Default list filters bot accounts. Edit if needed.
5. **PR is a draft.** Drafts are always skipped.
6. **PR doesn't match any enabled category.** See [categories.md](categories.md).

`pr-scout --verbose` prints every step of the scan, including which repos and PRs were considered.

## Slow scans

Each repo requires one `gh pr list` call plus one `gh pr view` per matching PR. With 30 repos and 50 open PRs across them, that's ~80 sequential API calls.

Mitigations:

- Use `owners` allowlist to narrow the repo set.
- Use `excludeRepos` to skip noisy repos that always have lots of PRs.
- Run with `--profile <name>` and a profile that has tight scope.
- Use `discoveredOrgs` scope only when you specifically want PRs in repos you haven't cloned — it's broader by design.

## Pre-commit hook fails after upgrading Swift

The hook runs `swift test`. If your Swift toolchain is older than what `Package.swift` requires (currently 5.9), `swift test` will fail. Update Xcode (macOS) or your Swift toolchain (Linux).

## Anything else

[Open an issue](https://github.com/matthewa26/pr-scout/issues/new). Include `pr-scout --version`, `gh --version`, and the output of running with `--verbose`.

# FAQ

## How is this different from `gh pr list`?

`gh pr list` enumerates open PRs in *one* repository. `pr-scout`:

- Enumerates open PRs across *every local clone* in your scan directories.
- Classifies each PR into a small catalog of categories targeting reviewer-attention patterns ("changes requested on my PR", "awaiting my review", "new commits since my review", etc.).
- Filters out drafts and bot PRs by default.
- Dedupes PRs that appear under multiple owner names (e.g. after a repo rename).
- Auto-resolves a config profile from your current working directory, so you can have different scopes / categories / authors per project context.

Think of `pr-scout` as `gh pr list --everywhere --classify`.

## Why Swift?

- Cold start in <50ms after a one-time build — light enough to integrate into a tmux status line, a `cd` hook, or a periodic check.
- Single static binary, runs natively on macOS and Linux.
- Foundation alone covers JSON, filesystem, HTTP, process management — no runtime dependencies.
- Strong type system catches gh-output schema drift at decode time.

## Why shell out to `gh` instead of hitting the API directly?

- **Auth.** `gh` already manages tokens, OAuth, Enterprise hosts, and refresh. pr-scout doesn't need to reimplement any of that.
- **Pagination + rate limits.** `gh` handles them transparently.
- **Future-proofing.** When GitHub changes API shapes, `gh` adapts and pr-scout inherits the fix.
- **Trust.** Users already trust `gh` with their credentials. pr-scout doesn't need a separate trust budget.

The cost is one extra process per call (~10ms overhead), which is negligible vs. the network round-trip.

## Will it ever support GitLab / Bitbucket / Gerrit / CodeCommit?

Maybe. Host-agnostic abstraction was scoped out of the initial release because each host has meaningfully different concepts (PRs vs. MRs vs. changesets) and CLI quality (gh is best-in-class; some hosts have no first-party CLI). If there's demand, the architecture can absorb additional backends behind a `Host` protocol — the work is bounded but non-trivial.

[Open an issue](https://github.com/matthewa26/pr-scout/issues/new) if you want this and we'll discuss priorities.

## Can I add a custom category?

The catalog is currently hard-coded in `Sources/PRScout/Categories.swift`. Adding one means a small code change + test:

1. Add a `case` to `CategoryKind`.
2. Add the trigger predicate in `Classifier.match()`.
3. Add a unit test.
4. Open a PR.

A future version may support user-defined categories via JSON config — but only if real demand emerges. Hard-coded keeps the catalog audited and testable.

## How do I have different settings for different projects?

Profiles. Define one per context with its own `directories`, `owners`, `categories`, and `ignoreAuthors`. They auto-resolve from your working directory.

```json
{
  "profiles": {
    "work":     { "directories": ["~/work"],     "owners": ["my-employer"] },
    "personal": { "directories": ["~/projects"], "owners": ["mygithub"] },
    "oss":      { "directories": ["~/oss"]                                  }
  }
}
```

`cd` into any subdirectory of those paths and pr-scout picks the matching profile automatically.

## Does it work with GitHub Enterprise?

Yes — anywhere `gh` works, pr-scout works. Configure `gh` for your Enterprise host (`gh auth login --hostname your-enterprise.example.com`) and pr-scout will use it transparently. The `host` is determined by `gh`'s config, not by pr-scout.

## What happens if I have a private repo I haven't cloned?

`pr-scout` only knows about repos with local clones (in the `currentDirectoryRepos` scope). To pick up uncloned repos in a GitHub org, set:

```json
{
  "profiles": {
    "work": {
      "scope": "discoveredOrgs",
      "owners": ["my-employer"]
    }
  }
}
```

This switches from "scan local clones" to "query every open PR in these orgs". You still need read access (gh handles that).

## Can I use it without any config file?

Yes — running `pr-scout` from a directory with at least one git clone works without any config. Library defaults apply: scan the current directory recursively, use the default category catalog, filter the default bot list, get the viewer login from `gh api user`.

The config file gives you profiles, scope, owner allowlist, and category customization — useful but not required.

## How are bot PRs and bot reviews handled?

- **Bot PRs** are filtered by login matching `ignoreAuthors`. The default list covers `dependabot`, `renovate`, `github-actions`, `claude-code` (with and without the `[bot]` suffix). To see those PRs, edit your profile's `ignoreAuthors` to remove the bot's login.
- **Bot reviews** are detected separately — a `github-actions` CI status comment doesn't count as "the PR has been reviewed", so a PR with only bot comments still surfaces under "no reviews yet". This is hard-coded behavior, not config-driven.

## Does it work offline?

No — pr-scout calls `gh` which calls GitHub's API. The man page (`man pr-scout`), `--help` output, and these docs are offline-readable, but actual PR queries require network.

## How do I uninstall it?

```bash
brew uninstall pr-scout
brew untap matthewa26/tap                      # optional
rm -rf ~/.config/pr-scout                       # config (kept by default)
```

## Is there a release cadence?

No fixed cadence. Patch releases (`0.x.y`) ship when bugs are reported and fixed. Minor releases (`0.x`) ship when meaningfully new features land. Pre-1.0, breaking config changes are signaled in release notes. After 1.0, semver applies.

## How do I report a bug or request a feature?

[Open an issue](https://github.com/matthewa26/pr-scout/issues/new) with:

- `pr-scout --version`
- `gh --version`
- Output of running with `--verbose`
- What you expected vs. what happened

PRs welcome — see [CONTRIBUTING.md](https://github.com/matthewa26/pr-scout/blob/main/CONTRIBUTING.md).

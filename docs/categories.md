# Categories

`pr-scout` classifies each open PR into exactly one of five built-in categories. Each category targets a specific kind of "needs your attention" pattern. You can enable a subset per profile.

| ID | Display name | Triggers when |
|---|---|---|
| `changes_requested_mine` | Your PRs with changes requested | You authored the PR and reviewers requested changes. |
| `awaiting_my_review` | Awaiting your review | Someone else's PR; you're explicitly requested OR no human has reviewed yet AND no other reviewer is on the hook. |
| `new_commits_since_my_review` | New commits since your review | Someone else's PR; you reviewed previously and new commits have landed since. |
| `stale_pushed_by_others` | Your PRs with non-author commits | You authored the PR but the latest commit is by someone else and you haven't reviewed since. |
| `mergeable_approved_mine` | Your approved PRs (ready to merge) | You authored the PR and `reviewDecision` is `APPROVED`. |

Drafts are always skipped. PRs whose author is in your `ignoreAuthors` list are filtered before classification.

## Priority

A single PR can theoretically match more than one category (e.g. a PR you authored with `CHANGES_REQUESTED` plus someone else's commits since). When that happens, the higher-priority category wins:

```
changes_requested_mine
        ↓
stale_pushed_by_others
        ↓
new_commits_since_my_review
        ↓
awaiting_my_review
        ↓
mergeable_approved_mine
```

The priority order matches what the human reviewer most likely needs to act on first.

## Per-category detail

### `changes_requested_mine`

Triggered when:

- `pr.author.login == viewer`
- `pr.reviewDecision == "CHANGES_REQUESTED"`

Reason text: `"changes requested"`

Use case: you pushed a PR, got feedback, and need to address it. This is the highest-priority category because the ball is squarely in your court.

### `awaiting_my_review`

Triggered when **either**:

1. `pr.author.login != viewer` AND `viewer` appears in `pr.reviewRequests` (you're explicitly requested), or
2. `pr.author.login != viewer` AND `pr.reviews` has no human review AND no specific reviewer is requested AND `pr.reviewDecision` is undecided (`"REVIEW_REQUIRED"`, `null`, or empty).

Reason text: `"review requested from you"` or `"no reviews yet"`

Bot reviews (`is_bot: true`, login ending in `[bot]`, or login matching the known-bot fallback list — `github-actions`, `dependabot`, `renovate`, `claude`, `claude-code`, `codecov`, `sonarcloud`, `sonarqubecloud`, `coderabbitai`, `copilot-pull-request-reviewer`) are not counted as reviews here. A PR with only a github-actions CI comment still surfaces as "no reviews yet".

If someone else (not you) is explicitly requested, the PR is **not** surfaced under "no reviews yet" — it's their queue, not yours.

### `new_commits_since_my_review`

Triggered when:

- `pr.author.login != viewer`
- You have at least one review on the PR (any state: `APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`, `DISMISSED`)
- `pr.commits` includes at least one commit with `committedDate` after your latest review's `submittedAt`

Reason text: `"N commit(s) since your <state>"` (e.g. `"3 commits since your changes requested"`)

Use case: you reviewed, the author addressed feedback (or made unrelated changes), and you should re-check.

### `stale_pushed_by_others`

Triggered when:

- `pr.author.login == viewer`
- The latest commit's author is NOT you
- You have not reviewed or commented on the PR since that commit

Reason text: `"latest commit by <login>, no review from you since"`

Use case: a collaborator (or AI agent, or coworker fixing something) pushed to your branch and you haven't acknowledged. Easy to miss when notifications get noisy.

### `mergeable_approved_mine`

Triggered when:

- `pr.author.login == viewer`
- `pr.reviewDecision == "APPROVED"`

Reason text: `"approved — ready to merge"`

Lowest priority because nothing's blocking — but useful to spot in your daily list as a "go land this" reminder.

## Customizing per profile

The default catalog enables four of the five (everything except `mergeable_approved_mine`). To override, set `categories` on the profile:

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
    },
    "oss": {
      "categories": ["awaiting_my_review", "new_commits_since_my_review"]
    }
  }
}
```

Profiles with `categories` omitted use the default catalog.

## Adding new categories

The catalog is hard-coded in `Sources/PRScout/Categories.swift`. Adding a new one means:

1. Add a `case` to `CategoryKind`.
2. Add a `displayName`.
3. Add the matching predicate in `Classifier.match()`.
4. Decide where it sits in the `priority` array.
5. Add at least one test in `Tests/PRScoutTests/ClassifierTests.swift`.

PRs welcome — see [Contributing](https://github.com/matthewa26/pr-scout/blob/main/CONTRIBUTING.md).

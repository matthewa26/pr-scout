# Contributing to pr-scout

## Getting set up

After cloning, run the dev setup script once:

```bash
./scripts/setup-dev.sh
```

This installs the `.githooks/pre-commit` hook (which runs `swift test` before every commit) and verifies the project builds.

## Running tests

```bash
swift test
```

All tests must pass before a commit goes through. If you need to bypass the hook in a genuine emergency, `git commit --no-verify` works — but CI will block the PR if anything fails.

## Submitting a pull request

1. Branch off `main`.
2. Make your changes.
3. Add or update tests under `Tests/PRScoutTests/`.
4. Verify locally with `swift test`.
5. Open a PR.

CI runs the full test suite on every PR. For first-time contributors, a maintainer must approve the workflow run before CI starts (this repo has GitHub's "Require approval for first-time contributors" setting enabled).

## Repo settings checklist (maintainer)

These are not in source control — they need to be set once in the repository's GitHub settings:

- Settings → Actions → General → "Fork pull request workflows from outside collaborators" → **Require approval for first-time contributors**
- Settings → Branches → Add rule for `main` → require status check `Test (macOS)` to pass before merging

## Coding style

- Match the existing style of the file you're editing.
- Comments explain *why*, not *what* — the code itself should make *what* obvious.
- New configuration fields go in `Config.swift` with a one-line `///` comment describing the field's purpose.
- New categories go in `Categories.swift`. Add a `displayName`, the matching predicate in `Classifier.match`, and at least one test in `ClassifierTests.swift`.

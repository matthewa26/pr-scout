# pr-scout documentation

Long-form documentation for [pr-scout](https://github.com/matthewa26/pr-scout) — a CLI for surfacing actionable GitHub PRs across local repository clones.

## Where to start

- New here? → [Installation](installation.md), then [Configuration](configuration.md)
- Want to understand what categories exist and when they fire? → [Categories](categories.md)
- Looking for practical examples? → [Cookbook](cookbook.md)
- Hit a problem? → [Troubleshooting](troubleshooting.md)
- Quick answers to common questions? → [FAQ](faq.md)

## Index

| Topic | Page |
|---|---|
| Install on macOS, Linux, or from source | [installation.md](installation.md) |
| Config schema, profiles, auto-resolution | [configuration.md](configuration.md) |
| Built-in PR categories (in depth) | [categories.md](categories.md) |
| Output formats (`json` / `table` / `list` / `pretty`) | [output-formats.md](output-formats.md) |
| Recipes: tmux, fzf, Slack, cron, prompts, jq | [cookbook.md](cookbook.md) |
| When things go wrong | [troubleshooting.md](troubleshooting.md) |
| Frequently asked | [faq.md](faq.md) |
| tldr-pages quick reference | [pr-scout.tldr.md](pr-scout.tldr.md) |

## Offline reading

After installing via Homebrew, full reference is also available via:

```bash
man pr-scout                # full manual
pr-scout --help             # top-level usage
pr-scout list --help        # per-subcommand options + discussion
```

## Contributing to these docs

These pages live in [`docs/`](https://github.com/matthewa26/pr-scout/tree/main/docs) in the main repo. Open a PR — same flow as code changes, including the test gate (which doesn't fail for docs-only PRs but does run).
